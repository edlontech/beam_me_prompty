defmodule BeamMePrompty.Tools.Memory.Search do
  @moduledoc """
  Tool for searching through agent memory.
  """
  @moduledoc section: :memory_management
  use BeamMePrompty.Tool,
    name: :memory_search,
    description: """
    Search through the agent's memory using queries. The query format depends on the memory backend.
    """,
    parameters: %{
      type: "object",
      properties: %{
        query: %{
          type: "object",
          description: "Search query (format depends on memory backend)"
        },
        limit: %{
          type: "integer",
          description: "Maximum number of results to return",
          default: 10
        },
        memory_source: %{
          type: "string",
          description: "Name of the memory source to search (optional)"
        }
      },
      required: ["query"]
    }

  alias BeamMePrompty.Agent.MemoryManager

  @impl true
  def run(%{"query" => query} = params, context) do
    memory_manager = get_memory_manager(context)
    limit = Map.get(params, "limit", 10)
    source = Map.get(params, "memory_source")

    opts = [limit: limit]
    opts = if source, do: [{:source, String.to_existing_atom(source)} | opts], else: opts

    case MemoryManager.search(memory_manager, query, opts) do
      {:ok, results} ->
        {:ok,
         %{
           found: length(results),
           results: results
         }}

      {:error, reason} ->
        {:error, "Failed to search memory: #{inspect(reason)}"}
    end
  end

  defp get_memory_manager(context) do
    context[:memory_manager] || raise "Memory manager not available in context"
  end
end
