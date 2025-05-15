defmodule BeamMePrompty.Errors.ParsingError do
  @moduledoc """
  Represents a parsing error within the BeamMePrompty framework.

  This error is raised when the system encounters issues while parsing content
  in different modules. It belongs to the `:framework` error class, indicating
  that the error originates from within the framework itself.

  ## Required Fields

  When raising this error, you must provide the following fields:

  * `:module` - The module where the parsing error occurred
  * `:cause` - The cause of the parsing error, which can be any term
  """

  use Splode.Error, fields: [:module, :cause], class: :framework

  @doc false
  def message(%{module: module, cause: cause}) do
    "Invalid Parsing at #{module}: #{inspect(cause)}"
  end
end
