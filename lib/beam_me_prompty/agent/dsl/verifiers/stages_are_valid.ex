defmodule BeamMePrompty.Agent.Dsl.Verifiers.StagesAreValid do
  @moduledoc """
  A Spark DSL verifier that ensures all stages in an agent configuration are valid.

  This verifier performs validation checks on each stage in the agent configuration.
  Currently, it verifies that:

  1. Each stage has at most one LLM configuration

  More validation rules can be added to this verifier as needed.
  """
  use Spark.Dsl.Verifier

  alias BeamMePrompty.Agent.Dsl.Info

  @doc """
  Verifies that all stages in the agent configuration are valid.

  Runs a series of validation checks on each stage and collects any errors.

  ## Parameters
    * `dsl_state` - The Spark DSL state to verify
    
  ## Returns
    * `:ok` - If all stages pass all validation checks
    * `{:error, errors}` - A list of errors if any validation checks fail
  """
  @impl Spark.Dsl.Verifier
  @spec verify(Spark.Dsl.t()) :: :ok | {:error, list()}
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

  @doc """
  Verifies that a stage has at most one LLM configuration.

  ## Parameters
    * `dsl_state` - The Spark DSL state
    * `stage` - The stage to verify
    
  ## Returns
    * `:ok` - If the stage has zero or one LLM configurations
    * Raises a `Spark.Error.DslError` - If the stage has multiple LLM configurations
  """
  @spec only_one_llm_config_allowed(Spark.Dsl.t(), map()) :: :ok | no_return()
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
