defmodule BeamMePrompty.Agent.Serialization do
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
  alias BeamMePrompty.Agent.Serialization.Deserializer
  alias BeamMePrompty.Agent.Serialization.Serializer

  @type serializable_agent :: %{
          agent: [Dsl.Stage.t()],
          memory: [Dsl.MemorySource.t()],
          opts: keyword()
        }

  defdelegate serialize(agent_definition), to: Serializer

  defdelegate deserialize(json_string), to: Deserializer

  @doc """
  Validates that a deserialized agent definition is valid.

  ## Parameters

  - `agent_definition` - The agent definition to validate

  ## Returns

  - `:ok` - Agent definition is valid
  - `{:error, reason}` - Validation failed
  """
  @spec validate(serializable_agent()) :: :ok | {:error, BeamMePrompty.Errors.ValidationError.t()}
  def validate(%{agent: stages, memory: memory_sources, opts: opts})
      when is_list(stages) and is_list(memory_sources) and is_list(opts) do
    with :ok <- validate_stages(stages),
         :ok <- validate_memory_sources(memory_sources) do
      :ok
    end
  end

  def validate(input) do
    {:error,
     BeamMePrompty.Errors.ValidationError.exception(
       cause: %{message: "Invalid agent structure", input: input}
     )}
  end

  defp validate_stages(stages) do
    stages
    |> Enum.all?(fn stage ->
      is_struct(stage, Dsl.Stage) and
        is_atom(stage.name) and
        (is_nil(stage.depends_on) or
           (is_list(stage.depends_on) and Enum.all?(stage.depends_on, &is_atom/1)))
    end)
    |> case do
      true ->
        :ok

      false ->
        {:error,
         BeamMePrompty.Errors.ValidationError.exception(
           cause: %{message: "Invalid stages structure", stages: stages}
         )}
    end
  end

  defp validate_memory_sources(memory_sources) do
    memory_sources
    |> Enum.all?(fn source ->
      is_struct(source, Dsl.MemorySource) and
        is_atom(source.name) and
        is_atom(source.module) and
        is_binary(source.description)
    end)
    |> case do
      true ->
        :ok

      false ->
        {:error,
         BeamMePrompty.Errors.ValidationError.exception(
           cause: %{message: "Invalid memory sources structure", sources: memory_sources}
         )}
    end
  end
end
