defmodule BeamMePrompty.LLM.Errors.UnexpectedLLMResponse do
  use Splode.Error, fields: [:module, :status, :cause], class: :external

  def message(%{status: status, module: module, cause: cause}) do
    "Unexpected response from LLM #{module} (#{status}): #{inspect(cause)}"
  end
end
