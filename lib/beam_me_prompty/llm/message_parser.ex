defmodule BeamMePrompty.LLM.MessageParser do
  @moduledoc """
  Parses and interpolates message mustache templates with input data.
  """
  alias BeamMePrompty.Agent.Dsl.TextPart

  @doc """
  Parses a list of messages, interpolating placeholders with values from the inputs map.
  Supports nested map access, list indexing, and simple function calls.
  Handles both string and atom keys in the inputs map.
  """
  def parse(messages, inputs) do
    Enum.map(messages, fn
      %{role: role, content: parts} ->
        {role, Enum.map(parts, &interpolate(&1, inputs))}
    end)
  end

  defp interpolate(%TextPart{text: message} = message_part, inputs) do
    rendered_text = Mustache.render(message, normalize_keys(inputs))

    %TextPart{
      message_part
      | text: rendered_text
    }
  end

  defp interpolate(message, _inputs), do: message

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
