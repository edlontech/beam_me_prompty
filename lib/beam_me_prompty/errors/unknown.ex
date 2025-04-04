defmodule BeamMePrompty.Errors.Unknown do
  @moduledoc """
  Represents the `:unknown` error class in the BeamMePrompty error handling system.

  This error class is intended for handling unclassified or unexpected errors that don't
  fit into the other error categories. It serves as a fallback for error conditions
  that weren't explicitly anticipated by the application design.
  """
  @moduledoc section: :error_handling
  use Splode.ErrorClass, class: :unknown

  defmodule Unknown do
    @moduledoc """
    A generic error type within the `:unknown` error class.

    This error represents a completely unclassified error and serves as the default
    error type for the error handling system. Any uncaught exceptions or errors that
    can't be classified will typically be converted to this error type.

    Typically, this error would be created with a map containing an `:error` key:

        %BeamMePrompty.Errors.Unknown.Unknown{error: "Something unexpected happened"}
    """
    @moduledoc section: :error_handling

    use Splode.Error, class: :unknown

    @doc false
    def message(%{error: error}) do
      if is_binary(error) do
        to_string(error)
      else
        inspect(error)
      end
    end
  end
end
