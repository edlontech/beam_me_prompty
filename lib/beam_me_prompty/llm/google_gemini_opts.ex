defmodule BeamMePrompty.LLM.GoogleGeminiOpts do
  @moduledoc """
  Defines and validates configuration options for the Google Gemini LLM adapter.
  Uses NimbleOptions to enforce required parameters (e.g., API key, model) and
  acceptable types for generation settings like temperature, top_k, and top_p.
  """
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
            key: [
              type: :string,
              doc: "Gemini API key."
            ],
            model: [
              type: :string,
              doc: "Which model to use",
              default: "gemini-2.0-flash"
            ],
            response_schema: [
              type: :map,
              doc: """
              OpenAPI 3.0 schema for the response, if filled, will enable the structured response feature
              """
            ],
            thinking_budget: [
              type: :non_neg_integer,
              doc: """
              The maximum number of tokens to use for the thinking budget. Minimum of 1024 tokens.
              """
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
