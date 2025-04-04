defmodule BeamMePrompty.Agent.Stage.LLMProcessor do
  @moduledoc """
  Handles LLM interactions, response validation, and the recursive tool calling loop.

  This module centralizes all LLM-related operations including:
  - Processing LLM configurations and making completion calls
  - Handling structured response validation
  - Managing the recursive tool calling flow
  - Determining when responses contain tool calls vs final content
  """
  @moduledoc section: :agent_stage_and_execution

  use TypedStruct

  require Logger

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Stage.AgentCallbacks
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
    @moduledoc section: :agent_stage_and_execution
    alias BeamMePrompty.LLM

    @type message_history :: list(LLM.message())

    field :session_id, reference()
    field :llm_client, any(), enforce: true
    field :model, String.t(), enforce: true
    field :available_tools, list(), default: []
    field :llm_params, Dsl.LLM.t(), enforce: true
    field :message_history, message_history(), default: []
    field :remaining_iterations, non_neg_integer(), default: 5
    field :agent_module, module()
    field :current_agent_state, map(), default: %{}
    field :stage_name, atom()
  end

  @doc """
  Processes LLM configuration and initiates LLM interactions if valid.
  """

  @spec maybe_call_llm(
          config :: Dsl.LLM.t() | list(Dsl.LLM.t()),
          input :: map(),
          initial_messages_history :: __MODULE__.Context.message_history(),
          agent_module :: module(),
          current_agent_state :: map(),
          session_id :: reference(),
          stage_name :: atom()
        ) ::
          {
            :ok,
            llm_response :: list(Dsl.Part.parts()),
            chat_history :: __MODULE__.Context.message_history(),
            context :: map()
          }
          | {
              :error,
              error :: Errors.ExecutionError.t(),
              chat_history :: __MODULE__.Context.message_history(),
              context :: map()
            }
  def maybe_call_llm(
        [config | _],
        input,
        initial_messages_history,
        agent_module,
        current_agent_state,
        session_id,
        stage_name
      ),
      do:
        maybe_call_llm(
          config,
          input,
          initial_messages_history,
          agent_module,
          current_agent_state,
          session_id,
          stage_name
        )

  def maybe_call_llm(
        config,
        input,
        initial_messages_history,
        agent_module,
        current_agent_state,
        session_id,
        stage_name
      )
      when is_map(config) do
    llm_params = extract_llm_params(config.params)
    tools = Enum.map(config.tools, & &1.tool_info())

    messages =
      MessageManager.prepare_messages_for_llm(
        config,
        input,
        initial_messages_history
      )

    context = %Context{
      session_id: session_id,
      llm_client: config.llm_client,
      model: config.model,
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

    {:ok, [], current_messages, current_agent_state}
  end

  def maybe_call_llm(
        _unhandled_config,
        _input,
        current_messages,
        _agent_module,
        current_agent_state,
        session_id,
        stage_name
      ) do
    log_llm_interaction(session_id, "unhandled_config_format", %{})

    {:error, Errors.ExecutionError.exception(stage: stage_name, cause: :unhandled_config_format),
     current_messages, current_agent_state}
  end

  defp process_llm_interactions(
         %Context{remaining_iterations: 0} = context,
         _current_request_messages
       ) do
    log_llm_interaction(context, "max_iterations_reached", %{iterations: 0})

    {:error, Errors.ExecutionError.exception(cause: :max_tool_iterations_reached),
     context.message_history, context.current_agent_state}
  end

  defp process_llm_interactions(%Context{} = context, current_request_messages) do
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

  defp handle_llm_response(%Context{} = context, llm_response_content) do
    formatted_message = MessageManager.format_response(llm_response_content)

    {content_message, function_calls} =
      MessageManager.separate_function_calls(formatted_message)

    case {content_message, function_calls} do
      {{:assistant, []}, []} ->
        log_llm_interaction(context, "empty_response", %{})

        {:error, Errors.ExecutionError.exception(cause: :empty_llm_response),
         context.message_history, context.current_agent_state}

      {{:assistant, _parts}, []} ->
        log_llm_interaction(context, "final_response", %{
          content_type: "multi_part",
          part_count: length(elem(content_message, 1))
        })

        {:ok, llm_response_content, context.message_history, context.current_agent_state}

      {_, tool_calls} when tool_calls != [] ->
        process_multi_part_response(context, content_message, tool_calls)
    end
  end

  defp process_multi_part_response(context, {:assistant, content_parts}, tool_calls) do
    log_llm_interaction(context, "multi_part_response", %{
      content_count: length(content_parts),
      tool_count: length(tool_calls)
    })

    tool_results =
      Enum.map(tool_calls, fn %FunctionCallPart{function_call: call} ->
        tool_info = ToolExecutor.extract_tool_info(%{function_call: call})

        case execute_single_tool_call(context, tool_info) do
          {:ok, _updated_context, result} ->
            {:ok, result, call[:id], call[:name]}

          {:error, reason} ->
            {:error, reason, call[:id], call[:name]}
        end
      end)

    tool_result_message = MessageManager.format_multiple_tool_results(tool_results)

    next_messages =
      if content_parts == [] do
        [tool_result_message]
      else
        MessageManager.merge_intermediate_content_with_results(content_parts, tool_result_message)
      end

    final_context = update_context_from_tool_results(context, tool_results)

    process_llm_interactions(
      %Context{final_context | remaining_iterations: final_context.remaining_iterations - 1},
      next_messages
    )
  end

  defp execute_single_tool_call(context, tool_info) do
    {tool_call_status, agent_state_after_tool_call_cb} =
      AgentCallbacks.call_tool_call(
        context.agent_module,
        tool_info.tool_name,
        tool_info.tool_args,
        context.current_agent_state
      )

    updated_agent_state_post_handle_tool_call =
      AgentCallbacks.update_agent_state_from_callback(
        tool_call_status,
        agent_state_after_tool_call_cb,
        context.current_agent_state
      )

    tool_definition =
      ToolExecutor.find_tool_definition(context.available_tools, tool_info.tool_name)

    if tool_definition do
      Telemetry.tool_execution_start(
        context.agent_module,
        context.session_id,
        context.stage_name,
        tool_info.tool_name,
        tool_info.tool_args
      )

      actual_tool_run_result =
        ToolExecutor.execute_tool(tool_definition, tool_info.tool_args, %{
          memory_manager: updated_agent_state_post_handle_tool_call[:memory_manager],
          agent_module: context.agent_module,
          session_id: context.session_id,
          stage_name: context.stage_name
        })

      {tool_result_status, agent_state_after_tool_result_cb} =
        AgentCallbacks.call_tool_result(
          context.agent_module,
          tool_info.tool_name,
          actual_tool_run_result,
          updated_agent_state_post_handle_tool_call
        )

      final_agent_state =
        AgentCallbacks.update_agent_state_from_callback(
          tool_result_status,
          agent_state_after_tool_result_cb,
          updated_agent_state_post_handle_tool_call
        )

      tool_status = if elem(actual_tool_run_result, 0) == :ok, do: :ok, else: :error

      Telemetry.tool_execution_stop(
        context.agent_module,
        context.session_id,
        context.stage_name,
        tool_info.tool_name,
        tool_status,
        actual_tool_run_result
      )

      updated_context = %Context{context | current_agent_state: final_agent_state}

      case actual_tool_run_result do
        {:ok, result} -> {:ok, updated_context, result}
        {:error, _} = error -> error
      end
    else
      error_content = "Tool not defined: #{tool_info.tool_name}"

      Telemetry.tool_execution_start(
        context.agent_module,
        context.session_id,
        context.stage_name,
        tool_info.tool_name,
        tool_info.tool_args
      )

      Telemetry.tool_execution_stop(
        context.agent_module,
        context.session_id,
        context.stage_name,
        tool_info.tool_name,
        :error,
        error_content
      )

      {:error, LLMErrors.ToolError.exception(module: __MODULE__, cause: error_content)}
    end
  end

  defp update_context_from_tool_results(context, tool_results) do
    last_updated_context =
      tool_results
      |> Enum.reverse()
      |> Enum.find_value(context, fn
        {:ok, updated_context, _result} -> updated_context
        _ -> nil
      end)

    last_updated_context || context
  end

  defp validate_structured_response(llm_response, llm_params) do
    case llm_params.structured_response do
      nil ->
        {:ok, llm_response}

      schema ->
        response_data = MessageManager.fetch_data_part_from_response(llm_response)

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

  defp log_llm_interaction(session_id, event, metadata),
    do:
      Logger.debug(
        "[BeamMePrompty] (sid: #{inspect(session_id)}) LLMProcessor: #{inspect(event)} - #{inspect(metadata)}"
      )

  defp typeof(value) when is_binary(value), do: "string"
  defp typeof(value) when is_map(value), do: "map"
  defp typeof(value) when is_list(value), do: "list"
  defp typeof(_value), do: "other"

  defp extract_llm_params(params) do
    case params do
      [p | _] -> p
      _ -> %BeamMePrompty.Agent.Dsl.LLMParams{}
    end
  end
end
