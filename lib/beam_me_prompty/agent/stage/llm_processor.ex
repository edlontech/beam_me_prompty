defmodule BeamMePrompty.Agent.Stage.LLMProcessor do
  @moduledoc """
  Handles LLM interactions, response validation, and the recursive tool calling loop.

  This module centralizes all LLM-related operations including:
  - Processing LLM configurations and making completion calls
  - Handling structured response validation
  - Managing the recursive tool calling flow
  - Determining when responses contain tool calls vs final content
  """

  require Logger

  alias BeamMePrompty.Agent.Stage.Config
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.Agent.Stage.ToolExecutor
  alias BeamMePrompty.Validator

  @doc """
  Processes LLM configuration and initiates LLM interactions if valid.
  """
  def maybe_call_llm(
        [config | _rest_configs],
        input,
        initial_messages_history,
        agent_module,
        current_agent_state
      )
      when is_map(config) do
    if config.model && config.llm_client do
      llm_params =
        case config.params do
          [p | _] -> p
          _ -> %BeamMePrompty.Agent.Dsl.LLMParams{}
        end

      tools = Enum.map(config.tools, & &1.tool_info())

      messages = MessageManager.prepare_messages_for_llm(config, input, initial_messages_history)

      process_llm_interactions(
        config.llm_client,
        config.model,
        tools,
        llm_params,
        initial_messages_history,
        messages,
        Config.default_max_tool_iterations(),
        agent_module,
        current_agent_state
      )
    else
      {:ok, %{}, initial_messages_history, current_agent_state}
    end
  end

  def maybe_call_llm([], _input, current_messages, _agent_module, current_agent_state) do
    {:ok, %{}, current_messages, current_agent_state}
  end

  def maybe_call_llm(
        _unhandled_config,
        _input,
        current_messages,
        _agent_module,
        current_agent_state
      ) do
    {:ok, %{}, current_messages, current_agent_state}
  end

  @doc """
  Handles the recursive LLM interaction loop with tool calling support.
  """
  def process_llm_interactions(
        _llm_client,
        _model,
        _tools,
        _params,
        acc_messages,
        _curr_req_msgs,
        # Max iterations reached
        0,
        _agent_module,
        current_agent_state
      ) do
    {:error, :max_tool_iterations_reached, acc_messages, current_agent_state}
  end

  def process_llm_interactions(
        llm_client,
        model,
        available_tools,
        llm_params,
        accumulated_messages,
        current_request_messages,
        remaining_iterations,
        agent_module,
        current_agent_state
      ) do
    messages_to_send_to_llm =
      MessageManager.combine_messages_for_llm(accumulated_messages, current_request_messages)

    {llm_client, opts} = if is_tuple(llm_client), do: llm_client, else: {llm_client, []}

    case BeamMePrompty.LLM.completion(
           llm_client,
           model,
           messages_to_send_to_llm,
           llm_params,
           available_tools,
           opts
         ) do
      {:ok, llm_response_content} ->
        case validate_structured_response(llm_response_content, llm_params) do
          {:ok, validated_response} ->
            assistant_response_message = MessageManager.format_response(validated_response)

            history_after_llm_response =
              MessageManager.append_assistant_response(
                messages_to_send_to_llm,
                assistant_response_message
              )

            handle_llm_response(
              validated_response,
              llm_client,
              model,
              available_tools,
              llm_params,
              history_after_llm_response,
              remaining_iterations,
              agent_module,
              current_agent_state
            )

          {:error, validation_error} ->
            {:error, validation_error, accumulated_messages, current_agent_state}
        end

      {:error, reason} ->
        {:error, reason, accumulated_messages, current_agent_state}
    end
  end

  @doc """
  Processes LLM response and determines if it contains tool calls or final content.
  """
  def handle_llm_response(
        llm_response_content,
        llm_client,
        model,
        available_tools,
        llm_params,
        message_history,
        remaining_iterations,
        agent_module,
        current_agent_state
      ) do
    case function_call_response(llm_response_content) do
      {:ok, final_llm_content} ->
        {:ok, final_llm_content, message_history, current_agent_state}

      {:tool, tool_function_call_part} ->
        tool_info = ToolExecutor.extract_tool_info(tool_function_call_part)

        case ToolExecutor.process_tool_call(
               tool_info,
               available_tools,
               llm_client,
               model,
               llm_params,
               message_history,
               remaining_iterations,
               agent_module,
               current_agent_state
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
            process_llm_interactions(
              llm_client,
              model,
              available_tools,
              llm_params,
              message_history,
              next_request_messages,
              remaining_iterations,
              agent_module,
              updated_agent_state
            )
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
end
