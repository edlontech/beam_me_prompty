defmodule BeamMePrompty.Agent.Dsl.Verifiers.HasStages do
  use Spark.Dsl.Verifier

  alias BeamMePrompty.Agent.Dsl.Info

  @impl Spark.Dsl.Verifier
  def verify(dsl_state) do
    case Info.agent(dsl_state) do
      [_ | _] ->
        :ok

      _ ->
        Spark.Error.DslError.exception(
          message: "At least one stage is required",
          path: [:agent],
          module: Spark.Dsl.Verifier.get_persisted(dsl_state, :module)
        )
    end
  end
end
