defmodule BeamMePrompty.Tools.Memory.Retrieve do
  @moduledoc """
  Tool for retrieving information from agent memory.
  """
  @moduledoc section: :memory_management
  use BeamMePrompty.Tool,
    name: :memory_retrieve,
    description: """
    Retrieve previously stored information from the agent's memory. Useful for accessing context or facts that were stored during previous stages.
    """,
    parameters: %{
      type: "object",
      properties: %{
        key: %{
          type: "string",
          description: "The key of the memory item to retrieve"
        },
        memory_source: %{
          type: "string",
          description: "Name of the memory source to use (optional)"
        }
      },
      required: ["key"]
    }

  alias BeamMePrompty.Agent.MemoryManager

  @impl true
  def run(%{"key" => key} = params, context) do
    memory_manager = get_memory_manager(context)
    source = Map.get(params, "memory_source")

    opts = if source, do: [source: String.to_existing_atom(source)], else: []

    case MemoryManager.retrieve(memory_manager, key, opts) do
      {:ok, value} ->
        {:ok, %{found: true, key: key, value: value}}

      {:error, :not_found} ->
        {:ok, %{found: false, key: key, message: "No memory found for key: #{key}"}}

      {:error, reason} ->
        {:error, "Failed to retrieve memory: #{inspect(reason)}"}
    end
  end

  defp get_memory_manager(context) do
    context[:memory_manager] || raise "Memory manager not available in context"
  end
end
