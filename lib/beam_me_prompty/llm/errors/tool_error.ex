defmodule BeamMePrompty.LLM.Errors.ToolError do
  @moduledoc """
  Represents a failed tool execution.

  ## Required Fields

  When raising this error, you must provide the following fields:

  * `:module` - The module where the invalid configuration was detected
  * `:cause` - The specific details about what made the configuration invalid
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:module, :cause], class: :external

  @type t() :: Splode.Error.t()

  @doc false
  def message(%{module: module, cause: cause}) do
    "The tool [#{module}] finished with error, cause: #{inspect(cause)}"
  end
end
