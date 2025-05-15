defmodule BeamMePrompty.Agent.Dsl.Verifiers.HasStages do
  @moduledoc """
  A Spark DSL verifier that ensures an agent has at least one stage defined.

  This verifier checks that the agent configuration contains at least one stage
  in its definition. If no stages are found, a DSL error is raised.
  """
  use Spark.Dsl.Verifier

  alias BeamMePrompty.Agent.Dsl.Info

  @doc """
  Verifies that the agent has at least one stage defined in the DSL state.

  ## Parameters
    * `dsl_state` - The Spark DSL state to verify
    
  ## Returns
    * `:ok` - If the agent has at least one stage
    * Raises a `Spark.Error.DslError` - If no stages are defined
  """
  @impl Spark.Dsl.Verifier
  @spec verify(Spark.Dsl.t()) :: :ok | no_return()
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
