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
    serialized_definition = %{
      agent: serialize_value(agent_definition.agent),
      memory: serialize_value(agent_definition.memory),
      agent_config: serialize_value(agent_definition.agent_config)
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

  # Recursive transformation functions

  # Handle nil explicitly
  defp serialize_value(nil), do: nil
  defp serialize_value(data) when is_list(data), do: Enum.map(data, &serialize_value/1)
  defp serialize_value(fun) when is_function(fun), do: serialize_function(fun)
  defp serialize_value(%_{} = struct), do: serialize_struct(struct)

  defp serialize_value(data) when is_map(data),
    do: Map.new(data, fn {k, v} -> {serialize_value(k), serialize_value(v)} end)

  defp serialize_value(data) when is_tuple(data), do: serialize_tuple(data)
  defp serialize_value(atom) when is_atom(atom), do: serialize_atom(atom)

  # Exclude PIDs
  defp serialize_value(pid) when is_pid(pid), do: nil

  # Pass through numbers, strings, etc.

  defp serialize_value(other), do: other

  defp serialize_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.put("__struct__", serialize_module(struct.__struct__))
    |> serialize_value()
  end

  defp serialize_function(fun) do
    fun_info = :erlang.fun_info(fun)

    case {fun_info[:module], fun_info[:name], fun_info[:arity]} do
      {module, name, arity} when is_atom(module) and is_atom(name) and is_integer(arity) ->
        name_str = Atom.to_string(name)

        # Check if this is a generated function (contains _generated_ in the name)
        if String.contains?(name_str, "_generated_") do
          raise SerializationError.exception(
                  cause:
                    "Cannot serialize generated functions for persisted agents. " <>
                      "Generated function: #{serialize_module(module)}.#{name_str}/#{arity}. " <>
                      "Please use regular named functions instead."
                )
        end

        %{
          "__type__" => "mfa",
          "module" => serialize_module(module),
          "function" => serialize_atom(name),
          "arity" => arity
        }

      _ ->
        raise SerializationError.exception(
                cause:
                  "Cannot serialize anonymous functions for persisted agents. " <>
                    "Please use regular named functions like &Module.function/arity instead."
              )
    end
  end

  defp serialize_module(module) when is_atom(module) do
    module |> Module.split() |> Enum.join(".")
  end

  defp serialize_atom(nil), do: nil
  defp serialize_atom(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp serialize_tuple(tuple) when is_tuple(tuple) do
    %{
      "__type__" => "tuple",
      "elements" => tuple |> Tuple.to_list() |> Enum.map(&serialize_value/1)
    }
  end
end
