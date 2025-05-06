defmodule BeamMePrompty do
  @moduledoc """
  Main entrypoint for executing defined BeamMePrompty agents.
  Provides the `execute/3` function to orchestrate multi-stage LLM prompts,
  handling input/output validation, dependency resolution, and customizable
  LLM clients and executors.
  """

  alias BeamMePrompty.DAG
  alias BeamMePrompty.Errors

  def execute_agent(agent, input, opts \\ []) do
    executor = Keyword.get(opts, :executor)
    override_llm = Keyword.get(opts, :llm_client)
    dag = DAG.build(agent.stages)

    case DAG.validate(dag) do
      {:error, reason} ->
        {:error, Errors.to_class(reason)}

      {:ok, dag} ->
        initial_context = %{
          global_input: input,
          llm_client: override_llm
        }
    end
  end
end
