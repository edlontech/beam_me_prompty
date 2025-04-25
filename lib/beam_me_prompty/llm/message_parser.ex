defmodule BeamMePrompty.LLM.MessageParser do
  @moduledoc """
  Parses and interpolates message templates with input data.

  Supports placeholders in the form `{{ expression }}`, where expressions
  can reference map keys, list indices, and simple Elixir code evaluated
  against the provided inputs map.
  """
  @doc """
  Parses a list of messages, interpolating placeholders with values from the inputs map.
  Supports nested map access, list indexing, and simple function calls.
  Handles both string and atom keys in the inputs map.
  """
  alias BeamMePrompty.Errors

  def parse(messages, inputs) do
    Enum.map(messages, fn
      %{role: role, content: message} ->
        {role, interpolate(message, inputs)}
    end)
  end

  defp interpolate(message, inputs) do
    Regex.replace(~r/{{\s*(.*?)\s*}}/, message, fn _, expression ->
      evaluate_expression(expression, inputs)
    end)
  end

  defp evaluate_expression(expression, inputs) do
    try do
      dbg(expression)
      dbg(inputs)
      {result, _} = Code.eval_string(expression, input: normalize_keys(inputs))
      to_string(result)
    rescue
      _ ->
        raise Errors.ParsingError.exception(
                module: __MODULE__,
                cause: "Failed to evaluate expression: #{expression}"
              )
    end
  end

  defp normalize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {key, value} when is_map(value) -> {to_atom(key), normalize_keys(value)}
      {key, value} -> {to_atom(key), value}
    end)
    |> Enum.into(%{})
  end

  defp to_atom(key) when is_binary(key), do: String.to_atom(key)
  defp to_atom(key), do: key
end
