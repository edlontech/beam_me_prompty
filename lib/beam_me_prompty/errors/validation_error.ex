defmodule BeamMePrompty.Errors.ValidationError do
  use Splode.Error, fields: [:cause], class: :framework

  def message(%{cause: cause}) do
    "Validation error: #{inspect(cause)}"
  end
end
