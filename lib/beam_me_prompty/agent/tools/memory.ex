defmodule BeamMePrompty.Agent.Tools.Memory do
  @moduledoc """
  Standard memory tools that can be used by LLMs to interact with agent memory.

  These tools provide a bridge between LLM tool calls and the agent's memory system,
  allowing stages to store and retrieve information across executions.
  """
  @moduledoc section: :memory_management

  alias BeamMePrompty.Agent.Tools.Memory.Delete
  alias BeamMePrompty.Agent.Tools.Memory.ListKeys
  alias BeamMePrompty.Agent.Tools.Memory.ListSources
  alias BeamMePrompty.Agent.Tools.Memory.Retrieve
  alias BeamMePrompty.Agent.Tools.Memory.Search
  alias BeamMePrompty.Agent.Tools.Memory.Store

  @doc """
  Returns all memory tools for use in agent stages.
  """
  def all do
    [
      ListSources,
      Store,
      Retrieve,
      Search,
      Delete,
      ListKeys
    ]
  end
end
