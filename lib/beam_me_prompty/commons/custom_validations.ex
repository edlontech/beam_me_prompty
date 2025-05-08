defmodule BeamMePrompty.Commons.CustomValidations do
  def validate_float_range(value, min_val, max_val)
      when is_float(value) and value >= min_val and value <= max_val,
      do: {:ok, value}

  def validate_float_range(value, min_val, max_val) do
    {:error, "must be a float between #{min_val} and #{max_val}. Got: #{inspect(value)}"}
  end
end
