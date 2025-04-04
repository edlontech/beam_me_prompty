defmodule BeamMePrompty.Agent.ExecutorOptions do
  @moduledoc """
  Defines and validates configuration options for BeamMePrompty Agent executors.

  This module provides a schema for configuration options that control the behavior
  of agent executors, particularly around error handling, retry mechanisms, and
  backoff strategies.

  Use this module to validate executor configurations before applying them to ensure
  that all options are properly formatted and within acceptable ranges.
  """
  @moduledoc section: :agent_core_and_lifecycle

  @schema NimbleOptions.new!(
            name: [
              type: :atom,
              doc: """
              A unique identifier for the agent executor instance. Used for logging and monitoring.
              """
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
