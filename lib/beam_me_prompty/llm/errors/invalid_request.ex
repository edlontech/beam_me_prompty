defmodule BeamMePrompty.LLM.Errors.InvalidRequest do
  @moduledoc """
  Represents an invalid request error within the BeamMePrompty LLM system.

  This error is raised when the system encounters issues with requests made to
  a Large Language Model (LLM), such as invalid parameters, malformed prompts,
  or other request-specific problems. It belongs to the `:invalid` error class,
  indicating that it represents an error related to invalid input or state.

  ## Required Fields

  When raising this error, you must provide the following fields:

  * `:module` - The module where the invalid request originated or was detected
  * `:cause` - The specific details about what made the request invalid
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:module, :cause], class: :invalid

  def message(%{module: module, cause: cause}) do
    "Invalid request to LLM #{module}: #{inspect(cause)}"
  end
end
