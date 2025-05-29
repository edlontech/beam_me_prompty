defmodule BeamMePrompty.Agent.Dsl.Transformers.InjectMemoryTools do
  @moduledoc """
  A Spark DSL transformer that automatically injects memory tools into stages
  when memory sources are configured in the agent.

  This transformer runs during the DSL compilation phase and ensures that
  all LLM-enabled stages have access to memory tools without requiring
  manual configuration.
  """

  use Spark.Dsl.Transformer

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Tools.MemoryTools
  alias Spark.Dsl.Transformer

  @doc false
  def transform(dsl_state) do
    memory_sources = Transformer.get_entities(dsl_state, [:agent, :memory_source])

    if Enum.empty?(memory_sources) do
      # No memory sources configured, nothing to do
      {:ok, dsl_state}
    else
      # Get all stages and inject memory tools
      stages = Transformer.get_entities(dsl_state, [:agent, :stage])

      # Transform each stage
      Enum.reduce_while(stages, {:ok, dsl_state}, fn stage, {:ok, acc_state} ->
        case inject_memory_tools_into_stage(acc_state, stage) do
          {:ok, new_state} -> {:cont, {:ok, new_state}}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
    end
  end

  defp inject_memory_tools_into_stage(dsl_state, %Dsl.Stage{llm: nil} = _stage) do
    # No LLM configuration, nothing to do
    {:ok, dsl_state}
  end

  defp inject_memory_tools_into_stage(dsl_state, %Dsl.Stage{llm: llm_configs} = stage)
       when is_list(llm_configs) do
    # Multiple LLM configurations
    updated_llms = Enum.map(llm_configs, &add_memory_tools_to_llm/1)
    updated_stage = %{stage | llm: updated_llms}

    # Replace the stage in the DSL state
    replace_stage(dsl_state, stage.name, updated_stage)
  end

  defp inject_memory_tools_into_stage(dsl_state, %Dsl.Stage{llm: llm} = stage) do
    # Single LLM configuration
    updated_llm = add_memory_tools_to_llm(llm)
    updated_stage = %{stage | llm: [updated_llm]}

    # Replace the stage in the DSL state
    replace_stage(dsl_state, stage.name, updated_stage)
  end

  defp add_memory_tools_to_llm(%Dsl.LLM{tools: existing_tools} = llm) do
    # Get memory tool modules
    memory_tool_modules = MemoryTools.all()

    # Get existing tool names to avoid duplicates
    existing_tool_names =
      (existing_tools || [])
      |> Enum.map(&get_tool_name/1)
      |> Enum.filter(& &1)
      |> MapSet.new()

    # Filter out memory tools that are already present
    new_memory_tools =
      memory_tool_modules
      |> Enum.reject(fn tool_module ->
        MapSet.member?(existing_tool_names, tool_module.name())
      end)

    # Combine existing tools with new memory tools
    all_tools = (existing_tools || []) ++ new_memory_tools

    %{llm | tools: all_tools}
  end

  defp get_tool_name(tool) when is_atom(tool) do
    if function_exported?(tool, :name, 0) do
      tool.name()
    else
      nil
    end
  end

  defp get_tool_name(tool) when is_map(tool) do
    Map.get(tool, :name)
  end

  defp get_tool_name(_), do: nil

  defp replace_stage(dsl_state, stage_name, updated_stage) do
    # Remove the old stage
    dsl_state =
      Transformer.remove_entity(dsl_state, [:agent, :stage], fn stage ->
        stage.name == stage_name
      end)

    # Add the updated stage
    Transformer.add_entity(dsl_state, [:agent, :stage], updated_stage)
  end

  @doc false
  def after?(_), do: []

  @doc false
  def before?(_), do: [BeamMePrompty.Agent.Dsl.Transformers.BuildDag]
end
