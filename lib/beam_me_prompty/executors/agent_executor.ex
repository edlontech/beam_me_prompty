defmodule BeamMePrompty.Executors.StateMachine do
  @moduledoc """
  GenStatem-based executor for BeamMePrompty agents.
  Provides robust state management and concurrency control.

  State transitions:
  - :ready -> :planning (initial transition when execute is called)
  - :planning -> :node_execution (when ready nodes are found)
  - :planning -> :complete (when all nodes are executed)
  - :planning -> :error (when no ready nodes but DAG incomplete)
  - :node_execution -> :node_completed or :error
  - :node_completed -> :planning (to find next nodes)
  """
  use GenStateMachine, callback_mode: :handle_event_function

  alias BeamMePrompty.DAG.Executor.State, as: ExecutorState

  def execute(dag, initial_context) do
    case DAG.validate(dag) do
      :ok ->
        # Start the state machine and execute the DAG
        {:ok, pid} = GenStateMachine.start_link(__MODULE__, {dag, initial_context})
        result = GenStateMachine.call(pid, :execute)
        GenStateMachine.stop(pid)
        result

      error ->
        error
    end
  end

  @impl true
  def init({dag, initial_context}) do
    state = ExecutorState.new(dag, initial_context)
    {:ok, state.state, state}
  end

  # Handle eecute call from client
  @impl true
  def handle_event({:call, from}, :execute, :ready, data) do
    # Transition to planning state to find nodes to execute
    {:next_state, :planning, Map.put(data, :caller, from),
     [{:next_event, :internal, :plan_execution}]}
  end

  # Planning phase - identify the next set of nodes to execute
  @impl true
  def handle_event(:internal, :plan_execution, :planning, data) do
    ready_nodes = DAG.find_ready_nodes(data.dag, data.results)

    cond do
      map_size(data.results) == map_size(data.dag.nodes) ->
        {:next_state, :complete, data, [{:reply, data.caller, {:ok, data.results}}]}

      Enum.empty?(ready_nodes) ->
        error = "Not all nodes could be executed. Possible unreachable nodes."

        {:next_state, :error, Map.put(data, :error, error),
         [{:reply, data.caller, {:error, error}}]}

      true ->
        tasks =
          for node_name <- ready_nodes do
            node = Map.get(data.dag.nodes, node_name)

            Task.async(fn ->
              node_context = Map.merge(data.initial_context, %{dependency_results: data.results})
              {node_name, execute_node(node, node_context)}
            end)
          end

        # Transition to node_execution state with the running tasks
        {:next_state, :node_execution, Map.put(data, :running_tasks, tasks),
         [{:next_event, :internal, :await_tasks}]}
    end
  end

  # Parallel execution phase - wait for all tasks to complete
  @impl true
  # Await all tasks and collect their results
  def handle_event(:internal, :await_tasks, :node_execution, data) do
    task_results = Task.await_many(data.running_tasks)

    # Process the results and update the data
    {new_results, errors} =
      Enum.reduce(task_results, {data.results, []}, fn {node_name, result},
                                                       {acc_results, acc_errors} ->
        case result do
          {:ok, node_result} ->
            # Add successful result
            {Map.put(acc_results, node_name, node_result), acc_errors}

          {:error, reason} ->
            # Add to errors list
            error = "Error executing node #{node_name}: #{inspect(reason)}"
            {acc_results, [{node_name, error} | acc_errors]}
        end
      end)

    # Clean up the state by removing running_tasks
    new_data = Map.put(%{data | results: new_results}, :running_tasks, nil)

    if Enum.empty?(errors) do
      # All tasks completed successfully, go to node_completed
      {:next_state, :node_completed, new_data, [{:next_event, :internal, :node_completed}]}
    else
      # Handle errors in parallel execution
      error = "Errors in parallel execution: #{inspect(errors)}"

      {:next_state, :error, Map.put(new_data, :error, error),
       [{:reply, data.caller, {:error, error}}]}
    end
  end

  # Node execution phase - execute a specific node
  @impl true
  def handle_event(:internal, {:execute_node, node_name}, :node_execution, data) do
    node = Map.get(data.dag.nodes, node_name)

    # Create the node execution context with dependency results
    node_context = Map.merge(data.initial_context, %{dependency_results: data.results})

    # Execute the node
    case execute_node(node, node_context) do
      {:ok, result} ->
        # Update results and transition to node_completed state
        new_data = %{data | results: Map.put(data.results, node_name, result)}

        {:next_state, :node_completed, new_data,
         [{:next_event, :internal, {:node_completed, node_name}}]}

      {:error, reason} ->
        # Handle node execution error
        error = "Error executing node #{node_name}: #{inspect(reason)}"

        {:next_state, :error, Map.put(data, :error, error),
         [{:reply, data.caller, {:error, error}}]}
    end
  end

  # Node completed phase - handle successful node execution
  @impl true
  def handle_event(:internal, {:node_completed, node_name}, :node_completed, data) do
    # Go back to planning phase to find the next nodes
    {:next_state, :planning, %{data | current_node: nil},
     [{:next_event, :internal, :plan_execution}]}
  end

  # Special handler for pausing execution (extensibility point)
  @impl true
  def handle_event(:cast, :pause, _state, data) do
    {:next_state, :paused, data}
  end

  # Special handler for resuming execution
  @impl true
  def handle_event(:cast, :resume, :paused, data) do
    {:next_state, :planning, data, [{:next_vent, :internal, :plan_execution}]}
  end
end
