defmodule BeamMePrompty.Errors.ExecutionError do
  @moduledoc """
  Represents an internal error within the agent execution pipeline or orchestrator.

  This error is raised when the framework itself encounters an unexpected issue
  while managing the execution of an agent's stages (e.g., problems with
  stage transitions, internal state management of the executor, or issues with the
  Directed Acyclic Graph (DAG) processing logic).

  It belongs to the `:framework` error class. This error should *not* typically be used
  for issues originating from within a stage's specific logic if those are better
  represented by other error types (e.g., `BeamMePrompty.Errors.Invalid` if a stage
  receives bad input from a prior stage, or `BeamMePrompty.LLM.Errors.ToolError` if a
  tool called by a stage fails for its own reasons).

  ## Fields

    * `:stage` - The identifier of the stage (e.g., an atom representing the stage name)
      that the execution pipeline was attempting to process or transition from/to when
      the internal error occurred. This can be `nil` if the error is not specific
      to a single stage (e.g., a general pipeline initialization failure).
    * `:cause` - A description or the underlying exception that caused the execution
      pipeline to fail. This should detail the nature of the internal framework error.

  ## Example

  If the execution pipeline fails to find the next set of runnable stages from the DAG
  due to an unexpected internal state:

      %BeamMePrompty.Errors.ExecutionError{
        stage: :planning_phase, # The current phase when the error was detected
        cause: "Internal inconsistency: Failed to determine next runnable stages in DAG."
      }

  Another example, if a specific pipeline operation fails:

      %BeamMePrompty.Errors.ExecutionError{
        stage: :data_aggregation_stage,
        cause: "Executor failed to commit stage results due to: :internal_state_corruption"
      }
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:stage, :cause], class: :framework

  @type t() :: Splode.Error.t()

  def message(%{stage: stage, cause: cause}) when not is_nil(stage) do
    "Internal agent execution error at/near stage #{inspect(stage)}: #{inspect(cause)}"
  end

  # Handles case where stage might be nil
  def message(%{cause: cause}) do
    "Internal agent execution error: #{inspect(cause)}"
  end
end
