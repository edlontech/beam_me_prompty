defmodule BeamMePrompty.Errors.ParsingError do
  @moduledoc """
  Represents an error when parsing input data within the BeamMePrompty system.

  This error is raised when the system encounters issues while attempting to parse
  content, typically due to malformed or unexpected input data format.
  It belongs to the `:invalid` error class.

  ## Fields

    * `:module` - The module or context where the parsing error occurred. This helps
      in pinpointing the location of the error.
    * `:cause` - The underlying reason for the parsing failure. This field is flexible
      and can hold various types of information:
        - A specific parser error struct (e.g., `%Jason.DecodeError{...}`).
        - A descriptive string explaining the malformation.
        - A snippet of the offending content if it's small and helps in debugging.
      Providing detailed information in `:cause` is crucial for diagnosing parsing issues.

  ## Example

  If parsing a JSON string in `MyModule.Processor` fails due to a `Jason.DecodeError`:

      %BeamMePrompty.Errors.ParsingError{
        module: MyModule.Processor,
        cause: %Jason.DecodeError{data: "invalid json", position: 10, token: "j"}
      }

  Another example with a string cause:

      %BeamMePrompty.Errors.ParsingError{
        module: MyConfigLoader,
        cause: "Missing required key 'api_url' in configuration file."
      }
  """
  @moduledoc section: :error_handling

  use Splode.Error, fields: [:module, :cause], class: :invalid

  @doc false
  def message(%{module: module, cause: cause}) do
    "Parsing error in #{module}: #{inspect(cause)}"
  end
end
