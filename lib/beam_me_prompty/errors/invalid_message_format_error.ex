defmodule BeamMePrompty.Errors.InvalidMessageFormatError do
  @moduledoc """
   This error is raised when a message does not conform to the expected format.
  """
  @moduledoc section: :error_handling

  use Splode.Error, class: :invalid, fields: [:reason, :offending_value]

  def message(%{reason: reason, offending_value: value}) do
    "#{reason}: #{inspect(value)}"
  end
end
