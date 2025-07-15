defmodule BeamMePrompty.Agent.Tools.Memory.Delete do
  @moduledoc """
  Tool for deleting information from agent memory.
  """
  @moduledoc section: :memory_management
  use BeamMePrompty.Tool,
    name: :memory_delete,
    description: """
    Delete information from the agent's memory. Useful for removing outdated or incorrect facts.
    """,
    parameters: %{
      type: "object",
      properties: %{
        key: %{
          type: "string",
          description: "The key of the memory item to delete"
        },
        memory_source: %{
          type: "string",
          description: "Name of the memory source to use (optional)"
        }
      },
      required: ["key"]
    }

  @impl true
  def run(%{"key" => key} = params, context) do
    memory_manager = get_memory_manager(context)
    source = Map.get(params, "memory_source")

    opts = if source, do: [source: String.to_existing_atom(source)], else: []

    case BeamMePrompty.Agent.MemoryManager.delete(memory_manager, key, opts) do
      :ok ->
        {:ok, %{status: "deleted", key: key}}

      {:error, reason} ->
        {:error, "Failed to delete memory: #{inspect(reason)}"}
    end
  end

  defp get_memory_manager(context) do
    context[:memory_manager] || raise "Memory manager not available in context"
  end
end
