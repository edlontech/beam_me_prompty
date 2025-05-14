defmodule BeamMePrompty.Agent.Stage do
  use GenStateMachine, callback_mode: :state_functions

  alias BeamMePrompty.Agent.Dsl.{FunctionResultPart, TextPart, FunctionCallPart, DataPart}
  alias BeamMePrompty.Agent.Dsl.Message
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.MessageParser

  defstruct [
    :stage_name,
    :messages,
    :tool_responses
  ]

  def start_link(stage_name) do
    GenStateMachine.start_link(__MODULE__, stage_name, [])
  end

  @impl true
  def init(stage_name) do
    actual_stage_name =
      case stage_name do
        {s_name} when is_atom(s_name) or is_binary(s_name) -> s_name
        s_name -> s_name
      end

    {:ok, :idle, %__MODULE__{stage_name: actual_stage_name, messages: [], tool_responses: []}}
  end

  def idle(:cast, {:execute, node_name, node_def, node_ctx, caller_pid}, data) do
    updated_data =
      case do_execute_stage(node_def, node_ctx, data) do
        {:ok, result, updated_data} ->
          send(caller_pid, {:stage_response, node_name, {:ok, result}})
          updated_data

        {:error, reason, updated_data} ->
          send(caller_pid, {:stage_response, node_name, {:error, reason}})
          updated_data
      end

    # Stay in idle state, ready for next command with updated data
    {:next_state, :idle, updated_data}
  end

  def idle(_event_type, _event_content, data) do
    {:keep_state, data}
  end

  @impl true
  def terminate(_reason, _state, _data) do
    :ok
  end

  # --- Private Helper Functions for Stage Execution ---

  defp do_execute_stage(stage_node, exec_context, data) do
    global_input = exec_context[:global_input] || %{}
    dependency_results = exec_context[:dependency_results] || %{}
    inputs = Map.merge(global_input, dependency_results)

    with {:ok, llm_result, updated_messages} <-
           maybe_call_llm(stage_node.llm, inputs, data.messages) do
      updated_data = %{data | messages: updated_messages}
      {:ok, llm_result, updated_data}
    else
      {:error, reason} ->
        {:error, Errors.to_class(reason), data}

      {:error, reason, updated_messages} ->
        updated_data = %{data | messages: updated_messages}
        {:error, Errors.to_class(reason), updated_data}
    end
  end

  # --- Tool Calling Helpers ---

  defp is_function_call_response(%{function_call: %{name: name}}) when is_binary(name), do: true
  defp is_function_call_response(_), do: false

  # --- LLM Interaction Logic ---

  defp maybe_call_llm([config | _rest_configs], input, initial_messages_history)
       when is_map(config) do
    if config.model && config.llm_client do
      stage_prompt_messages = MessageParser.parse(config.messages, input) || []

      # Ensure params is a list and provide a default if it's nil or empty, though DSL should guarantee it.
      llm_params =
        case config.params do
          [p | _] -> p
          _ -> %BeamMePrompty.Agent.Dsl.LLMParams{}
        end

      process_llm_interactions(
        config.llm_client,
        config.model,
        config.tools || [],
        llm_params,
        initial_messages_history,
        stage_prompt_messages,
        5
      )
    else
      {:ok, %{}, initial_messages_history}
    end
  end

  defp maybe_call_llm([], _input, current_messages) do
    {:ok, %{}, current_messages}
  end

  defp maybe_call_llm(_, _input, current_messages) do
    {:ok, %{}, current_messages}
  end

  defp process_llm_interactions(
         _llm_client,
         _model,
         _tools,
         _params,
         acc_messages,
         _curr_req_msgs,
         0
       ) do
    {:error, :max_tool_iterations_reached, acc_messages}
  end

  defp process_llm_interactions(
         llm_client,
         model,
         available_tools,
         llm_params,
         accumulated_messages,
         current_request_messages,
         remaining_iterations
       ) do
    messages_to_send_to_llm = accumulated_messages ++ current_request_messages

    case BeamMePrompty.LLM.completion(
           llm_client,
           model,
           messages_to_send_to_llm,
           available_tools,
           llm_params
         ) do
      {:ok, llm_response} ->
        assistant_response_message = format_response(llm_response)
        history_after_llm_response = messages_to_send_to_llm ++ [assistant_response_message]

        if is_function_call_response(llm_response) do
          function_call = llm_response.function_call
          tool_name_str = function_call.name
          tool_name_atom = String.to_existing_atom(tool_name_str)
          tool_args = function_call.arguments
          tool_call_id = Map.get(function_call, :id)

          tool_def = Enum.find(available_tools, &(&1.name == tool_name_atom))

          if tool_def do
            tool_run_result =
              try do
                apply(tool_def.module, :run, [tool_args])
              rescue
                e -> {:error, {e, __STACKTRACE__}}
              end

            next_request_messages =
              case tool_run_result do
                {:ok, result_content} ->
                  [format_tool_result_as_message(tool_call_id, tool_name_str, result_content)]

                {:error, error_reason} ->
                  [format_tool_error_as_message(tool_call_id, tool_name_str, error_reason)]
              end

            process_llm_interactions(
              llm_client,
              model,
              available_tools,
              llm_params,
              history_after_llm_response,
              next_request_messages,
              remaining_iterations - 1
            )
          else
            tool_not_found_msg = [
              format_tool_error_as_message(
                tool_call_id,
                tool_name_str,
                "Tool not defined: #{tool_name_str}"
              )
            ]

            process_llm_interactions(
              llm_client,
              model,
              available_tools,
              llm_params,
              history_after_llm_response,
              tool_not_found_msg,
              remaining_iterations - 1
            )
          end
        else
          {:ok, llm_response, history_after_llm_response}
        end

      {:error, reason} ->
        {:error, reason, accumulated_messages}
    end
  end

  defp format_response(response) when is_binary(response) do
    {:assistant, [%TextPart{text: response}]}
  end

  defp format_response(%{function_call: call}) do
    {:assistant, [%FunctionCallPart{function_call: call}]}
  end

  defp format_response(response) when is_map(response) do
    {:assistant, [%DataPart{data: response}]}
  end

  defp format_tool_result_as_message(tool_call_id, fun_name, result) do
    {:user,
     [
       %FunctionResultPart{
         id: tool_call_id,
         name: fun_name,
         result: result
       }
     ]}
  end

  defp format_tool_error_as_message(tool_call_id, fun_name, error) do
    content =
      "Error executing tool #{fun_name} (call_id: #{tool_call_id || "N/A"}): #{inspect(error)}"

    {:user,
     [
       %FunctionResultPart{
         id: tool_call_id,
         name: fun_name,
         result: content
       }
     ]}
  end
end
