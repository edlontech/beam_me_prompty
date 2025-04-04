defmodule BeamMePrompty.LLM.Errors.UnexpectedLLMResponse do
  @moduledoc """
  Represents an unexpected response error from an external LLM service.

  This error is raised when the system receives an unexpected, malformed, or 
  error response from an external Large Language Model (LLM) provider. It belongs
  to the `:external` error class, indicating that it represents an error 
  originating from an external system or dependency.

  ## Required Fields

  When raising this error, you must provide the following fields:

  * `:module` - The module that was interacting with the LLM service
  * `:status` - The status code or indicator received from the LLM service
  * `:cause` - The specific details about what was unexpected in the response
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:module, :status, :cause], class: :external

  def message(%{status: status, module: module, cause: cause}) do
    "Unexpected response from LLM #{module} (#{status}): #{inspect(cause)}"
  end
end
