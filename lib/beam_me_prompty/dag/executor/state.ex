defmodule BeamMePrompty.DAG.Executor.State do
  @moduledoc """
  Encapsulates the execution state for a BeamMePrompty agent.
  """
  defstruct [
    :dag,
    :results,
    :context,
    :current_stage,
    :pending_stages,
    :completed_stages,
    :error
  ]

  @type t :: %__MODULE__{
          dag: BeamMePrompty.DAG.t(),
          results: map(),
          context: map(),
          current_stage: atom() | nil,
          pending_stages: list(atom()),
          completed_stages: list(atom()),
          error: any() | nil
        }

  @doc """
  Creates a new execution state from a DAG and initial context
  """
  def new(dag, initial_context) do
    %__MODULE__{
      dag: dag,
      results: %{},
      context: initial_context,
      pending_stages: BeamMePrompty.DAG.topological_sort(dag),
      completed_stages: []
    }
  end

  @doc """
  Updates the state with a completed stage result
  """
  def update_result(state, stage_name, result) do
    %{
      state
      | results: Map.put(state.results, stage_name, result),
        completed_stages: [stage_name | state.completed_stages],
        pending_stages: List.delete(state.pending_stages, stage_name)
    }
  end

  @doc """
  Marks the state with the current stage being executed
  """
  def set_current_stage(state, stage_name) do
    %{state | current_stage: stage_name}
  end

  @doc """
  Marks the state with an error
  """
  def set_error(state, error) do
    %{state | error: error}
  end
end
