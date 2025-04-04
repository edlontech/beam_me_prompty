defmodule BeamMePrompty.Agent.Stage.ToolExecutor do
  @moduledoc """
  Handles tool discovery, execution, and result processing.

  This module centralizes all tool-related operations including:
  - Finding tool definitions from available tools
  - Executing tools safely with error handling
  - Processing tool results and errors
  - Managing tool call flow with agent callbacks
  """
  @moduledoc section: :agent_stage_and_execution

  require Logger

  alias BeamMePrompty.Agent.Stage.AgentCallbacks
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.LLM.Errors, as: LLMErrors
  alias BeamMePrompty.Telemetry

  @doc """
  Handles tool execution when the tool is not found in available tools.
  """
  def handle_tool_not_found(
        tool_info,
        llm_client,
        model,
        available_tools,
        llm_params,
        message_history,
        remaining_iterations,
        agent_module,
        current_agent_state,
        stage_name,
        session_id
      ) do
    Telemetry.tool_execution_start(
      agent_module,
      session_id,
      stage_name,
      tool_info.tool_name,
      tool_info.tool_args
    )

    error_content_for_llm = "Tool not defined: #{tool_info.tool_name}"

    tool_not_found_msg_to_llm = [
      MessageManager.format_tool_error_as_message(
        tool_info.tool_call_id,
        tool_info.tool_name,
        error_content_for_llm
      )
    ]

    tool_execution_outcome_for_agent =
      {:error,
       LLMErrors.ToolError.exception(
         module: __MODULE__,
         cause: error_content_for_llm
       )}

    {tool_result_status, agent_state_after_tool_result_cb} =
      AgentCallbacks.call_tool_result(
        agent_module,
        tool_info.tool_name,
        tool_execution_outcome_for_agent,
        current_agent_state
      )

    updated_agent_state_post_tool_result_cb =
      AgentCallbacks.update_agent_state_from_callback(
        tool_result_status,
        agent_state_after_tool_result_cb,
        current_agent_state
      )

    Telemetry.tool_execution_stop(
      agent_module,
      session_id,
      stage_name,
      tool_info.tool_name,
      :error,
      error_content_for_llm
    )

    {
      :continue_llm_interactions,
      llm_client,
      model,
      available_tools,
      llm_params,
      message_history,
      tool_not_found_msg_to_llm,
      remaining_iterations,
      agent_module,
      updated_agent_state_post_tool_result_cb
    }
  end

  @doc """
  Handles tool execution when the tool is found in available tools.
  """
  def handle_tool_execution(
        tool_def,
        tool_info,
        llm_client,
        model,
        available_tools,
        llm_params,
        message_history,
        remaining_iterations,
        agent_module,
        current_agent_state,
        stage_name,
        session_id
      ) do
    Telemetry.tool_execution_start(
      agent_module,
      session_id,
      stage_name,
      tool_info.tool_name,
      tool_info.tool_args
    )

    actual_tool_run_result =
      execute_tool(tool_def, tool_info.tool_args, %{
        memory_manager: current_agent_state[:memory_manager],
        agent_module: agent_module,
        session_id: session_id,
        stage_name: stage_name
      })

    {tool_result_status, agent_state_after_tool_result_cb} =
      AgentCallbacks.call_tool_result(
        agent_module,
        tool_info.tool_name,
        actual_tool_run_result,
        current_agent_state
      )

    updated_agent_state_post_tool_result_cb =
      AgentCallbacks.update_agent_state_from_callback(
        tool_result_status,
        agent_state_after_tool_result_cb,
        current_agent_state
      )

    next_request_messages_for_llm =
      MessageManager.format_tool_result_message(
        actual_tool_run_result,
        tool_info.tool_call_id,
        tool_info.tool_name
      )

    tool_status = if elem(actual_tool_run_result, 0) == :ok, do: :ok, else: :error

    Telemetry.tool_execution_stop(
      agent_module,
      session_id,
      stage_name,
      tool_info.tool_name,
      tool_status,
      actual_tool_run_result
    )

    {
      :continue_llm_interactions,
      llm_client,
      model,
      available_tools,
      llm_params,
      message_history,
      next_request_messages_for_llm,
      remaining_iterations,
      agent_module,
      updated_agent_state_post_tool_result_cb
    }
  end

  @doc """
  Executes a tool with the given arguments, handling exceptions gracefully.
  """
  def execute_tool(tool_def, tool_args, context \\ %{}) do
    tool_def.module.run(tool_args, context)
  rescue
    e -> {:error, LLMErrors.ToolError.exception(module: tool_def.module, cause: e)}
  end

  @doc """
  Finds a tool definition by name from the list of available tools.
  """
  def find_tool_definition(available_tools, tool_name) do
    Enum.find(available_tools, &(&1.name == tool_name))
  end

  @doc """
  Extracts tool information from a function call response.
  """
  def extract_tool_info(tool_function_call_part) do
    function_call_details = tool_function_call_part.function_call
    tool_name = normalize_tool_name(function_call_details)

    %{
      tool_name: tool_name,
      tool_args: function_call_details.arguments,
      tool_call_id: Map.get(function_call_details, :id)
    }
  end

  @doc """
  Processes a tool call by calling agent callbacks and executing the tool.
  """
  def process_tool_call(
        tool_info,
        available_tools,
        llm_client,
        model,
        llm_params,
        message_history,
        remaining_iterations,
        agent_module,
        current_agent_state,
        stage_name,
        session_id
      ) do
    {tool_call_status, agent_state_after_tool_call_cb} =
      AgentCallbacks.call_tool_call(
        agent_module,
        tool_info.tool_name,
        tool_info.tool_args,
        current_agent_state
      )

    updated_agent_state_post_handle_tool_call =
      AgentCallbacks.update_agent_state_from_callback(
        tool_call_status,
        agent_state_after_tool_call_cb,
        current_agent_state
      )

    tool_definition = find_tool_definition(available_tools, tool_info.tool_name)

    if tool_definition do
      handle_tool_execution(
        tool_definition,
        tool_info,
        llm_client,
        model,
        available_tools,
        llm_params,
        message_history,
        remaining_iterations - 1,
        agent_module,
        updated_agent_state_post_handle_tool_call,
        stage_name,
        session_id
      )
    else
      handle_tool_not_found(
        tool_info,
        llm_client,
        model,
        available_tools,
        llm_params,
        message_history,
        remaining_iterations - 1,
        agent_module,
        updated_agent_state_post_handle_tool_call,
        stage_name,
        session_id
      )
    end
  end

  defp normalize_tool_name(tool) do
    String.to_existing_atom(tool.name)
  rescue
    _ ->
      tool.name
  end
end
