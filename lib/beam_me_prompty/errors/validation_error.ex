defmodule BeamMePrompty.Errors.ValidationError do
  @moduledoc """
  Error raised when input data fails validation checks within the BeamMePrompty system.

  This error indicates that the provided data does not meet the required criteria
  or constraints. It is classified as an `:invalid` error.

  ## Fields

    * `:cause` - Describes the reason for the validation failure. This can be a
      simple string, a map with structured error details (e.g., field, rule, message),
      or a keyword list. It may also contain error details from underlying validation
      libraries.

  ## Examples

  Creating an error with a simple cause:

      %BeamMePrompty.Errors.ValidationError{cause: "Input 'email' is not valid."}

  Creating an error with a structured cause:

      %BeamMePrompty.Errors.ValidationError{
        cause: %{field: :email, rule: :format, message: "is invalid"}
      }
  """
  @moduledoc section: :error_handling
  use Splode.Error, fields: [:cause], class: BeamMePrompty.Errors.Invalid

  @type t() :: Splode.Error.t()

  @doc false
  def message(%{cause: cause}) do
    "Validation error: #{inspect(cause)}"
  end
end
