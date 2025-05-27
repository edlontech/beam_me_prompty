defmodule BeamMePrompty.Agent.ExecutorOptions do
  @moduledoc """
  Defines and validates configuration options for BeamMePrompty Agent executors.

  This module provides a schema for configuration options that control the behavior
  of agent executors, particularly around error handling, retry mechanisms, and
  backoff strategies.

  Use this module to validate executor configurations before applying them to ensure
  that all options are properly formatted and within acceptable ranges.
  """

  @schema NimbleOptions.new!(
            name: [
              type: :string,
              doc:
                "A unique identifier for the agent executor instance. Used for logging and monitoring."
            ],
            max_retries: [
              type: :non_neg_integer,
              default: 3,
              doc: "Maximum number of retry attempts for failed operations before giving up."
            ],
            backoff_initial: [
              type: :non_neg_integer,
              default: 1000,
              doc: "Initial backoff period in milliseconds before the first retry attempt."
            ],
            backoff_factor: [
              type: :float,
              default: 2.0,
              doc: "Multiplicative factor by which the backoff period increases after each retry."
            ],
            max_backoff: [
              type: :non_neg_integer,
              default: 30_000,
              doc: "Maximum backoff period in milliseconds, regardless of the number of retries."
            ]
          )

  @typedoc """
  #{NimbleOptions.docs(@schema)}  
  """
  @type t() :: [unquote(NimbleOptions.option_typespec(@schema))]

  alias BeamMePrompty.LLM.Errors.InvalidConfig

  @doc false
  def validate(config) do
    case NimbleOptions.validate(config, @schema) do
      {:ok, parsed_config} ->
        {:ok, parsed_config}

      {:error, error} ->
        {:error, InvalidConfig.exception(module: __MODULE__, cause: error.message)}
    end
  end
end
