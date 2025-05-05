defmodule BeamMePrompty.DAG.Executor.StateMachine do
  @moduledoc """
  GenStatem-based executor for BeamMePrompty agents.
  Provides robust state management and concurrency control.
  """
  use GenStateMachine, callback_mode: :handle_event_function
  use BeamMePrompty.DAG

  alias BeamMePrompty.DAG.Executor.State, as: ExecutorState

  @impl true
  def execute(dag, initial_context, node_executor) do
    case DAG.validate(dag) do
      :ok ->
        # Start the state machine and execute the DAG
        {:ok, pid} = GenStateMachine.start_link(__MODULE__, {dag, initial_context, node_executor})
        result = GenStateMachine.call(pid, :execute)
        GenStateMachine.stop(pid)
        result

      error ->
        error
    end
  end

  @impl true
  def init({dag, initial_context, node_executor}) do
    {:ok, :ready,
     %{
       dag: dag,
       initial_context: initial_context,
       node_executor: node_executor,
       results: %{},
       current_node: nil
     }}
  end

  # Handle eecute call from client
  @impl true
  def handle_event({:call, from}, :execute, :ready, data) do
    # Transition to executing state and begin node execution
    {:next_state, :executing, Map.put(data, :caller, from),
     [{:next_event, :internal, :execute_next}]}
  end

  # Process the next available node
  @impl true
  def handle_event(:internal, :execute_next, :executing, data) do
    ready_nodes = DAG.find_ready_nodes(data.dag, data.results)

    cond do
      # All nodes have been executed successfully
      map_size(data.results) == map_size(data.dag.nodes) ->
        {:next_state, :complete, data, [{:reply, data.caller, {:ok, data.results}}]}

      # No more nodes to process but DAG not complete - possibly unreachable nodes
      Enum.empty?(ready_nodes) ->
        error = "Not all nodes could be executed. Possible unreachable nodes."

        {:next_state, :error, Map.put(data, :error, error),
         [{:reply, data.caller, {:error, error}}]}

      # Process the next ready node
      true ->
        node_name = hd(ready_nodes)
        node = Map.get(data.dag.nodes, node_name)

        # Create the node execution context with dependency results
        node_context = Map.merge(data.initial_context, %{dependency_results: data.results})

        # Execute the node
        case execute_node(node, node_context, data.node_executor) do
          {:ok, result} ->
            # Update results and continue execution
            new_data = %{data | results: Map.put(data.results, node_name, result)}
            {:keep_state, new_data, [{:next_event, :internal, :execute_next}]}

          {:error, reason} ->
            # Handle node execution error
            error = "Error executing node #{node_name}: #{inspect(reason)}"

            {:next_state, :error, Map.put(data, :error, error),
             [{:reply, data.caller, {:error, error}}]}
        end
    end
  end
end
