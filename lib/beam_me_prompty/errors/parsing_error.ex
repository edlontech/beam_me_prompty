defmodule BeamMePrompty.Errors.ParsingError do
  use Splode.Error, fields: [:module, :cause], class: :framework

  def message(%{module: module, cause: cause}) do
    "Invalid Parsing at #{module}: #{inspect(cause)}"
  end
end
