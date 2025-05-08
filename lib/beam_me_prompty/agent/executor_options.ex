defmodule BeamMePrompty.Agent.ExecutorOptions do
  @schema NimbleOptions.new!(
            name: [
              type: :string,
              doc: "Name for the agent executor"
            ],
            max_retries: [
              type: :non_neg_integer,
              default: 3
            ],
            backoff_initial: [
              type: :non_neg_integer,
              default: 1000
            ],
            backoff_factor: [
              type: :float,
              default: 2.0
            ],
            max_backoff: [
              type: :non_neg_integer,
              default: 30_000
            ]
          )

  @typedoc """
  #{NimbleOptions.docs(@schema)}  
  """
  @type t() :: [unquote(NimbleOptions.option_typespec(@schema))]

  alias BeamMePrompty.LLM.Errors.InvalidConfig

  def validate(config) do
    case NimbleOptions.validate(config, @schema) do
      {:ok, parsed_config} ->
        {:ok, parsed_config}

      {:error, error} ->
        {:error, InvalidConfig.exception(%{module: __MODULE__, cause: error.message})}
    end
  end
end
