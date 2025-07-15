defmodule BeamMePrompty.Agent.Tools.Memory.ListKeys do
  @moduledoc """
  Tool for listing available memory keys.
  """
  @moduledoc section: :memory_management
  use BeamMePrompty.Tool,
    name: :memory_list_keys,
    description: """
    List all available keys in the agent's memory. Useful for understanding what information is stored.
    """,
    parameters_schema: %{
      type: "object",
      properties: %{
        pattern: %{
          type: "string",
          description: "Optional pattern to filter keys"
        },
        limit: %{
          type: "integer",
          description: "Maximum number of keys to return",
          default: 100
        },
        memory_source: %{
          type: "string",
          description: "Name of the memory source to list from (optional)"
        }
      }
    }

  alias BeamMePrompty.Agent.MemoryManager

  @impl true
  def run(params, context) do
    memory_manager = get_memory_manager(context)
    pattern = Map.get(params, "pattern")
    limit = Map.get(params, "limit", 100)
    source = Map.get(params, "memory_source")

    opts = [limit: limit]
    opts = if pattern, do: [{:pattern, pattern} | opts], else: opts
    opts = if source, do: [{:source, String.to_existing_atom(source)} | opts], else: opts

    case MemoryManager.list_keys(memory_manager, opts) do
      {:ok, keys} ->
        {:ok,
         %{
           count: length(keys),
           keys: keys
         }}

      {:error, reason} ->
        {:error, "Failed to list memory keys: #{inspect(reason)}"}
    end
  end

  defp get_memory_manager(context) do
    context[:memory_manager] || raise "Memory manager not available in context"
  end
end
