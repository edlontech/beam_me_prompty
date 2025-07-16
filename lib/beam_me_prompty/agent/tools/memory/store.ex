defmodule BeamMePrompty.Agent.Tools.Memory.Store do
  @moduledoc """
  Tool for storing information in agent memory.
  """
  @moduledoc section: :memory_management
  use BeamMePrompty.Tool,
    name: :memory_store,
    description: """
    Store information in the agent's memory for later retrieval. Useful for remembering facts, context, or intermediate results.
    """,
    parameters: %{
      type: "object",
      properties: %{
        key: %{
          type: "string",
          description: "Unique identifier for the memory item"
        },
        value: %{
          type: "object",
          description: "The information to store"
        },
        metadata: %{
          type: "object",
          description: "Optional metadata about the stored item",
          properties: %{
            tags: %{
              type: "array",
              items: %{type: "string"},
              description: "Tags for categorizing the memory"
            },
            ttl: %{
              type: "integer",
              description: "Time to live in seconds (optional)"
            },
            source: %{
              type: "string",
              description: "Source of the information"
            }
          }
        },
        memory_source: %{
          type: "string",
          description:
            "Name of the memory source to use, you should use the :memory_list_sources tool to see which sources are available and how to use them."
        }
      },
      required: ["key", "value"]
    }

  alias BeamMePrompty.Agent.MemoryManager

  @impl true
  def run(%{"key" => key, "value" => value} = params, context) do
    memory_manager = get_memory_manager(context)
    metadata = Map.get(params, "metadata", %{})
    source = Map.get(params, "memory_source")

    opts = build_opts(metadata, source)

    case MemoryManager.store(memory_manager, key, value, opts) do
      {:ok, result} ->
        {:ok,
         %{
           status: "stored",
           key: key,
           metadata: result[:metadata] || metadata
         }}

      {:error, reason} ->
        {:error, "Failed to store memory: #{inspect(reason)}"}
    end
  end

  defp get_memory_manager(context) do
    context[:memory_manager] || raise "Memory manager not available in context"
  end

  defp build_opts(metadata, source) do
    opts = []
    opts = if source, do: [{:source, String.to_existing_atom(source)} | opts], else: opts
    opts = if metadata[:ttl], do: [{:ttl, metadata[:ttl] * 1000} | opts], else: opts
    opts = if metadata[:tags], do: [{:metadata, %{tags: metadata[:tags]}} | opts], else: opts
    opts
  end
end
