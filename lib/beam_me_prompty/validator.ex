defmodule BeamMePrompty.Validator do
  @moduledoc """
  Validates input data against OpenAPI Schemas
  """
  @moduledoc section: :validations

  alias BeamMePrompty.Agent.Dsl.DataPart
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
  @spec validate(
          nil | OpenApiSpex.Schema.t(),
          map() | DataPart.t()
        ) ::
          {:ok, map()} | {:error, ValidationError.t()}
  def validate(nil, data) when is_map(data), do: {:ok, data}

  def validate(schema, %DataPart{} = data_part), do: validate(schema, data_part.data)

  def validate(schema, data) when is_map(data) do
    case OpenApiSpex.cast_value(data, schema) do
      {:ok, validated_data} ->
        {:ok, validated_data}

      {:error, errors} ->
        {:error, ValidationError.exception(cause: format_cast_errors(errors))}
    end
  end

  def validate(_schema, data),
    do: {:error, ValidationError.exception(cause: "Invalid input data format: #{inspect(data)}")}

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
    |> Enum.map_join(".", &to_string/1)
  end
end
