defmodule BeamMePrompty.LLM.MessageParser do
  @moduledoc """
  Parses and interpolates message EEx templates with input data.
  """
  @moduledoc section: :llm_integration

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.Part
  alias BeamMePrompty.Agent.Dsl.TextPart

  @doc """
  Parses a list of messages, interpolating EEx placeholders with values from the inputs map.
  Supports nested map access and variable interpolation using EEx syntax (<%= variable %>).
  Handles both string and atom keys in the inputs map.
  """
  @spec parse([%{role: atom(), content: [Part.parts()]}], map()) ::
          [{atom(), [Part.parts()]}]
  def parse(messages, inputs) do
    Enum.map(messages, fn
      %{role: role, content: parts} ->
        {role, Enum.map(parts, &interpolate(&1, inputs))}
    end)
  end

  # sobelow_skip ["RCE.EEx"]
  defp interpolate(%TextPart{text: message} = message_part, inputs) do
    bindings = normalize_to_bindings(inputs)
    rendered_text = EEx.eval_string(message, bindings)

    %TextPart{
      message_part
      | text: rendered_text
    }
  end

  defp interpolate(message, _inputs), do: message

  defp normalize_to_bindings(struct) when is_struct(struct),
    do:
      struct
      |> Map.from_struct()
      |> normalize_to_bindings()

  defp normalize_to_bindings(map) when is_map(map) do
    map
    |> Enum.map(fn
      {key, value} when is_struct(value, TextPart) ->
        {to_atom(key), value.text}

      {key, value} when is_struct(value, DataPart) ->
        {to_atom(key), normalize_to_bindings(value.data)}

      {key, value} when is_map(value) ->
        {to_atom(key), normalize_to_bindings(value)}

      {key, value} when is_list(value) ->
        {to_atom(key), Enum.map(value, &normalize_to_bindings/1)}

      {key, value} when is_binary(value) ->
        {to_atom(key), value}

      {key, value} ->
        {to_atom(key), value}
    end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp normalize_to_bindings(value), do: value

  defp to_atom(key) when is_binary(key), do: String.to_existing_atom(key)

  defp to_atom(key), do: key
end
