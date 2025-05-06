defmodule BeamMePrompty.Executors.AgentState do
  @moduledoc """
  Encapsulates the execution state for a BeamMePrompty agent.
  Tracks execution progress, results, and the current state of the state machine.
  """
  defstruct [
    # The DAG being executed
    :dag,
    # Results of executed nodes
    :results,
    # Initial context provided at start
    :initial_context,
    # Currently executing node
    :current_node,
    # PID of the caller process
    :caller,
    # Current state machine state 
    :state,
    # Timestamp when execution started
    :started_at,
    # Timestamp of last state transition
    :last_transition_at,
    # Error details if in error state
    :error
  ]

  @type t :: %__MODULE__{
          dag: map(),
          results: map(),
          initial_context: map(),
          current_node: String.t() | nil,
          caller: pid() | nil,
          state: atom(),
          started_at: integer() | nil,
          last_transition_at: integer() | nil,
          error: any() | nil
        }

  @doc """
  Creates a new execution state from a DAG, initial context, and node executor function
  """
  def new(dag, initial_context) do
    now = System.monotonic_time()

    %__MODULE__{
      dag: dag,
      results: %{},
      initial_context: initial_context,
      state: :ready,
      started_at: now,
      last_transition_at: now,
      current_node: nil
    }
  end

  @doc """
  Updates the state with a completed node result
  """
  def update_result(state, node_name, result) do
    %{state | results: Map.put(state.results, node_name, result)}
  end

  @doc """
  Sets the current node being executed
  """
  def set_current_node(state, node_name) do
    %{state | current_node: node_name}
  end

  @doc """
  Sets the caller for the state machine
  """
  def set_caller(state, caller) do
    %{state | caller: caller}
  end

  @doc """
  Transitions the state machine to a new state
  """
  def transition_to(state, new_state) do
    %{state | state: new_state, last_transition_at: System.monotonic_time()}
  end

  @doc """
  Marks the state with an error
  """
  def set_error(state, error) do
    %{state | error: error}
  end

  @doc """
  Returns execution statistics
  """
  def stats(state) do
    now = System.monotonic_time()
    execution_time = System.convert_time_unit(now - state.started_at, :native, :millisecond)

    %{
      state: state.state,
      nodes_total: map_size(state.dag.nodes),
      nodes_completed: map_size(state.results),
      current_node: state.current_node,
      execution_time_ms: execution_time
    }
  end
end
