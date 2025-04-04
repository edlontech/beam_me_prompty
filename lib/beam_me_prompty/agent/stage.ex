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
  @moduledoc section: :agent_stage_and_execution

  use GenStateMachine, callback_mode: :state_functions

  require Logger

  alias BeamMePrompty.Agent.Stage.AgentCallbacks
  alias BeamMePrompty.Agent.Stage.LLMProcessor
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.Errors
  alias BeamMePrompty.Telemetry

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
    Telemetry.stage_execution_start(
      data.agent_module,
      data.session_id,
      data.stage_name,
      node_name
    )

    agent_module_from_ctx = node_ctx[:agent_module]
    agent_state_from_ctx = node_ctx[:current_agent_state]

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(data.agent_module)}](sid: #{inspect(data.session_id)}) running node [#{inspect(node_name)}]"
    )

    # Ensure memory_manager is in the agent state
    agent_state_with_memory =
      Map.put(
        agent_state_from_ctx || %{},
        :memory_manager,
        node_ctx[:memory_manager]
      )

    data_with_agent_context = %{
      data
      | agent_module: agent_module_from_ctx,
        current_agent_state: agent_state_with_memory
    }

    AgentCallbacks.call_stage_start(
      agent_module_from_ctx,
      node_def,
      data_with_agent_context.current_agent_state
    )

    execution_params = {node_name, node_def, node_ctx, caller_pid}

    {:next_state, :executing_llm, data_with_agent_context,
     {:next_event, :internal, {:execute, execution_params}}}
  end

  def idle(:cast, {:update_messages, new_message, reset_history}, data) do
    updated_messages =
      MessageManager.update_message_history(data.messages, new_message, reset_history)

    updated_data = %{data | messages: updated_messages}
    {:keep_state, updated_data}
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

    Telemetry.stage_execution_stop(
      final_stage_data.agent_module,
      final_stage_data.session_id,
      final_stage_data.stage_name,
      node_name,
      stage_execution_result,
      result_payload
    )

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

  defp do_execute_stage(stage_node_def, exec_context, stage_data) do
    Logger.debug("""
    [BeamMePrompty] Agent [#{inspect(stage_data.agent_module)}](sid: #{inspect(stage_data.session_id)}) Stage [#{inspect(stage_data.stage_name)}] executing.
    """)

    global_input = exec_context[:global_input] || %{}
    dependency_results = exec_context[:dependency_results] || %{}
    inputs_for_llm = Map.merge(global_input, dependency_results)

    case LLMProcessor.maybe_call_llm(
           stage_node_def.llm,
           inputs_for_llm,
           stage_data.messages,
           stage_data.agent_module,
           stage_data.current_agent_state,
           stage_data.session_id,
           stage_data.stage_name
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
end
