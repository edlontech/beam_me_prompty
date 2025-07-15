defmodule BeamMePrompty.Agent.Dsl.Transformers.InjectMemoryTools do
  @moduledoc """
  A Spark DSL transformer that automatically injects memory tools into stages
  when memory sources are configured in the agent.

  This transformer runs during the DSL compilation phase and ensures that
  all LLM-enabled stages have access to memory tools without requiring
  manual configuration.
  """
  @moduledoc section: :dsl

  use Spark.Dsl.Transformer

  alias BeamMePrompty.Agent.Tools.Memory, as: MemoryTools
  alias Spark.Dsl.Transformer

  @doc false
  def transform(dsl_state) do
    memory_sources = Transformer.get_entities(dsl_state, [:memory])

    if Enum.empty?(memory_sources) do
      {:ok, dsl_state}
    else
      stages = Transformer.get_entities(dsl_state, [:agent])

      updated_stages =
        Enum.map(stages, fn stage ->
          [llm | _] = stage.llm
          updated_tools = llm.tools ++ MemoryTools.all()
          llm = put_in(llm.tools, updated_tools)
          put_in(stage.llm, [llm])
        end)

      updated_dsl_state =
        Enum.reduce(updated_stages, dsl_state, fn stage, acc ->
          Transformer.replace_entity(acc, [:agent], stage, fn curr_stage ->
            curr_stage.name == stage.name
          end)
        end)

      {:ok, updated_dsl_state}
    end
  end
end
