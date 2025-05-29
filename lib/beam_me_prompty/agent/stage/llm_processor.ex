defmodule BeamMePrompty.Agent.Stage.LLMProcessor do
  @moduledoc """
  Handles LLM interactions, response validation, and the recursive tool calling loop.

  This module centralizes all LLM-related operations including:
  - Processing LLM configurations and making completion calls
  - Handling structured response validation
  - Managing the recursive tool calling flow
  - Determining when responses contain tool calls vs final content
  """

  use TypedStruct

  require Logger

  alias BeamMePrompty.Agent.Stage.Config
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.Agent.Stage.ToolExecutor
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors, as: LLMErrors
  alias BeamMePrompty.Telemetry
  alias BeamMePrompty.Validator

  typedstruct module: Context do
    @moduledoc """
    Context struct for LLM processing operations.

    Encapsulates all the parameters needed for LLM interactions,
    making function signatures cleaner and easier to maintain.
    """

    field :session_id, String.t() | nil, default: nil
    field :llm_client, any(), enforce: true
    field :model, String.t(), enforce: true
    field :available_tools, list(), default: []
    field :llm_params, map(), enforce: true
    field :message_history, list(), default: []
    field :remaining_iterations, non_neg_integer(), default: 5
    field :agent_module, module() | nil, default: nil
    field :current_agent_state, map(), default: %{}
    field :stage_name, atom() | nil, default: nil
  end

  @doc """
  Processes LLM configuration and initiates LLM interactions if valid.
  """
  def maybe_call_llm(
        [config | _rest_configs],
        input,
        initial_messages_history,
        agent_module,
        current_agent_state,
        session_id,
        stage_name
      )
      when is_map(config) do
    case validate_llm_config(config) do
      {:ok, validated_config} ->
        llm_params = extract_llm_params(validated_config.params)
        tools = Enum.map(validated_config.tools, & &1.tool_info())

        messages =
          MessageManager.prepare_messages_for_llm(
            validated_config,
            input,
            initial_messages_history
          )

        context = %Context{
          session_id: session_id,
          llm_client: validated_config.llm_client,
          model: validated_config.model,
          available_tools: tools,
          llm_params: llm_params,
          message_history: initial_messages_history,
          remaining_iterations: Config.default_max_tool_iterations(),
          agent_module: agent_module,
          current_agent_state: current_agent_state,
          stage_name: stage_name
        }

        log_llm_interaction(context, "starting_llm_processing", %{
          model: context.model,
          tool_count: length(tools),
          message_count: length(messages)
        })

        process_llm_interactions(context, messages)

      {:error, reason} ->
        log_llm_interaction(session_id, "config_validation_failed", %{reason: reason})

        {:ok, %{}, initial_messages_history, current_agent_state}
    end
  end

  def maybe_call_llm(
        [],
        _input,
        current_messages,
        _agent_module,
        current_agent_state,
        session_id,
        _stage_name
      ) do
    log_llm_interaction(session_id, "no_llm_config", %{})
    {:ok, %{}, current_messages, current_agent_state}
  end

  def maybe_call_llm(
        _unhandled_config,
        _input,
        current_messages,
        _agent_module,
        current_agent_state,
        session_id,
        _stage_name
      ) do
    log_llm_interaction(session_id, "unhandled_config_format", %{})
    {:ok, %{}, current_messages, current_agent_state}
  end

  @doc """
  Handles the recursive LLM interaction loop with tool calling support.
  """
  def process_llm_interactions(
        %Context{remaining_iterations: 0} = context,
        _current_request_messages
      ) do
    log_llm_interaction(context, "max_iterations_reached", %{iterations: 0})

    {:error, Errors.ExecutionError.exception(cause: :max_tool_iterations_reached),
     context.message_history, context.current_agent_state}
  end

  def process_llm_interactions(%Context{} = context, current_request_messages) do
    llm_client_module_for_telemetry =
      if is_tuple(context.llm_client), do: elem(context.llm_client, 0), else: context.llm_client

    messages_to_send_to_llm =
      MessageManager.combine_messages_for_llm(context.message_history, current_request_messages)

    Telemetry.llm_call_start(
      context.agent_module,
      context.session_id,
      context.stage_name,
      llm_client_module_for_telemetry,
      context.model,
      Enum.count(messages_to_send_to_llm),
      Enum.count(context.available_tools)
    )

    log_llm_interaction(context, "sending_request", %{
      message_count: length(messages_to_send_to_llm),
      remaining_iterations: context.remaining_iterations
    })

    {llm_client, opts} = normalize_llm_client(context.llm_client)

    case BeamMePrompty.LLM.completion(
           llm_client,
           context.model,
           messages_to_send_to_llm,
           context.llm_params,
           context.available_tools,
           opts
         ) do
      {:ok, llm_response_content} ->
        handle_llm_completion_success(
          context,
          llm_response_content,
          messages_to_send_to_llm
        )

      # The llm_call_stop for successful case is handled in handle_llm_completion_success

      {:error, reason} ->
        Telemetry.llm_call_stop(
          context.agent_module,
          context.session_id,
          context.stage_name,
          llm_client_module_for_telemetry,
          context.model,
          :error,
          reason
        )

        log_llm_interaction(context, "completion_failed", %{reason: reason})
        {:error, reason, context.message_history, context.current_agent_state}
    end
  end

  @doc """
  Processes LLM response and determines if it contains tool calls or final content.
  """
  def handle_llm_response(%Context{} = context, llm_response_content) do
    case function_call_response(llm_response_content) do
      {:ok, final_llm_content} ->
        log_llm_interaction(context, "final_response", %{content_type: typeof(final_llm_content)})
        {:ok, final_llm_content, context.message_history, context.current_agent_state}

      {:tool, tool_function_call_part} ->
        log_llm_interaction(context, "tool_call_detected", %{
          tool_name: get_in(tool_function_call_part, [:function_call, :name])
        })

        tool_info = ToolExecutor.extract_tool_info(tool_function_call_part)

        case ToolExecutor.process_tool_call(
               tool_info,
               context.available_tools,
               context.llm_client,
               context.model,
               context.llm_params,
               context.message_history,
               context.remaining_iterations,
               context.agent_module,
               context.current_agent_state,
               context.stage_name,
               context.session_id
             ) do
          {
            :continue_llm_interactions,
            llm_client,
            model,
            available_tools,
            llm_params,
            message_history,
            next_request_messages,
            remaining_iterations,
            agent_module,
            updated_agent_state
          } ->
            updated_context = %Context{
              context
              | llm_client: llm_client,
                model: model,
                available_tools: available_tools,
                llm_params: llm_params,
                message_history: message_history,
                remaining_iterations: remaining_iterations,
                agent_module: agent_module,
                current_agent_state: updated_agent_state
            }

            process_llm_interactions(updated_context, next_request_messages)
        end
    end
  end

  @doc """
  Determines if an LLM response contains function calls or is final content.
  """
  def function_call_response(%{function_call: %{name: name}} = response) when is_binary(name),
    do: {:tool, response}

  def function_call_response(parts) when is_list(parts) do
    case Enum.find(parts, &is_map_key(&1, :function_call)) do
      nil -> {:ok, parts}
      tool -> {:tool, tool}
    end
  end

  def function_call_response(response), do: {:ok, response}

  @doc """
  Validates structured responses against schema if configured.
  """
  def validate_structured_response(llm_response, llm_params) do
    case llm_params.structured_response do
      nil ->
        {:ok, llm_response}

      schema ->
        response_data = MessageManager.normalize_response_for_validation(llm_response)

        case Validator.validate(schema, response_data) do
          {:ok, validated_data} ->
            {:ok, validated_data}

          {:error, validation_error} ->
            Logger.warning(
              "[BeamMePrompty] LLM response validation failed: #{inspect(validation_error)}"
            )

            {:error, validation_error}
        end
    end
  end

  # --- Private Helper Functions ---

  defp handle_llm_completion_success(context, llm_response_content, messages_to_send_to_llm) do
    case validate_structured_response(llm_response_content, context.llm_params) do
      {:ok, validated_response} ->
        log_llm_interaction(context, "response_validated", %{
          response_type: typeof(validated_response)
        })

        assistant_response_message = MessageManager.format_response(validated_response)

        history_after_llm_response =
          MessageManager.append_assistant_response(
            messages_to_send_to_llm,
            assistant_response_message
          )

        updated_context = %Context{context | message_history: history_after_llm_response}

        # Telemetry stop for OK is called here because this is the point of successful receipt and validation before further processing (like tool calls).
        llm_client_module_for_telemetry =
          if is_tuple(context.llm_client),
            do: elem(context.llm_client, 0),
            else: context.llm_client

        Telemetry.llm_call_stop(
          context.agent_module,
          context.session_id,
          context.stage_name,
          llm_client_module_for_telemetry,
          context.model,
          :ok,
          validated_response
        )

        handle_llm_response(updated_context, validated_response)

      {:error, validation_error} ->
        llm_client_module_for_telemetry =
          if is_tuple(context.llm_client),
            do: elem(context.llm_client, 0),
            else: context.llm_client

        Telemetry.llm_call_stop(
          context.agent_module,
          context.session_id,
          context.stage_name,
          llm_client_module_for_telemetry,
          context.model,
          :error,
          validation_error
        )

        log_llm_interaction(context, "validation_failed", %{error: validation_error})
        {:error, validation_error, context.message_history, context.current_agent_state}
    end
  end

  defp normalize_llm_client(llm_client) do
    if is_tuple(llm_client), do: llm_client, else: {llm_client, []}
  end

  defp log_llm_interaction(context, event, metadata) when is_struct(context),
    do: log_llm_interaction(context.session_id, event, metadata)

  defp log_llm_interaction(session_id, event, metadata) do
    Logger.debug("[BeamMePrompty] (sid: #{inspect(session_id)}) LLMProcessor: #{inspect(event)}")
    Logger.debug("#{inspect(metadata)}")
  end

  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(_value), do: "other"

  defp validate_llm_config(config) do
    cond do
      is_nil(config.model) ->
        {:error,
         LLMErrors.InvalidConfig.exception(
           module: __MODULE__,
           cause: :missing_model
         )}

      is_nil(config.llm_client) ->
        {:error,
         LLMErrors.InvalidConfig.exception(
           module: __MODULE__,
           cause: :missing_llm_client
         )}

      true ->
        {:ok, config}
    end
  end

  defp extract_llm_params(params) do
    case params do
      [p | _] -> p
      _ -> %BeamMePrompty.Agent.Dsl.LLMParams{}
    end
  end
end
