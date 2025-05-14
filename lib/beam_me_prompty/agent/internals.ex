defmodule BeamMePrompty.Agent.Internals do
  use GenStateMachine, callback_mode: :state_functions

  defstruct [
    :dag,
    :module,
    :global_input,
    :nodes_to_execute,
    :initial_state,
    :current_state,
    :started_at,
    :last_transition_at,
    :opts,
    :stages_supervisor_pid,
    :stage_workers,
    :results,
    :pending_nodes,
    :current_batch_details,
    :temp_batch_results
  ]

  require Logger

  alias BeamMePrompty.Agent.StagesSupervisor
  alias BeamMePrompty.DAG
  alias BeamMePrompty.Errors

  @impl true
  def init({dag, input, state, opts, module}) do
    case StagesSupervisor.start_link(:ok) do
      {:ok, sup_pid} ->
        stage_workers =
          Enum.into(dag.nodes, %{}, fn {node_name, _node_definition} ->
            case StagesSupervisor.start_stage_worker(sup_pid, node_name) do
              {:ok, stage_pid} ->
                {node_name, stage_pid}

              {:ok, pid, _extra_info} ->
                {node_name, pid}

              {:error, reason} ->
                raise "Failed to start stage worker for #{node_name}: #{inspect(reason)}"
            end
          end)

        data = %__MODULE__{
          dag: dag,
          opts: opts,
          module: module,
          global_input: input,
          initial_state: state,
          current_state: state,
          started_at: System.monotonic_time(:millisecond),
          stages_supervisor_pid: sup_pid,
          stage_workers: stage_workers,
          results: %{},
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
    ready_nodes = DAG.find_ready_nodes(data.dag, data.results)

    cond do
      map_size(data.results) == map_size(data.dag.nodes) ->
        data.module.handle_complete(data.results, data.current_state)
        {:next_state, :completed, data}

      Enum.empty?(ready_nodes) ->
        {:error,
         Errors.ExecutionError.exception(
           step: :waiting_for_plan,
           cause: "No nodes are ready to execute"
         )}
        |> handle_error(data)

      true ->
        nodes_to_execute =
          Enum.map(ready_nodes, fn node_name ->
            node = Map.get(data.dag.nodes, node_name)

            node_context =
              Map.merge(data.initial_state, %{
                dependency_results: data.results,
                global_input: data.global_input
              })

            {node_name, node, node_context}
          end)

        {:next_state, :execute_nodes, %__MODULE__{data | nodes_to_execute: nodes_to_execute},
         [{:next_event, :internal, :execute}]}
    end
  end

  def waiting_for_plan(:call, {:get_state, from}, data) do
    {:keep_state, data, [{:reply, from, {:ok, data.current_state}}]}
  end

  def execute_nodes(:internal, :execute, data) do
    if Enum.empty?(data.nodes_to_execute) do
      # This case should ideally not be hit if waiting_for_plan ensures nodes_to_execute is populated
      # before transitioning here with an :execute event.
      # However, as a safeguard, transition back to planning.
      {:next_state, :waiting_for_plan, data, [{:next_event, :internal, :plan}]}
    else
      current_batch_details =
        Enum.into(data.nodes_to_execute, %{}, fn {name, nd_def, nd_ctx} ->
          {name, {nd_def, nd_ctx}}
        end)

      Enum.each(data.nodes_to_execute, fn {node_name, node_def, node_ctx} ->
        stage_pid = Map.get(data.stage_workers, node_name)
        GenStateMachine.cast(stage_pid, {:execute, node_name, node_def, node_ctx, self()})
      end)

      pending_node_names = Enum.map(data.nodes_to_execute, fn {name, _, _} -> name end)

      new_data = %{
        data
        | nodes_to_execute: [],
          pending_nodes: pending_node_names,
          current_batch_details: current_batch_details,
          temp_batch_results: %{}
      }

      {:next_state, :awaiting_stage_results, new_data}
    end
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

  def awaiting_stage_results({:call, {from, _}}, :get_state, data) do
    {:keep_state, data, [{:reply, from, {:ok, data.current_state}}]}
  end

  def awaiting_stage_results(event_type, event_content, _data) do
    Logger.warning(
      "Unexpected event in awaiting_stage_results: #{inspect(event_type)} - #{inspect(event_content)}"
    )

    :keep_state_and_data
  end

  defp handle_error({:error, error}, data) do
    error
    |> Errors.to_class()
    |> data.module.handle_error(data.current_state)
    |> handle_error_callback(data)
  end

  defp handle_error_callback({:stop, reason}, data) do
    {:stop, reason, data}
  end
end
