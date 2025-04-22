defmodule BeamMePrompty.LLM.AnthropicOpts do
  @schema NimbleOptions.new!(
            max_output_tokens: [
              type: :non_neg_integer,
              doc: "Sets the maximum number of tokens to include in a candidate."
            ],
            temperature: [
              type: :float,
              doc: """
              Controls the randomness of the output. Use higher values for more creative responses, and lower values for more deterministic responses.
              """
            ],
            key: [
              type: :string,
              doc: "Anthropic API key."
            ],
            version: [
              type: :string,
              doc: "Anthropic API Version",
              default: "2023-06-01"
            ],
            top_p: [
              type: :float,
              doc: """
              Changes how the model selects tokens for output. Tokens are selected from the most to least probable until the sum of their probabilities equals the topP value."
              """
            ],
            top_k: [
              type: :float,
              doc: """
              Changes how the model selects tokens for output. A topK of 1 means the selected token is the most probable among all the tokens in the model's vocabulary, 
              while a topK of 3 means that the next token is selected from among the 3 most probable using the temperature. 
              Tokens are further filtered based on topP with the final token selected using temperature sampling.
              """
            ],
            thinking: [
              type: :boolean,
              doc: """
              When enabled, responses include thinking content blocks showing Claude's thinking process before the final answer. Requires a minimum budget of 1,024 tokens and counts towards your max_tokens limit.
              """
            ],
            thinking_budget_tokens: [
              type: :non_neg_integer,
              default: 1024,
              doc: """
              The amount of tokens reserved for thinking
              """
            ],
            model: [
              type: :string,
              doc: "Which model to use",
              default: "claude-3-7-sonnet-20250219"
            ],
            plug: [
              type: {:tuple, [:atom, :atom]},
              doc: "Plugins to use for the request. This is useful for testing."
            ]
          )

  @typedoc """
  #{NimbleOptions.docs(@schema)}  
  """
  @type t() :: [unquote(NimbleOptions.option_typespec(@schema))]

  alias BeamMePrompty.LLM.Errors.InvalidConfig

  @doc """
  Validates the given configuration options and returns the parsed configuration.
  """
  def validate(config) do
    case NimbleOptions.validate(config, @schema) do
      {:ok, parsed_config} ->
        {:ok, parsed_config}

      {:error, error} ->
        {:error, InvalidConfig.exception(%{module: __MODULE__, cause: error.message})}
    end
  end
end
