defmodule BeamMePrompty.Agent.Stage do
  @moduledoc """
  A GenStateMachine implementation that handles the execution of individual stages within a BeamMePrompty Agent's DAG.

  This module is responsible for:

  * Processing LLM interactions for a single stage/node in the execution graph
  * Handling tool calling functionality, allowing LLMs to invoke tools during execution
  * Managing message history and state for each stage
  * Communicating results back to the parent agent process

  Each stage operates independently, processing its assigned node's configuration, executing
  LLM calls with appropriate context, handling any tool invocations, and returning the final
  result to the caller.

  The state machine primarily stays in an `:idle` state, processing execution requests 
  as they arrive and maintaining its conversation history between executions.

  This module is part of the internal execution engine of BeamMePrompty and is typically
  managed by the `BeamMePrompty.Agent.Internals` module through a supervisor.
  """

  use GenStateMachine, callback_mode: :state_functions

  alias BeamMePrompty.Agent.Dsl.{FunctionResultPart, TextPart, FunctionCallPart, DataPart}
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.MessageParser

  defstruct [
    :stage_name,
    :messages,
    :tool_responses,
    # Added to store the agent module implementation
    :agent_module,
    # Added to store and manage agent's state locally
    :current_agent_state
  ]

  @doc false
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

    # Initialize new fields
    initial_data = %__MODULE__{
      stage_name: actual_stage_name,
      messages: [],
      tool_responses: [],
      # Will be set on first execute
      agent_module: nil,
      # Will be set on first execute
      current_agent_state: %{}
    }

    {:ok, :idle, initial_data}
  end

  def idle(:cast, {:execute, node_name, node_def, node_ctx, caller_pid}, data) do
    # Store agent_module and current_agent_state from node_ctx
    # node_ctx should contain :agent_module and :current_agent_state from Internals
    agent_module_from_ctx = node_ctx[:agent_module]
    agent_state_from_ctx = node_ctx[:current_agent_state]

    data_with_agent_context = %{
      data
      | agent_module: agent_module_from_ctx,
        current_agent_state: agent_state_from_ctx
    }

    # Call agent's handle_stage_start
    # handle_stage_start(stage :: map(), inner_state :: map()) :: :ok
    # This callback is for side-effects and doesn't modify agent state directly here.
    if agent_module_from_ctx do
      agent_module_from_ctx.handle_stage_start(node_def, agent_state_from_ctx)
    end

    # Proceed with stage execution, passing the full data struct which now includes agent context
    # do_execute_stage will now return {status, payload, updated_stage_data_including_agent_state}
    {stage_execution_result, result_payload, final_stage_data} =
      do_execute_stage(node_def, node_ctx, data_with_agent_context)

    # Send response back to Internals, including the final agent state from this stage
    case stage_execution_result do
      :ok ->
        send(
          caller_pid,
          {:stage_response, node_name, {:ok, result_payload},
           final_stage_data.current_agent_state}
        )

      :error ->
        send(
          caller_pid,
          {:stage_response, node_name, {:error, result_payload},
           final_stage_data.current_agent_state}
        )
    end

    # Stay in idle state, ready for next command with updated data (including potentially changed agent_state)
    {:next_state, :idle, final_stage_data}
  end

  def idle(_event_type, _event_content, data) do
    {:keep_state, data}
  end

  @impl true
  def terminate(_reason, _state, _data) do
    :ok
  end

  # --- Private Helper Functions for Stage Execution ---

  # do_execute_stage now returns a tuple: {:ok | :error, result_payload, updated_data_for_state}
  defp do_execute_stage(stage_node_def, exec_context, stage_data) do
    global_input = exec_context[:global_input] || %{}
    dependency_results = exec_context[:dependency_results] || %{}
    inputs_for_llm = Map.merge(global_input, dependency_results)

    # Pass agent_module and current_agent_state from stage_data to maybe_call_llm
    case maybe_call_llm(
           stage_node_def.llm,
           inputs_for_llm,
           stage_data.messages,
           # Pass agent_module from stage_data
           stage_data.agent_module,
           # Pass current_agent_state from stage_data
           stage_data.current_agent_state
         ) do
      # Expecting maybe_call_llm to return agent_state potentially modified by LLM/tools
      {:ok, llm_result, updated_messages_history, final_agent_state_after_llm} ->
        updated_stage_data = %{
          stage_data
          | messages: updated_messages_history,
            # Persist agent state changes
            current_agent_state: final_agent_state_after_llm
        }

        {:ok, llm_result, updated_stage_data}

      {:error, error_reason, updated_messages_history, final_agent_state_after_llm_error} ->
        updated_stage_data_on_error = %{
          stage_data
          | messages: updated_messages_history,
            # Persist state even on error
            current_agent_state: final_agent_state_after_llm_error
        }

        {:error, Errors.to_class(error_reason), updated_stage_data_on_error}

      # Fallback for cases where maybe_call_llm might not return the 4-tuple (e.g., no LLM call paths)
      # These imply no direct change to agent_state within maybe_call_llm itself for that path.
      {:ok, llm_result, updated_messages_history} ->
        updated_stage_data = %{stage_data | messages: updated_messages_history}
        {:ok, llm_result, updated_stage_data}

      {:error, error_reason} ->
        {:error, Errors.to_class(error_reason), stage_data}
    end
  end

  # --- Tool Calling Helpers ---

  defp function_call_response(%{function_call: %{name: name}} = response) when is_binary(name),
    do: {:tool, response}

  defp function_call_response(parts) when is_list(parts) do
    case Enum.find(parts, &is_map_key(&1, :function_call)) do
      nil -> {:ok, parts}
      tool -> {:tool, tool}
    end
  end

  defp function_call_response(response), do: {:ok, response}

  # --- LLM Interaction Logic ---

  # Updated to accept and return agent_module and current_agent_state
  defp maybe_call_llm(
         [config | _rest_configs],
         input,
         initial_messages_history,
         agent_module,
         current_agent_state
       )
       when is_map(config) do
    if config.model && config.llm_client do
      stage_prompt_messages = MessageParser.parse(config.messages, input) || []

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
        # Max iterations
        5,
        agent_module,
        # Pass current agent state
        current_agent_state
      )
    else
      # No LLM configured for this stage, return current agent state unchanged
      {:ok, %{}, initial_messages_history, current_agent_state}
    end
  end

  defp maybe_call_llm([], _input, current_messages, _agent_module, current_agent_state) do
    # No LLM configurations, return current agent state unchanged
    {:ok, %{}, current_messages, current_agent_state}
  end

  # Fallback for non-map config or other cases, return current agent state unchanged
  defp maybe_call_llm(
         _unhandled_config,
         _input,
         current_messages,
         _agent_module,
         current_agent_state
       ) do
    {:ok, %{}, current_messages, current_agent_state}
  end

  # Updated to accept and return agent_module and current_agent_state
  defp process_llm_interactions(
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

  defp process_llm_interactions(
         llm_client,
         model,
         available_tools,
         llm_params,
         accumulated_messages,
         current_request_messages,
         remaining_iterations,
         # Added
         agent_module,
         # Added
         current_agent_state
       ) do
    messages_to_send_to_llm = accumulated_messages ++ current_request_messages

    case BeamMePrompty.LLM.completion(
           llm_client,
           model,
           messages_to_send_to_llm,
           available_tools,
           llm_params
         ) do
      {:ok, llm_response_content} ->
        assistant_response_message = format_response(llm_response_content)
        history_after_llm_response = messages_to_send_to_llm ++ [assistant_response_message]

        handle_llm_response(
          llm_response_content,
          llm_client,
          model,
          available_tools,
          llm_params,
          history_after_llm_response,
          remaining_iterations,
          # Pass through
          agent_module,
          # Pass through
          current_agent_state
        )

      {:error, reason} ->
        # Return current agent state on error, along with messages
        {:error, reason, accumulated_messages, current_agent_state}
    end
  end

  # Updated to accept and return agent_module and current_agent_state
  defp handle_llm_response(
         llm_response_content,
         llm_client,
         model,
         available_tools,
         llm_params,
         message_history,
         remaining_iterations,
         # Added
         agent_module,
         # Added
         current_agent_state
       ) do
    case function_call_response(llm_response_content) do
      # No tool call, direct response
      {:ok, final_llm_content} ->
        # Return current agent state, as no tool interaction modified it here
        {:ok, final_llm_content, message_history, current_agent_state}

      # LLM wants to call a tool
      {:tool, tool_function_call_part} ->
        function_call_details = tool_function_call_part.function_call
        tool_name_atom = String.to_existing_atom(function_call_details.name)

        parsed_tool_info = %{
          tool_name: tool_name_atom,
          tool_args: function_call_details.arguments,
          tool_call_id: Map.get(function_call_details, :id)
        }

        # Call agent's handle_tool_call before actual tool execution
        # handle_tool_call(tool_name :: atom(), tool_args :: map(), inner_state :: map())
        {tool_call_status, agent_state_after_tool_call_cb} =
          if agent_module do
            agent_module.handle_tool_call(
              parsed_tool_info.tool_name,
              parsed_tool_info.tool_args,
              current_agent_state
            )
          else
            # This case should ideally not be reached if agent_module is consistently passed
            {:ok, current_agent_state}
          end

        updated_agent_state_post_handle_tool_call =
          case tool_call_status do
            :ok -> agent_state_after_tool_call_cb
            # Keep original state on error from callback
            _ -> current_agent_state
          end

        tool_definition = Enum.find(available_tools, &(&1.name == parsed_tool_info.tool_name))

        handle_tool_execution(
          tool_definition,
          parsed_tool_info,
          llm_client,
          model,
          available_tools,
          llm_params,
          message_history,
          remaining_iterations - 1,
          agent_module,
          updated_agent_state_post_handle_tool_call
        )
    end
  end

  # Updated to accept and return agent_module and current_agent_state
  defp handle_tool_execution(
         # Tool definition not found
         nil,
         # Contains :tool_name, :tool_args, :tool_call_id
         tool_info,
         llm_client,
         model,
         available_tools,
         llm_params,
         message_history,
         remaining_iterations,
         # Added
         agent_module,
         # Added
         current_agent_state
       ) do
    error_content_for_llm = "Tool not defined: #{tool_info.tool_name}"

    tool_not_found_msg_to_llm = [
      format_tool_error_as_message(
        tool_info.tool_call_id,
        tool_info.tool_name,
        error_content_for_llm
      )
    ]

    # Call agent's handle_tool_result (for the error of tool not found)
    # handle_tool_result(tool_name :: atom(), result :: term(), inner_state :: map())
    tool_execution_outcome_for_agent = {:error, error_content_for_llm}

    {tool_result_status, agent_state_after_tool_result_cb} =
      if agent_module do
        agent_module.handle_tool_result(
          tool_info.tool_name,
          tool_execution_outcome_for_agent,
          current_agent_state
        )
      else
        # Should not happen
        {:ok, current_agent_state}
      end

    updated_agent_state_post_tool_result_cb =
      case tool_result_status do
        :ok -> agent_state_after_tool_result_cb
        # Keep state on error from callback
        _ -> current_agent_state
      end

    process_llm_interactions(
      llm_client,
      model,
      available_tools,
      llm_params,
      message_history,
      tool_not_found_msg_to_llm,
      remaining_iterations,
      agent_module,
      # Pass the updated agent state
      updated_agent_state_post_tool_result_cb
    )
  end

  defp handle_tool_execution(
         # Tool definition found
         tool_def,
         # Contains :tool_name, :tool_args, :tool_call_id
         tool_info,
         llm_client,
         model,
         available_tools,
         llm_params,
         message_history,
         remaining_iterations,
         # Added
         agent_module,
         # Added
         current_agent_state
       ) do
    actual_tool_run_result = execute_tool(tool_def, tool_info.tool_args)

    # Call agent's handle_tool_result with the actual tool execution outcome
    {tool_result_status, agent_state_after_tool_result_cb} =
      if agent_module do
        agent_module.handle_tool_result(
          tool_info.tool_name,
          actual_tool_run_result,
          current_agent_state
        )
      else
        # Should not happen
        {:ok, current_agent_state}
      end

    updated_agent_state_post_tool_result_cb =
      case tool_result_status do
        :ok -> agent_state_after_tool_result_cb
        # Keep state on error from callback
        _ -> current_agent_state
      end

    next_request_messages_for_llm =
      format_tool_result_message(
        actual_tool_run_result,
        tool_info.tool_call_id,
        tool_info.tool_name
      )

    process_llm_interactions(
      llm_client,
      model,
      available_tools,
      llm_params,
      message_history,
      next_request_messages_for_llm,
      remaining_iterations,
      agent_module,
      # Pass the updated agent state
      updated_agent_state_post_tool_result_cb
    )
  end

  defp execute_tool(tool_def, tool_args) do
    try do
      apply(tool_def.module, :run, [tool_args])
    rescue
      e -> {:error, {e, __STACKTRACE__}}
    end
  end

  defp format_tool_result_message({:ok, result_content}, tool_call_id, tool_name_str) do
    [format_tool_result_as_message(tool_call_id, tool_name_str, result_content)]
  end

  defp format_tool_result_message({:error, error_reason}, tool_call_id, tool_name_str) do
    [format_tool_error_as_message(tool_call_id, tool_name_str, error_reason)]
  end

  defp format_response(response) when is_list(response) do
    {:assistant,
     Enum.map(response, fn part ->
       {_, response} = format_response(part)
       response
     end)}
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
