defmodule BeamMePrompty.Validator do
  @moduledoc """
  Validates input data against OpenAPI Schemas
  """

  alias BeamMePrompty.Errors.ValidationError

  @doc """
  Validates input data against a schema.

  ## Parameters
    * `schema` - The OpenAPI schema to validate against
    * `data` - The data to validate
    
  ## Returns
    * `{:ok, validated_data}` - If validation succeeds
    * `{:error, errors}` - If validation fails
  """
  def validate(nil, data) when is_map(data), do: {:ok, data}

  def validate(schema, data) when is_map(data) do
    case OpenApiSpex.cast_value(data, schema) do
      {:ok, validated_data} ->
        {:ok, validated_data}

      {:error, errors} ->
        {:error, ValidationError.exception(cause: format_cast_errors(errors))}
    end
  end

  def validate(_schema, data), do: {:error, "Invalid input data format: #{inspect(data)}"}

  defp format_cast_errors(errors) when is_list(errors) do
    Enum.map(errors, &format_cast_error/1)
  end

  defp format_cast_error(%OpenApiSpex.Cast.Error{} = error) do
    path_str = format_path(error.path)

    reason_message =
      case error.reason do
        :invalid_type -> "Expected type #{inspect(error.type)}, but got #{inspect(error.value)}"
        :invalid_format -> "Invalid format for value #{inspect(error.value)}"
        :missing_field -> "Missing required field"
        _ -> "Unknown reason: #{inspect(error.reason)}"
      end

    "#{reason_message} at path: #{path_str}"
  end

  defp format_path([]), do: "root"

  defp format_path(path) when is_list(path) do
    path
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end
end
