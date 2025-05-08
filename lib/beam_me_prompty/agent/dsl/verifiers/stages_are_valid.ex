defmodule BeamMePrompty.Agent.Dsl.Verifiers.StagesAreValid do
  use Spark.Dsl.Verifier

  alias BeamMePrompty.Agent.Dsl.Info

  @impl Spark.Dsl.Verifier
  def verify(dsl_state) do
    stages = Info.agent(dsl_state)

    all_errors =
      Enum.flat_map(stages, fn stage ->
        results = [
          only_one_llm_config_allowed(dsl_state, stage)
        ]

        Enum.filter(results, fn result -> result != :ok end)
      end)

    if Enum.empty?(all_errors) do
      :ok
    else
      {:error, all_errors}
    end
  end

  def only_one_llm_config_allowed(dsl_state, stage) do
    case stage.llm do
      [_llm] ->
        :ok

      [] ->
        :ok

      _ ->
        Spark.Error.DslError.exception(
          message: "Only one LLM config is allowed per stage",
          path: [:agent, :stage, stage.name],
          module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
        )
    end
  end
end
