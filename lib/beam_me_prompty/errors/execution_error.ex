defmodule BeamMePrompty.Errors.ExecutionError do
  use Splode.Error, fields: [:step, :cause], class: :framework

  def message(%{step: step, cause: cause}) do
    "Pipeline execution error at step #{inspect(step)}: #{inspect(cause)}"
  end
end
