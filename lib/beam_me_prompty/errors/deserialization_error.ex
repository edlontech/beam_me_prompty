defmodule BeamMePrompty.Errors.DeserializationError do
  @moduledoc """
  Error raised during agent DSL deserialization processes.

  This error indicates that the system encountered issues while attempting to
  deserialize JSON data back into agent DSL structures. It belongs to the `:invalid` error class.

  ## Fields

    * `:cause` - The underlying reason for the deserialization failure. This can be:
      - A specific JSON decoding error (e.g., `%Jason.DecodeError{...}`)
      - A module resolution error when a module is not found or not allowed
      - A function resolution error when a function reference is invalid
      - A descriptive string explaining the deserialization issue
      - A map with structured error details

  ## Examples

  Creating an error with a JSON decoding cause:

      %BeamMePrompty.Errors.DeserializationError{
        cause: %Jason.DecodeError{data: "invalid json", position: 10}
      }

  Creating an error with a module resolution cause:

      %BeamMePrompty.Errors.DeserializationError{
        cause: "Module BeamMePrompty.UnknownModule not found or not allowed"
      }

  Creating an error with structured cause:

      %BeamMePrompty.Errors.DeserializationError{
        cause: %{field: :llm_client, module: "BeamMePrompty.UnknownLLM", message: "module not allowed"}
      }
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:cause], class: BeamMePrompty.Errors.Invalid

  @type t() :: Splode.Error.t()

  @doc false
  def message(%{cause: cause}) do
    "Deserialization error: #{inspect(cause)}"
  end
end
