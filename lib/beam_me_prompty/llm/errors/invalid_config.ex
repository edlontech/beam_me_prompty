defmodule BeamMePrompty.LLM.Errors.InvalidConfig do
  @moduledoc """
  Represents an invalid configuration error within the BeamMePrompty LLM system.

  This error is raised when the system encounters invalid settings or configuration
  issues specific to the LLM (Large Language Model) component. It belongs to the
  `:invalid` error class, indicating that it represents an error related to invalid
  input or state.

  ## Required Fields

  When raising this error, you must provide the following fields:

  * `:module` - The module where the invalid configuration was detected
  * `:cause` - The specific details about what made the configuration invalid
  """
  @moduledoc section: :error_handling
  use Splode.Error, fields: [:module, :cause], class: :invalid

  @doc false
  def message(%{module: module, cause: cause}) do
    "Invalid Settings #{module}: #{inspect(cause)}"
  end
end
