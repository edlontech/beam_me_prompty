defmodule BeamMePrompty.Errors.SerializationError do
  @moduledoc """
  Error raised during agent DSL serialization processes.

  This error indicates that the system encountered issues while attempting to
  serialize an agent definition to JSON format. It belongs to the `:invalid` error class.

  ## Fields

    * `:cause` - The underlying reason for the serialization failure. This can be:
      - A specific JSON encoding error (e.g., `%Jason.EncodeError{...}`)
      - A protocol error when a struct doesn't implement Jason.Encoder
      - A descriptive string explaining the serialization issue
      - A map with structured error details

  ## Examples

  Creating an error with a JSON encoding cause:

      %BeamMePrompty.Errors.SerializationError{
        cause: %Jason.EncodeError{message: "cannot encode function"}
      }

  Creating an error with a descriptive cause:

      %BeamMePrompty.Errors.SerializationError{
        cause: "Anonymous function cannot be serialized"
      }

  Creating an error with structured cause:

      %BeamMePrompty.Errors.SerializationError{
        cause: %{field: :api_key, type: :function, message: "function not serializable"}
      }
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:cause], class: BeamMePrompty.Errors.Invalid

  @type t() :: Splode.Error.t()

  @doc false
  def message(%{cause: cause}) do
    "Serialization error: #{inspect(cause)}"
  end
end
