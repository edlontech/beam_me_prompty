defmodule BeamMePrompty.Agent.MemoryToolInjector do
  @moduledoc """
  Automatically injects memory tools into agent stages when memory sources are configured.

  This module is responsible for:
  - Detecting when an agent has memory sources configured
  - Automatically adding memory tools to all stages that have LLM configurations
  - Ensuring memory tools don't conflict with user-defined tools
  """

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Tools.MemoryTools

  @doc """
  Injects memory tools into all LLM-enabled stages if memory sources are configured.

  Returns the updated agent configuration with memory tools added.
  """
  def inject_memory_tools(agent_config) do
    memory_sources = Spark.Dsl.Extension.get_entities(agent_config, :memory_source)

    if Enum.empty?(memory_sources) do
      # No memory sources configured, return unchanged
      agent_config
    else
      # Get all stages
      stages = Spark.Dsl.Extension.get_entities(agent_config, :stage)

      # Update stages with memory tools
      updated_stages = Enum.map(stages, &maybe_add_memory_tools_to_stage/1)

      # Replace stages in the config
      agent_config
      |> remove_all_stages()
      |> add_stages(updated_stages)
    end
  end

  defp maybe_add_memory_tools_to_stage(%Dsl.Stage{llm: nil} = stage) do
    # No LLM configuration, return unchanged
    stage
  end

  defp maybe_add_memory_tools_to_stage(%Dsl.Stage{llm: llm} = stage) when is_list(llm) do
    # Multiple LLM configurations
    updated_llms = Enum.map(llm, &add_memory_tools_to_llm/1)
    %{stage | llm: updated_llms}
  end

  defp maybe_add_memory_tools_to_stage(%Dsl.Stage{llm: llm} = stage) do
    # Single LLM configuration
    updated_llm = add_memory_tools_to_llm(llm)
    %{stage | llm: updated_llm}
  end

  defp add_memory_tools_to_llm(%Dsl.LLM{tools: existing_tools} = llm) do
    # Get memory tools
    memory_tools = MemoryTools.all()

    # Filter out any memory tools that might already exist (by name)
    existing_tool_names =
      Enum.map(existing_tools || [], fn tool ->
        cond do
          is_atom(tool) -> tool
          is_map(tool) && Map.has_key?(tool, :name) -> tool.name
          true -> nil
        end
      end)

    # Only add memory tools that aren't already present
    new_memory_tools =
      Enum.filter(memory_tools, fn tool_module ->
        tool_name = tool_module.name()
        tool_name not in existing_tool_names
      end)

    # Combine existing tools with new memory tools
    all_tools = (existing_tools || []) ++ new_memory_tools

    %{llm | tools: all_tools}
  end

  defp remove_all_stages(agent_config) do
    # Remove all existing stage entities from the agent section
    stages = Spark.Dsl.Extension.get_entities(agent_config, [:agent, :stage])

    Enum.reduce(stages, agent_config, fn stage, config ->
      Spark.Dsl.Transformer.remove_entity(config, [:agent, :stage], stage)
    end)
  end

  defp add_stages(agent_config, stages) do
    # Add all stages back to the agent section
    Enum.reduce(stages, agent_config, fn stage, config ->
      Spark.Dsl.Transformer.add_entity(config, [:agent, :stage], stage)
    end)
  end

  @doc """
  Checks if an agent has memory sources configured.
  """
  def has_memory_sources?(agent_config) do
    memory_sources = Spark.Dsl.Extension.get_entities(agent_config, :memory_source)
    not Enum.empty?(memory_sources)
  end

  @doc """
  Gets the default memory source name if one is configured.
  """
  def get_default_memory_source(agent_config) do
    memory_sources = Spark.Dsl.Extension.get_entities(agent_config, :memory_source)

    case Enum.find(memory_sources, & &1.default) do
      nil ->
        # If no default is set, use the first one
        case memory_sources do
          [first | _] -> first.name
          [] -> nil
        end

      default_source ->
        default_source.name
    end
  end
end
