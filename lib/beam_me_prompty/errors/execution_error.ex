defmodule BeamMePrompty.Errors.ExecutionError do
  @moduledoc """
  Represents an execution error within the BeamMePrompty framework.

  This error is raised when the system encounters issues during the execution of
  agent steps or operations. It belongs to the `:framework` error class, indicating
  that the error originates from within the framework's execution pipeline.
  """

  use Splode.Error, fields: [:stage, :cause], class: :framework

  def message(%{stage: stage, cause: cause}) do
    "Agent execution error at stage #{inspect(stage)}: #{inspect(cause)}"
  end
end
