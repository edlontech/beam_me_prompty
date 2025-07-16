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
  - Recursive transformation of complex Elixir structures

  ## Usage

      # Serialize an agent definition
      agent_definition = %{
        agent: MyAgent.stages(),
        memory: MyAgent.memory_sources(),
        agent_config: MyAgent.agent_config()
      }
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
          agent_config: map()
        }

  @doc """
  Serializes an agent definition to JSON string.

  ## Parameters

  - `agent_definition` - The agent definition structure to serialize

  ## Returns

  - `{:ok, json_string}` - Successfully serialized
  - `{:error, reason}` - Serialization failed

  ## Examples

      iex> agent_def = %{agent: [stage], memory: [], agent_config: %{}}
      iex> {:ok, json} = BeamMePrompty.Agent.Serializer.serialize(agent_def)
      iex> is_binary(json)
      true
  """
  @spec serialize(serializable_agent()) :: {:ok, String.t()} | {:error, SerializationError.t()}
  def serialize(agent_definition) when is_map(agent_definition) do
    json_string = Jason.encode!(agent_definition)

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
end
