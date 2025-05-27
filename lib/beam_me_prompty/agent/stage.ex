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

  require Logger

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.TextPart
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.ToolError
  alias BeamMePrompty.LLM.MessageParser

  defstruct [
    :stage_name,
    :session_id,
    :messages,
    :tool_responses,
    :agent_module,
    :current_agent_state
  ]

  @doc false
  def start_link(stage) do
    GenStateMachine.start_link(__MODULE__, stage, [])
  end

  @impl true
  def init({stage_name, session_id, agent_module}) do
    actual_stage_name =
      case stage_name do
        {s_name} when is_atom(s_name) or is_binary(s_name) -> s_name
        s_name -> s_name
      end

    initial_data = %__MODULE__{
      stage_name: actual_stage_name,
      messages: [],
      tool_responses: [],
      session_id: session_id,
      agent_module: agent_module,
      current_agent_state: %{}
    }

    {:ok, :idle, initial_data}
  end

  def idle(:cast, {:execute, node_name, node_def, node_ctx, caller_pid}, data) do
    agent_module_from_ctx = node_ctx[:agent_module]
    agent_state_from_ctx = node_ctx[:current_agent_state]

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(data.agent_module)}](sid: #{inspect(data.session_id)}) running node [#{inspect(node_name)}]"
    )

    data_with_agent_context = %{
      data
      | agent_module: agent_module_from_ctx,
        current_agent_state: agent_state_from_ctx
    }

    if agent_module_from_ctx do
      agent_module_from_ctx.handle_stage_start(
        node_def,
        data_with_agent_context.current_agent_state
      )
    end

    execution_params = {node_name, node_def, node_ctx, caller_pid}

    {:next_state, :executing_llm, data_with_agent_context,
     {:next_event, :internal, {:execute, execution_params}}}
  end

  def idle(:cast, {:update_messages, new_message, reset_history}, data) do
    updated_messages =
      if reset_history do
        [new_message]
      else
        data.messages ++ [new_message]
      end

    updated_data = %{data | messages: updated_messages}
    {:keep_state, updated_data}
  end

  def idle(_event_type, _event_content, data) do
    {:keep_state, data}
  end

  # --- :executing_llm State ---

  def executing_llm(
        :internal,
        {:execute, {node_name, node_def, node_ctx, caller_pid}},
        data
      ) do
    {stage_execution_result, result_payload, final_stage_data} =
      do_execute_stage(node_def, node_ctx, data)

    response_payload =
      case stage_execution_result do
        :ok -> {:ok, result_payload}
        :error -> {:error, result_payload}
      end

    send(
      caller_pid,
      {:stage_response, node_name, response_payload, final_stage_data.current_agent_state}
    )

    {:next_state, :idle, final_stage_data}
  end

  def executing_llm(_event_type, _event_content, _data) do
    {:keep_state_and_data, :postpone}
  end

  @impl true
  def terminate(_reason, _state, _data) do
    :ok
  end

  # --- Private Helper Functions for Stage Execution ---

  defp do_execute_stage(stage_node_def, exec_context, stage_data) do
    Logger.debug("""
    [BeamMePrompty] Agent [#{inspect(stage_data.agent_module)}](sid: #{inspect(stage_data.session_id)}) Stage [#{inspect(stage_data.stage_name)}] executing.
    """)

    global_input = exec_context[:global_input] || %{}
    dependency_results = exec_context[:dependency_results] || %{}
    inputs_for_llm = Map.merge(global_input, dependency_results)

    case maybe_call_llm(
           stage_node_def.llm,
           inputs_for_llm,
           stage_data.messages,
           stage_data.agent_module,
           stage_data.current_agent_state
         ) do
      {:ok, llm_result, updated_messages_history, final_agent_state_after_llm} ->
        Logger.debug("""
        [BeamMePrompty] Agent [#{inspect(stage_data.agent_module)}](sid: #{inspect(stage_data.session_id)}) Stage [#{inspect(stage_data.stage_name)}] finished.
        """)

        updated_stage_data = %{
          stage_data
          | messages: updated_messages_history,
            current_agent_state: final_agent_state_after_llm
        }

        {:ok, llm_result, updated_stage_data}

      {:error, error_reason, updated_messages_history, final_agent_state_after_llm_error} ->
        updated_stage_data_on_error = %{
          stage_data
          | messages: updated_messages_history,
            current_agent_state: final_agent_state_after_llm_error
        }

        {:error, Errors.to_class(error_reason), updated_stage_data_on_error}
    end
  end

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

  defp maybe_call_llm(
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

      messages =
        if Enum.empty?(initial_messages_history) do
          MessageParser.parse(config.messages, input)
        else
          initial_messages_history
        end

      process_llm_interactions(
        config.llm_client,
        config.model,
        tools,
        llm_params,
        initial_messages_history,
        messages,
        5,
        agent_module,
        current_agent_state
      )
    else
      {:ok, %{}, initial_messages_history, current_agent_state}
    end
  end

  defp maybe_call_llm([], _input, current_messages, _agent_module, current_agent_state) do
    {:ok, %{}, current_messages, current_agent_state}
  end

  defp maybe_call_llm(
         _unhandled_config,
         _input,
         current_messages,
         _agent_module,
         current_agent_state
       ) do
    {:ok, %{}, current_messages, current_agent_state}
  end

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
         agent_module,
         current_agent_state
       ) do
    messages_to_send_to_llm = accumulated_messages ++ current_request_messages

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
          agent_module,
          current_agent_state
        )

      {:error, reason} ->
        {:error, reason, accumulated_messages, current_agent_state}
    end
  end

  defp handle_llm_response(
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
        function_call_details = tool_function_call_part.function_call
        tool_name = tool_name(function_call_details)

        parsed_tool_info = %{
          tool_name: tool_name,
          tool_args: function_call_details.arguments,
          tool_call_id: Map.get(function_call_details, :id)
        }

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

  defp handle_tool_execution(
         nil,
         tool_info,
         llm_client,
         model,
         available_tools,
         llm_params,
         message_history,
         remaining_iterations,
         agent_module,
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

    tool_execution_outcome_for_agent = {:error, error_content_for_llm}

    {tool_result_status, agent_state_after_tool_result_cb} =
      if agent_module do
        agent_module.handle_tool_result(
          tool_info.tool_name,
          tool_execution_outcome_for_agent,
          current_agent_state
        )
      else
        {:ok, current_agent_state}
      end

    updated_agent_state_post_tool_result_cb =
      case tool_result_status do
        :ok -> agent_state_after_tool_result_cb
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
      updated_agent_state_post_tool_result_cb
    )
  end

  defp handle_tool_execution(
         tool_def,
         tool_info,
         llm_client,
         model,
         available_tools,
         llm_params,
         message_history,
         remaining_iterations,
         agent_module,
         current_agent_state
       ) do
    actual_tool_run_result = execute_tool(tool_def, tool_info.tool_args)

    {tool_result_status, agent_state_after_tool_result_cb} =
      if agent_module do
        agent_module.handle_tool_result(
          tool_info.tool_name,
          actual_tool_run_result,
          current_agent_state
        )
      else
        {:ok, current_agent_state}
      end

    updated_agent_state_post_tool_result_cb =
      case tool_result_status do
        :ok -> agent_state_after_tool_result_cb
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
      updated_agent_state_post_tool_result_cb
    )
  end

  defp execute_tool(tool_def, tool_args) do
    tool_def.module.run(tool_args)
  rescue
    e -> {:error, {e, __STACKTRACE__}}
  end

  defp tool_name(tool) do
    String.to_existing_atom(tool.name)
  rescue
    _ ->
      tool.name
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

  defp format_tool_error_as_message(tool_call_id, fun_name, error)
       when is_struct(error, ToolError) do
    format_tool_error_as_message(tool_call_id, fun_name, error.cause)
  end

  defp format_tool_error_as_message(tool_call_id, fun_name, error) when is_binary(error) do
    content =
      "Error executing tool #{fun_name} (call_id: #{tool_call_id || "N/A"}): #{error}"

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
