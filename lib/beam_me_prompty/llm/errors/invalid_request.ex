defmodule BeamMePrompty.LLM.Errors.InvalidRequest do
  use Splode.Error, fields: [:module, :cause], class: :invalid

  def message(%{module: module, cause: cause}) do
    "Invalid request to LLM #{module}: #{inspect(cause)}"
  end
end
