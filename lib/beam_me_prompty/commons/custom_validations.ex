defmodule BeamMePrompty.Commons.CustomValidations do
  @moduledoc """
  Provides custom validation functions for various data types and ranges.

  This module contains helper functions for validating data according to specific
  constraints, returning standardized success/error tuples.
  """
  @moduledoc section: :validations

  @doc """
  Validates that a value is a float within the specified range.

  ## Parameters
    * `value` - The value to validate
    * `min_val` - The minimum acceptable value (inclusive)
    * `max_val` - The maximum acceptable value (inclusive)

  ## Returns
    * `{:ok, value}` - If the value is a float within the specified range
    * `{:error, message}` - If the value is not a float or is outside the specified range

  ## Examples

      iex> CustomValidations.validate_float_range(2.5, 1.0, 3.0)
      {:ok, 2.5}

      iex> CustomValidations.validate_float_range("not a float", 1.0, 3.0)
      {:error, "must be a float between 1.0 and 3.0. Got: \"not a float\""}

      iex> CustomValidations.validate_float_range(0.5, 1.0, 3.0)
      {:error, "must be a float between 1.0 and 3.0. Got: 0.5"}
  """
  @spec validate_float_range(any(), float(), float()) :: {:ok, float()} | {:error, String.t()}
  def validate_float_range(value, min_val, max_val)
      when is_float(value) and value >= min_val and value <= max_val,
      do: {:ok, value}

  @spec validate_float_range(any(), float(), float()) :: {:error, String.t()}
  def validate_float_range(value, min_val, max_val) do
    {:error, "must be a float between #{min_val} and #{max_val}. Got: #{inspect(value)}"}
  end
end
