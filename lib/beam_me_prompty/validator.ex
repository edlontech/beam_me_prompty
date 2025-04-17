defmodule BeamMePrompty.Validator do
  @moduledoc """
  Validates input data against schemas using Peri.

  This module provides functions to validate input data against schemas
  defined using the Peri validation library.
  """

  @doc """
  Validates input data against a schema.

  ## Parameters
    * `schema` - The Peri schema to validate against
    * `data` - The data to validate
    
  ## Returns
    * `{:ok, validated_data}` - If validation succeeds
    * `{:error, errors}` - If validation fails
  """
  def validate(schema, data) when is_map(schema) and is_map(data) do
    case Peri.validate(schema, data) do
      {:ok, validated_data} -> {:ok, validated_data}
      {:error, errors} -> {:error, format_errors(errors)}
    end
  end

  def validate(nil, data) when is_map(data), do: {:ok, data}

  def validate(_schema, data), do: {:error, "Invalid input data format: #{inspect(data)}"}

  defp format_errors(errors) when is_list(errors) do
    Enum.map(errors, fn error ->
      path_str = format_path(error.path)

      error_message = to_string(error.message || "Unknown error")

      message =
        if error_message =~ "expected type" and Map.has_key?(error, :field) do
          "#{error_message} for field #{error.field}#{path_str}"
        else
          "#{error_message} at path: #{path_str}"
        end

      message
    end)
  end

  defp format_path([]), do: "root"

  defp format_path(path) when is_list(path) do
    path
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end

  defp format_path(path) do
    cond do
      is_map(path) and Map.has_key?(path, :path) ->
        format_path(path.path)

      is_map(path) and Map.has_key?(path, :field) ->
        to_string(path.field)

      true ->
        to_string(path)
    end
  end
end
