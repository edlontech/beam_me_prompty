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
  use GenStateMachine, callback_mode: :state_functions

  require Logger

  @type agent_type :: :stateful | :stateless

  defstruct [
    :agent_type,
    :session_id,
    :dag,
    :agent_module,
    :global_input,
    :nodes_to_execute,
    :initial_state,
    :current_state,
    :opts,
    :stages_supervisor_pid,
    :stage_workers,
    :previous_results,
    :results,
    :started_at,
    :pending_nodes,
    :current_batch_details,
    :temp_batch_results
  ]

  require Logger

  alias BeamMePrompty.Agent.StagesSupervisor
  alias BeamMePrompty.DAG
  alias BeamMePrompty.Errors

  @impl true
  def init({session_id, dag, input, initial_agent_state, opts, agent_module_impl}) do
    agent_type = Keyword.get(opts, :agent_state, :stateless)

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(agent_module_impl)}](sid: #{inspect(session_id)}) initializing..."
    )

    {init_status, new_agent_state_after_init} =
      agent_module_impl.handle_init(dag, initial_agent_state)

    current_agent_state =
      case init_status do
        :ok -> new_agent_state_after_init
        {:ok, overidden_state} -> overidden_state
        _ -> initial_agent_state
      end

    case StagesSupervisor.start_link(:ok) do
      {:ok, sup_pid} ->
        stage_workers =
          Enum.into(dag.nodes, %{}, fn {node_name, _node_definition} ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            case StagesSupervisor.start_stage_worker(
                   sup_pid,
                   session_id,
                   agent_module_impl,
                   node_name
                 ) do
              {:ok, stage_pid} ->
                Logger.debug(
                  "[BeamMePrompty] Agent [#{inspect(agent_module_impl)}](sid: #{inspect(session_id)}): Started stage worker for #{node_name} (PID: #{inspect(stage_pid)})"
                )

                {node_name, stage_pid}

              {:error, reason} ->
                raise "Failed to start stage worker for #{node_name}: #{inspect(reason)}"
            end
          end)

        data = %__MODULE__{
          agent_type: agent_type,
          session_id: session_id,
          dag: dag,
          opts: opts,
          agent_module: agent_module_impl,
          global_input: input,
          initial_state: initial_agent_state,
          current_state: current_agent_state,
          stages_supervisor_pid: sup_pid,
          stage_workers: stage_workers,
          previous_results: [],
          results: %{},
          started_at: System.monotonic_time(:millisecond),
          pending_nodes: [],
          current_batch_details: %{},
          temp_batch_results: %{}
        }

        actions = [{:next_event, :internal, :plan}]
        {:ok, :waiting_for_plan, data, actions}

      {:error, reason} ->
        {:stop, {:failed_to_start_stages_supervisor, reason}}
    end
  end

  def waiting_for_plan(:internal, :plan, data) do
    ready_nodes_from_dag = DAG.find_ready_nodes(data.dag, data.results)

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(data.agent_module)}](sid: #{inspect(data.session_id)}) #{inspect(ready_nodes_from_dag)}, Completed: #{map_size(data.results)}/#{map_size(data.dag.nodes)}"
    )

    {plan_status, planned_nodes, new_agent_state_after_plan} =
      data.agent_module.handle_plan(ready_nodes_from_dag, data.current_state)

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(data.agent_module)}](sid: #{inspect(data.session_id)}) Plan callback result - Status: #{inspect(plan_status)}, Planned nodes: #{inspect(planned_nodes)}"
    )

    current_agent_state_after_plan_callback =
      case plan_status do
        :ok -> new_agent_state_after_plan
        _ -> data.current_state
      end

    effective_ready_nodes =
      case plan_status do
        :ok -> planned_nodes
        _ -> ready_nodes_from_dag
      end

    data_after_plan_callback = %{data | current_state: current_agent_state_after_plan_callback}

    cond do
      map_size(data_after_plan_callback.results) == map_size(data_after_plan_callback.dag.nodes) ->
        data_after_plan_callback.agent_module.handle_complete(
          data_after_plan_callback.results,
          data_after_plan_callback.current_state
        )

        if data_after_plan_callback.agent_type == :stateful do
          {:next_state, :idle, data_after_plan_callback}
        else
          {:next_state, :completed, data_after_plan_callback}
        end

      Enum.empty?(effective_ready_nodes) ->
        {:error,
         Errors.ExecutionError.exception(
           step: :waiting_for_plan,
           cause: "No nodes are ready to execute after agent's handle_plan"
         )}
        |> handle_error(data_after_plan_callback)

      true ->
        nodes_to_execute_definitions =
          Enum.map(effective_ready_nodes, fn node_name ->
            node_def = Map.get(data_after_plan_callback.dag.nodes, node_name)

            node_context =
              Map.merge(data_after_plan_callback.initial_state, %{
                dependency_results: data_after_plan_callback.results,
                global_input: data_after_plan_callback.global_input,
                agent_module: data_after_plan_callback.agent_module,
                current_agent_state: data_after_plan_callback.current_state
              })

            {node_name, node_def, node_context}
          end)

        next_data_state = %{
          data_after_plan_callback
          | nodes_to_execute: nodes_to_execute_definitions
        }

        {:next_state, :execute_nodes, next_data_state, [{:next_event, :internal, :execute}]}
    end
  end

  def waiting_for_plan({:call, from}, :get_results, data) do
    {:keep_state, data, [{:reply, from, {:ok, :planning_execution}}]}
  end

  def execute_nodes(:internal, :execute, data) do
    if Enum.empty?(data.nodes_to_execute) do
      {:next_state, :waiting_for_plan, data, [{:next_event, :internal, :plan}]}
    else
      {batch_start_status, new_agent_state_after_batch_start} =
        data.agent_module.handle_batch_start(data.nodes_to_execute, data.current_state)

      current_agent_state_after_batch_start_cb =
        case batch_start_status do
          :ok -> new_agent_state_after_batch_start
          _ -> data.current_state
        end

      data_after_batch_start_cb = %{
        data
        | current_state: current_agent_state_after_batch_start_cb
      }

      nodes_for_execution_with_updated_ctx =
        Enum.map(data_after_batch_start_cb.nodes_to_execute, fn {name, nd_def, nd_ctx} ->
          updated_nd_ctx =
            Map.put(nd_ctx, :current_agent_state, data_after_batch_start_cb.current_state)

          {name, nd_def, updated_nd_ctx}
        end)

      current_batch_details_map =
        Enum.into(nodes_for_execution_with_updated_ctx, %{}, fn {name, nd_def, updated_nd_ctx} ->
          {name, {nd_def, updated_nd_ctx}}
        end)

      Enum.each(nodes_for_execution_with_updated_ctx, fn {node_name, node_def, updated_node_ctx} ->
        stage_pid = Map.get(data_after_batch_start_cb.stage_workers, node_name)
        GenStateMachine.cast(stage_pid, {:execute, node_name, node_def, updated_node_ctx, self()})
      end)

      pending_node_names =
        Enum.map(nodes_for_execution_with_updated_ctx, fn {name, _, _} -> name end)

      final_data_for_state_transition = %{
        data_after_batch_start_cb
        | # Clear as they are now dispatched
          nodes_to_execute: [],
          pending_nodes: pending_node_names,
          current_batch_details: current_batch_details_map,
          temp_batch_results: %{}
      }

      {:next_state, :awaiting_stage_results, final_data_for_state_transition}
    end
  end

  def awaiting_stage_results(
        :info,
        {:stage_response, node_name, {:ok, stage_result}, agent_state_from_stage},
        data
      ) do
    data_with_stage_agent_state = %{data | current_state: agent_state_from_stage}

    {stage_node_definition, _node_ctx} =
      Map.get(data_with_stage_agent_state.current_batch_details, node_name)

    data_with_stage_agent_state.agent_module.handle_stage_finish(
      stage_node_definition,
      stage_result,
      data_with_stage_agent_state.current_state
    )

    updated_temp_batch_results =
      Map.put(data_with_stage_agent_state.temp_batch_results, node_name, stage_result)

    updated_pending_nodes_in_batch =
      List.delete(data_with_stage_agent_state.pending_nodes, node_name)

    total_dag_nodes_count = map_size(data_with_stage_agent_state.dag.nodes)

    dag_results_after_current_stage =
      Map.put(data_with_stage_agent_state.results, node_name, stage_result)

    current_completed_dag_nodes_count = map_size(dag_results_after_current_stage)

    progress_info = %{
      completed: current_completed_dag_nodes_count,
      total: total_dag_nodes_count,
      elapsed_ms: System.monotonic_time(:millisecond) - data_with_stage_agent_state.started_at
    }

    {progress_status, new_agent_state_after_progress_cb} =
      data_with_stage_agent_state.agent_module.handle_progress(
        progress_info,
        data_with_stage_agent_state.current_state
      )

    current_agent_state_after_progress =
      case progress_status do
        :ok -> new_agent_state_after_progress_cb
        _ -> data_with_stage_agent_state.current_state
      end

    data_after_progress_cb = %{
      data_with_stage_agent_state
      | temp_batch_results: updated_temp_batch_results,
        pending_nodes: updated_pending_nodes_in_batch,
        current_state: current_agent_state_after_progress
    }

    # Current Batch Complete
    # More nodes still pending in the current batch
    if Enum.empty?(updated_pending_nodes_in_batch) do
      final_dag_results =
        Map.merge(data_after_progress_cb.results, data_after_progress_cb.temp_batch_results)

      all_dag_node_names = Map.keys(data_after_progress_cb.dag.nodes)
      completed_dag_node_names = Map.keys(final_dag_results)
      pending_dag_nodes_list = all_dag_node_names -- completed_dag_node_names

      {batch_complete_status, new_agent_state_after_batch_complete_cb} =
        data_after_progress_cb.agent_module.handle_batch_complete(
          data_after_progress_cb.temp_batch_results,
          pending_dag_nodes_list,
          data_after_progress_cb.current_state
        )

      current_agent_state_after_batch_complete =
        case batch_complete_status do
          :ok -> new_agent_state_after_batch_complete_cb
          _ -> data_after_progress_cb.current_state
        end

      data_for_next_plan = %{
        data_after_progress_cb
        | # Commit batch results to main DAG results
          results: final_dag_results,
          temp_batch_results: %{},
          current_batch_details: %{},
          current_state: current_agent_state_after_batch_complete
      }

      {:next_state, :waiting_for_plan, data_for_next_plan, [{:next_event, :internal, :plan}]}
    else
      {:keep_state, data_after_progress_cb}
    end
  end

  def awaiting_stage_results(
        :info,
        {:stage_response, node_name, {:error, reason_of_error}, agent_state_from_stage},
        data
      ) do
    data_with_stage_agent_state = %{data | current_state: agent_state_from_stage}

    stage_execution_error =
      Errors.ExecutionError.exception(
        stage: node_name,
        cause: reason_of_error
      )

    data_for_error_handling_cb = %{
      data_with_stage_agent_state
      | # Clear partial batch results as this batch errored
        temp_batch_results: %{},
        pending_nodes: [],
        current_batch_details: %{}
    }

    handle_error({:error, stage_execution_error}, data_for_error_handling_cb)
  end

  def awaiting_stage_results({:call, from}, :get_results, data) do
    {:keep_state, data, [{:reply, from, {:ok, :waiting_for_stage_results}}]}
  end

  def awaiting_stage_results(:info, {:stage_response, node_name, {:ok, stage_result}}, data) do
    updated_temp_results = Map.put(data.temp_batch_results, node_name, stage_result)
    updated_pending_nodes = List.delete(data.pending_nodes, node_name)

    new_data = %{
      data
      | temp_batch_results: updated_temp_results,
        pending_nodes: updated_pending_nodes
    }

    if Enum.empty?(updated_pending_nodes) do
      final_results = Map.merge(data.results, new_data.temp_batch_results)

      next_data = %{
        new_data
        | results: final_results,
          temp_batch_results: %{},
          current_batch_details: %{}
      }

      {:next_state, :waiting_for_plan, next_data, [{:next_event, :internal, :plan}]}
    else
      {:keep_state, new_data}
    end
  end

  def awaiting_stage_results(:info, {:stage_response, node_name, {:error, reason_of_error}}, data) do
    {node_def, node_ctx} = Map.get(data.current_batch_details, node_name)
    error_info_tuple = {node_name, node_def, node_ctx, reason_of_error}

    data_for_error_handling = %{
      data
      | temp_batch_results: %{},
        pending_nodes: [],
        current_batch_details: %{}
    }

    handle_error({:error, error_info_tuple}, data_for_error_handling)
  end

  def awaiting_stage_results(event_type, event_content, data) do
    Logger.warning(
      "[BeamMePrompty] Agent [#{inspect(data.agent_module)}] (sid: #{inspect(data.session_id)})  Unexpected event in awaiting_stage_results: #{inspect(event_type)} - #{inspect(event_content)}"
    )

    :keep_state_and_data
  end

  def idle({:call, from}, :get_results, data) do
    {:keep_state, data, [{:reply, from, {:ok, :idle, data.results}}]}
  end

  def idle(:cast, {:message, message}, data) do
    entry_point_stage = find_entry_point_stage(data.dag.nodes)

    Logger.debug(
      "[BeamMePrompty] Agent [#{inspect(data.agent_module)}] (sid: #{inspect(data.session_id)}) received message: #{inspect(message)}"
    )

    if entry_point_stage do
      stage_pid = Map.get(data.stage_workers, entry_point_stage)
      GenStateMachine.cast(stage_pid, {:update_messages, message, false})
    end

    data_for_replan = %{
      data
      | previous_results: data.previous_results ++ [data.results],
        results: %{},
        pending_nodes: [],
        nodes_to_execute: [],
        temp_batch_results: %{},
        current_batch_details: %{}
    }

    {:next_state, :waiting_for_plan, data_for_replan, [{:next_event, :internal, :plan}]}
  end

  def idle(event_type, event_content, data) do
    Logger.warning(
      "Unexpected event in idle state for agent #{inspect(self())}: #{inspect(event_type)} - #{inspect(event_content)}"
    )

    {:keep_state, data}
  end

  def completed({:call, from}, :get_results, data) do
    {:keep_state, data, [{:reply, from, {:ok, :completed, data.results}}]}
  end

  def completed({:call, from}, {:get_node_result, node_name}, data) do
    result = Map.get(data.results, node_name)

    case result do
      nil -> {:keep_state, data, [{:reply, from, {:error, :node_not_found}}]}
      _ -> {:keep_state, data, [{:reply, from, {:ok, :completed, result}}]}
    end
  end

  def completed(:info, :cleanup, data) do
    # This :cleanup event is an internal signal if we decide to use it before termination.
    # Actual agent's handle_cleanup is called in GenStateMachine.terminate/3.
    if data.stages_supervisor_pid && Process.alive?(data.stages_supervisor_pid) do
      DynamicSupervisor.stop(data.stages_supervisor_pid)
    end

    {:keep_state, data}
  end

  def completed(event_type, event_content, data) do
    Logger.warning(
      "Unexpected event in completed state: #{inspect(event_type)} - #{inspect(event_content)}"
    )

    {:keep_state, data}
  end

  @impl true
  def terminate(reason, _state_name, data) do
    execution_status =
      case reason do
        :normal -> :completed
        :shutdown -> :completed
        {:shutdown, :completed} -> :completed
        _ -> :error
      end

    if data.agent_module do
      data.agent_module.handle_cleanup(execution_status, data.current_state)
    end

    # Ensure supervisor is stopped if it was started and is still alive
    if data.stages_supervisor_pid && Process.alive?(data.stages_supervisor_pid) do
      DynamicSupervisor.stop(data.stages_supervisor_pid)
    end

    :ok
  end

  defp handle_error({:error, error_detail}, data) do
    error_class_module = Errors.to_class(error_detail)

    agent_error_response = data.agent_module.handle_error(error_class_module, data.current_state)

    case agent_error_response do
      {:retry, new_agent_state_for_retry} ->
        data_for_retry = %{
          data
          | current_state: new_agent_state_for_retry,
            pending_nodes: [],
            nodes_to_execute: [],
            temp_batch_results: %{},
            current_batch_details: %{}
        }

        {:next_state, :waiting_for_plan, data_for_retry, [{:next_event, :internal, :plan}]}

      {:stop, stop_reason} ->
        {:stop, {:agent_stopped_execution, stop_reason}, data}

      {:restart, restart_reason} ->
        {:stop, {:restart_requested, restart_reason}, data}

      unexpected_response ->
        Logger.error(
          "Unexpected response from agent's handle_error: #{inspect(unexpected_response)}. Stopping."
        )

        {:stop, {:unexpected_handle_error_response, unexpected_response}, data}
    end
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
end
