defmodule BeamMePrompty.LLM.Errors.InvalidConfig do
  use Splode.Error, fields: [:module, :cause], class: :invalid

  def message(%{module: module, cause: cause}) do
    "Invalid Settings #{module}: #{inspect(cause)}"
  end
end
