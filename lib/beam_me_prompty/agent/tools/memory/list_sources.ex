defmodule BeamMePrompty.Agent.Tools.Memory.ListSources do
  @moduledoc """
  Tool for listing available memory sources and their capabilities.
  """
  @moduledoc section: :memory_management
  use BeamMePrompty.Tool,
    name: :memory_list_sources,
    description: """
    This tool provides all the available memory sources for the Agent Memory, you **will** use it to understand how to
    use each memory source, how to query them, and what capabilities they have.
    """

  alias BeamMePrompty.Agent.MemoryManager
  alias BeamMePrompty.LLM.Errors

  @impl true
  def run(_params, context) do
    context
    |> get_memory_manager()
    |> MemoryManager.info()
    |> Jason.encode()
    |> then(fn
      {:ok, json} -> {:ok, json}
      {:error, err} -> {:error, Errors.ToolError.exception(module: __MODULE__, cause: err)}
    end)
  end

  defp get_memory_manager(context) do
    context[:memory_manager] ||
      raise Errors.ToolError.exception(
              module: __MODULE__,
              cause: "Memory manager not available in context"
            )
  end
end
