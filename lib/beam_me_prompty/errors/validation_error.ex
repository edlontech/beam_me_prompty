defmodule BeamMePrompty.Errors.ValidationError do
  @moduledoc """
  Error raised when validation fails in the BeamMePrompty system.

  This error is classified as a `:framework` error, indicating it originates
  from the framework itself rather than from invalid input or external systems.
  """
  use Splode.Error, fields: [:cause], class: :framework

  @doc false
  def message(%{cause: cause}) do
    "Validation error: #{inspect(cause)}"
  end
end
