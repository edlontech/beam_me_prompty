defmodule BeamMePrompty.Errors.Unknown do
  use Splode.ErrorClass, class: :unknown

  defmodule Unknown do
    use Splode.Error, class: :unknown

    def message(%{error: error}) do
      if is_binary(error) do
        to_string(error)
      else
        inspect(error)
      end
    end
  end
end
