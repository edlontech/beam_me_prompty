defmodule BeamMePrompty.Agent.Internals do
  @moduledoc """
  Internal implementation of the BeamMePrompty Agent execution engine.

  This module is responsible for executing a directed acyclic graph (DAG) of operations
  in the correct order, respecting dependencies between nodes. It uses a state machine 
  approach to manage the execution flow:

  1. `waiting_for_plan`: Determines which nodes are ready to execute based on dependencies
  2. `execute_nodes`: Dispatches execution requests to stage workers
  3. `awaiting_stage_results`: Collects results from completed stage executions
  4. `completed`: Final state when all nodes have been executed

  The module maintains a supervision tree for stage workers and handles error conditions
  during the execution process. Results from each node are collected and can be accessed
  after completion.

  This is an internal module and should not be used directly unless you understand the 
  implications. Instead, use the public API provided by the BeamMePrompty.Agent module.
  """
  @moduledoc section: :agent_internals

  use GenStateMachine, callback_mode: :state_functions

  require Logger

  @type agent_type :: :stateful | :stateless

  # Simplified struct using the new component modules
  defstruct [
    # Core identifiers
    :agent_type,
    :session_id,
    :agent_version,
    :agent_spec,

    # DAG and execution context
    :dag,
    :global_input,
    :initial_state,
    :current_state,
    :nodes_to_execute,
    :opts,

    # Infrastructure
    :stage_workers,
    :memory_manager,

    # Management components
    :result_manager,
    :batch_manager,
    :progress_tracker
  ]

  alias BeamMePrompty.Agent.MemoryManager
  alias BeamMePrompty.Agent.StagesSupervisor
  alias BeamMePrompty.Telemetry

  alias BeamMePrompty.Agent.Internals.BatchManager
  alias BeamMePrompty.Agent.Internals.ErrorHandler
  alias BeamMePrompty.Agent.Internals.ProgressTracker
  alias BeamMePrompty.Agent.Internals.ResultManager
  alias BeamMePrompty.Agent.Internals.StateManager

  alias BeamMePrompty.DAG

  @impl true
  def init({session_id, dag, input, initial_agent_state, opts, agent_spec}) do
    Telemetry.agent_execution_start(
      agent_spec.callback_module,
      session_id,
      input,
      initial_agent_state,
      opts
    )

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(agent_spec)}](sid: #{inspect(session_id)}) initializing..."
    )

    {_init_status, current_agent_state} =
      StateManager.execute_init_callback(agent_spec, dag, initial_agent_state)

    with {:ok, stages_sup_pid} <- StagesSupervisor.start_link(:ok),
         {:ok, memory_manager_pid} <- start_memory_manager(agent_spec.memory_sources) do
      stage_workers =
        start_stage_workers(stages_sup_pid, session_id, agent_spec, dag.nodes)

      agent_config = agent_spec.agent_config

      data = %__MODULE__{
        agent_type: agent_config.agent_state,
        agent_version: agent_config.version,
        session_id: session_id,
        dag: dag,
        opts: opts,
        agent_spec: agent_spec,
        global_input: input,
        initial_state: initial_agent_state,
        current_state: current_agent_state,
        stage_workers: stage_workers,
        memory_manager: memory_manager_pid,
        result_manager: ResultManager.new(),
        batch_manager: BatchManager.new(),
        progress_tracker: ProgressTracker.new(map_size(dag.nodes)),
        nodes_to_execute: []
      }

      actions = [{:next_event, :internal, :plan}]
      {:ok, :waiting_for_plan, data, actions}
    else
      {:error, reason} ->
        ErrorHandler.handle_supervisor_error(reason)
    end
  end

  def waiting_for_plan(:internal, :plan, data) do
    completed_count = ResultManager.completed_count(data.result_manager)
    total_count = map_size(data.dag.nodes)
    Telemetry.dag_planning_start(data.agent_spec, data.session_id, completed_count, total_count)

    current_results = ResultManager.get_all_results(data.result_manager)
    ready_nodes_from_dag = DAG.find_ready_nodes(data.dag, current_results)

    Logger.debug(
      "[BeamMePrompty] Agent [#{data.agent_spec.agent_config.name}](v: #{data.agent_spec.agent_config.version})(sid: #{inspect(data.session_id)}) #{inspect(ready_nodes_from_dag)}, Completed: #{completed_count}/#{total_count}"
    )

    {plan_status, planned_nodes, updated_agent_state} =
      StateManager.execute_plan_callback(
        data.agent_spec,
        ready_nodes_from_dag,
        data.current_state
      )

    Logger.debug(
      "[BeamMePrompty] Agent [#{data.agent_spec.agent_config.name}](v: #{data.agent_spec.agent_config.version})(sid: #{inspect(data.session_id)}) Plan callback result - Status: #{inspect(plan_status)}, Planned nodes: #{inspect(planned_nodes)}"
    )

    effective_ready_nodes =
      case plan_status do
        :ok -> planned_nodes
        _ -> ready_nodes_from_dag
      end

    Telemetry.dag_planning_stop(
      data.agent_spec,
      data.session_id,
      Enum.count(ready_nodes_from_dag),
      Enum.count(planned_nodes),
      Enum.count(effective_ready_nodes),
      plan_status
    )

    updated_data = %{data | current_state: updated_agent_state}

    cond do
      execution_complete?(updated_data) ->
        handle_execution_completion(updated_data)

      Enum.empty?(effective_ready_nodes) ->
        ErrorHandler.handle_planning_error(updated_data)

      true ->
        prepare_node_execution(updated_data, effective_ready_nodes)
    end
  end

  def waiting_for_plan({:call, from}, :get_results, data) do
    {:keep_state, data, [{:reply, from, {:ok, :planning_execution}}]}
  end

  # Helper functions for waiting_for_plan state

  defp start_stage_workers(supervisor_pid, session_id, agent_spec, dag_nodes) do
    Enum.into(dag_nodes, %{}, fn {node_name, _node_definition} ->
      case StagesSupervisor.start_stage_worker(
             supervisor_pid,
             session_id,
             agent_spec.callback_module,
             node_name
           ) do
        {:ok, stage_pid} ->
          Logger.debug(
            "[BeamMePrompty] Agent [#{inspect(agent_spec)}](sid: #{inspect(session_id)}): Started stage worker for #{node_name} (PID: #{inspect(stage_pid)})"
          )

          {node_name, stage_pid}

        {:error, reason} ->
          ErrorHandler.handle_stage_worker_error(node_name, reason)
      end
    end)
  end

  defp execution_complete?(data) do
    completed_count = ResultManager.completed_count(data.result_manager)
    total_count = map_size(data.dag.nodes)
    completed_count == total_count
  end

  defp handle_execution_completion(data) do
    current_results = ResultManager.get_all_results(data.result_manager)

    {_status, final_agent_state} =
      StateManager.execute_complete_callback(
        data.agent_spec,
        current_results,
        data.current_state
      )

    updated_data = %{data | current_state: final_agent_state}

    if data.agent_type == :stateful do
      {:next_state, :idle, updated_data}
    else
      {:next_state, :completed, updated_data}
    end
  end

  defp prepare_node_execution(data, effective_ready_nodes) do
    current_results = ResultManager.get_all_results(data.result_manager)

    nodes_to_execute_definitions =
      Enum.map(effective_ready_nodes, fn node_name ->
        node_def = Map.get(data.dag.nodes, node_name)

        node_context =
          Map.merge(data.initial_state, %{
            dependency_results: current_results,
            global_input: data.global_input,
            agent_spec: data.agent_spec,
            current_agent_state: data.current_state,
            memory_manager: data.memory_manager
          })

        {node_name, node_def, node_context}
      end)

    updated_data = %{data | nodes_to_execute: nodes_to_execute_definitions}
    {:next_state, :execute_nodes, updated_data, [{:next_event, :internal, :execute}]}
  end

  # Helper functions for awaiting_stage_results state

  defp handle_stage_success_with_agent_state(
         data,
         node_name,
         stage_result,
         agent_state_from_stage
       ) do
    updated_data = %{data | current_state: agent_state_from_stage}

    {batch_status, updated_batch} =
      BatchManager.handle_stage_completion(
        updated_data.batch_manager,
        node_name,
        stage_result
      )

    # Get node details for stage finish callback
    case BatchManager.get_node_details(updated_data.batch_manager, node_name) do
      {:ok, {stage_node_definition, _node_ctx}} ->
        {_status, agent_state_after_stage_finish} =
          StateManager.execute_stage_finish_callback(
            updated_data.agent_spec,
            stage_node_definition,
            stage_result,
            updated_data.current_state
          )

        data_after_stage_finish = %{
          updated_data
          | current_state: agent_state_after_stage_finish,
            batch_manager: updated_batch
        }

        handle_progress_and_completion(data_after_stage_finish, batch_status)

      {:error, _reason} ->
        Logger.error("[Internals] Node details not found for #{node_name}")
        {:keep_state, updated_data}
    end
  end

  defp handle_stage_success_without_agent_state(data, node_name, stage_result) do
    {batch_status, updated_batch} =
      BatchManager.handle_stage_completion(
        data.batch_manager,
        node_name,
        stage_result
      )

    updated_data = %{data | batch_manager: updated_batch}
    handle_completion_status(updated_data, batch_status)
  end

  defp handle_progress_and_completion(data, batch_status) do
    current_results = ResultManager.get_all_results(data.result_manager)
    batch_results = BatchManager.get_batch_results(data.batch_manager)
    total_completed = map_size(current_results) + map_size(batch_results)

    updated_progress_tracker =
      ProgressTracker.update_progress(data.progress_tracker, total_completed)

    progress_info = ProgressTracker.get_progress_info(updated_progress_tracker)

    {_status, agent_state_after_progress} =
      StateManager.execute_progress_callback(data.agent_spec, progress_info, data.current_state)

    data_after_progress = %{
      data
      | current_state: agent_state_after_progress,
        progress_tracker: updated_progress_tracker
    }

    handle_completion_status(data_after_progress, batch_status)
  end

  defp handle_completion_status(data, :batch_complete) do
    batch_results = BatchManager.get_batch_results(data.batch_manager)

    updated_result_manager =
      ResultManager.commit_batch_results(data.result_manager, batch_results)

    all_dag_node_names = Map.keys(data.dag.nodes)
    current_results = ResultManager.get_all_results(updated_result_manager)
    completed_dag_node_names = Map.keys(current_results)
    pending_dag_nodes_list = all_dag_node_names -- completed_dag_node_names

    {_status, agent_state_after_batch_complete} =
      StateManager.execute_batch_complete_callback(
        data.agent_spec,
        batch_results,
        pending_dag_nodes_list,
        data.current_state
      )

    final_data = %{
      data
      | result_manager: updated_result_manager,
        batch_manager: BatchManager.new(),
        current_state: agent_state_after_batch_complete
    }

    {:next_state, :waiting_for_plan, final_data, [{:next_event, :internal, :plan}]}
  end

  defp handle_completion_status(data, :batch_pending) do
    {:keep_state, data}
  end

  def execute_nodes(:internal, :execute, data) do
    if Enum.empty?(data.nodes_to_execute) do
      {:next_state, :waiting_for_plan, data, [{:next_event, :internal, :plan}]}
    else
      {_batch_start_status, updated_agent_state} =
        StateManager.execute_batch_start_callback(
          data.agent_spec,
          data.nodes_to_execute,
          data.current_state
        )

      data_with_updated_state = %{data | current_state: updated_agent_state}

      prepared_batch = BatchManager.prepare_batch(data.nodes_to_execute, updated_agent_state)

      BatchManager.dispatch_nodes(prepared_batch, data_with_updated_state.stage_workers, self())

      final_data = %{
        data_with_updated_state
        | batch_manager: prepared_batch,
          nodes_to_execute: []
      }

      {:next_state, :awaiting_stage_results, final_data}
    end
  end

  def awaiting_stage_results(
        :info,
        {:stage_response, node_name, {:ok, stage_result}, agent_state_from_stage},
        data
      ) do
    handle_stage_success_with_agent_state(data, node_name, stage_result, agent_state_from_stage)
  end

  def awaiting_stage_results(
        :info,
        {:stage_response, node_name, {:error, reason_of_error}, agent_state_from_stage},
        data
      ) do
    updated_data = %{data | current_state: agent_state_from_stage}
    ErrorHandler.handle_stage_error(node_name, reason_of_error, updated_data)
  end

  def awaiting_stage_results({:call, from}, :get_results, data) do
    {:keep_state, data, [{:reply, from, {:ok, :waiting_for_stage_results}}]}
  end

  def awaiting_stage_results(:info, {:stage_response, node_name, {:ok, stage_result}}, data) do
    handle_stage_success_without_agent_state(data, node_name, stage_result)
  end

  def awaiting_stage_results(:info, {:stage_response, node_name, {:error, reason_of_error}}, data) do
    ErrorHandler.handle_stage_error(node_name, reason_of_error, data)
  end

  def awaiting_stage_results({:call, from}, {:message, _message}, data) do
    {:keep_state, data, [{:reply, from, {:error, :still_processing_last_message}}]}
  end

  def awaiting_stage_results(event_type, event_content, data) do
    ErrorHandler.handle_unexpected_event(:awaiting_stage_results, event_type, event_content, data)
  end

  def idle({:call, from}, :get_results, data) do
    current_results = ResultManager.get_all_results(data.result_manager)
    {:keep_state, data, [{:reply, from, {:ok, :idle, current_results}}]}
  end

  def idle({:call, from}, {:message, message}, data) do
    entry_point_stage = find_entry_point_stage(data.dag.nodes)

    Logger.debug(
      "[BeamMePrompty] Agent [#{data.agent_spec.agent_config.name}](v: #{data.agent_spec.agent_config.version}) (sid: #{inspect(data.session_id)}) received message: #{inspect(message)}"
    )

    if entry_point_stage do
      stage_pid = Map.get(data.stage_workers, entry_point_stage)
      GenStateMachine.cast(stage_pid, {:update_messages, message, false})
    end

    archived_result_manager = ResultManager.archive_current_results(data.result_manager)
    reset_progress_tracker = ProgressTracker.reset(data.progress_tracker)
    reset_batch_manager = BatchManager.new()

    data_for_replan = %{
      data
      | result_manager: archived_result_manager,
        progress_tracker: reset_progress_tracker,
        batch_manager: reset_batch_manager,
        nodes_to_execute: []
    }

    {:next_state, :waiting_for_plan, data_for_replan,
     [{:reply, from, :ok}, {:next_event, :internal, :plan}]}
  end

  def idle(event_type, event_content, data) do
    ErrorHandler.handle_unexpected_event(:idle, event_type, event_content, data)
    {:keep_state, data}
  end

  def completed({:call, from}, :get_results, data) do
    current_results = ResultManager.get_all_results(data.result_manager)
    {:keep_state, data, [{:reply, from, {:ok, :completed, current_results}}]}
  end

  def completed({:call, from}, {:get_node_result, node_name}, data) do
    case ResultManager.get_result(data.result_manager, node_name) do
      {:ok, result} ->
        {:keep_state, data, [{:reply, from, {:ok, :completed, result}}]}

      :error ->
        {:keep_state, data,
         [
           {:reply, from,
            {:error, BeamMePrompty.Errors.Framework.exception(cause: :node_not_found)}}
         ]}
    end
  end

  def completed(event_type, event_content, data) do
    ErrorHandler.handle_unexpected_event(:completed, event_type, event_content, data)
    {:keep_state, data}
  end

  @impl true
  def terminate(reason, _state_name, data) do
    Telemetry.agent_execution_stop(
      data.agent_spec.callback_module,
      data.session_id,
      reason,
      data.result_manager
    )

    :ok
  end

  defp find_entry_point_stage(nodes) do
    entry_point =
      Enum.find(nodes, fn {_name, node_def} ->
        Map.get(node_def, :entry_point, false)
      end)

    case entry_point do
      {name, _def} ->
        name

      nil ->
        nodes |> Map.keys() |> List.first()
    end
  end

  defp start_memory_manager(memory_sources) do
    memory_sources =
      Enum.map(memory_sources, fn source ->
        {source.name, {source.module, source.opts}}
      end)

    MemoryManager.start_link(memory_sources)
  end
end
