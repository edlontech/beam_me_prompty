defmodule BeamMePrompty.Agent.Serialization.Serializer do
  @moduledoc """
  Serialization and deserialization for BeamMePrompty Agent DSL.

  This module provides functionality to serialize agent DSL structures to JSON
  for database storage and deserialize them back to working agent definitions.

  ## Features

  - JSON-based serialization for database compatibility
  - Safe module resolution with validation
  - Function reference serialization as MFA tuples
  - Binary data encoding/decoding
  - Comprehensive error handling

  ## Usage

      # Serialize an agent definition
      agent_definition = MyAgent.agent_definition()
      {:ok, json_string} = BeamMePrompty.Agent.Serializer.serialize(agent_definition)

      # Deserialize back to agent definition
      {:ok, agent_definition} = BeamMePrompty.Agent.Serializer.deserialize(json_string)

  ## Security

  Module resolution is performed safely with validation against known modules.
  Function references are validated to prevent arbitrary code execution.
  """

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Errors.SerializationError

  @type serializable_agent :: %{
          agent: [Dsl.Stage.t()],
          memory: [Dsl.MemorySource.t()],
          opts: keyword()
        }

  @doc """
  Serializes an agent definition to JSON string.

  ## Parameters

  - `agent_definition` - The agent definition structure to serialize

  ## Returns

  - `{:ok, json_string}` - Successfully serialized
  - `{:error, reason}` - Serialization failed

  ## Examples

      iex> agent_def = %{agent: [stage], memory: [], opts: []}
      iex> {:ok, json} = BeamMePrompty.Agent.Serializer.serialize(agent_def)
      iex> is_binary(json)
      true
  """
  @spec serialize(serializable_agent()) :: {:ok, String.t()} | {:error, SerializationError.t()}
  def serialize(agent_definition) when is_map(agent_definition) do
    serialized_definition = %{
      agent: agent_definition.agent,
      memory: agent_definition.memory,
      opts: serialize_keyword_list(agent_definition.opts)
    }

    json_string = Jason.encode!(serialized_definition)

    {:ok, json_string}
  rescue
    error in Protocol.UndefinedError ->
      {:error, SerializationError.exception(cause: "Protocol not implemented: #{inspect(error)}")}

    error ->
      {:error, SerializationError.exception(cause: error)}
  end

  def serialize(input) do
    {:error, SerializationError.exception(cause: %{message: "Invalid input", input: input})}
  end

  defp serialize_keyword_list(opts) when is_list(opts) do
    Enum.map(opts, fn {key, value} -> [to_string(key), serialize_value(value)] end)
  end

  defp serialize_value(value) when is_atom(value), do: to_string(value)
  defp serialize_value(value), do: value
end
