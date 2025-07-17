defmodule BeamMePrompty.LLM.AnthropicOpts do
  @moduledoc """
  Provides configuration options and validation for Anthropic's Claude API integration.

  This module defines and validates the configuration schema for interacting with 
  Anthropic's Large Language Models (LLMs). It ensures that all required parameters 
  are properly formatted and handles the transformation of BeamMePrompty's internal 
  configuration format to Anthropic's expected API parameters.

  The module supports all major Anthropic API parameters including:
  - Model selection
  - Inference parameters (temperature, top_k, top_p)
  - Token limits
  - API authentication
  - Claude's thinking feature
  - Function calling tools
  """
  @moduledoc section: :llm_integration

  @schema NimbleOptions.new!(
            max_tokens: [
              type: :non_neg_integer,
              default: 4096,
              doc: "Sets the maximum number of tokens to include in a candidate."
            ],
            temperature: [
              type: :float,
              doc: """
              Controls the randomness of the output. Use higher values for more creative responses, and lower values for more deterministic responses.
              """
            ],
            api_key: [
              type: :string,
              doc: "Anthropic API key."
            ],
            version: [
              type: :string,
              doc: "Anthropic API Version",
              default: "2023-06-01"
            ],
            top_k: [
              type: :float,
              doc: """
              Changes how the model selects tokens for output. A topK of 1 means the selected token is the most probable among all the tokens in the model's vocabulary, 
              while a topK of 3 means that the next token is selected from among the 3 most probable using the temperature. 
              Tokens are further filtered based on topP with the final token selected using temperature sampling.
              """
            ],
            top_p: [
              type: :float,
              doc: """
              Changes how the model selects tokens for output. Tokens are selected from the most to least probable until the sum of their probabilities equals the topP value."
              """
            ],
            thinking_budget: [
              type: :non_neg_integer,
              doc: """
              The amount of tokens reserved for thinking
              """
            ],
            model: [
              type: :string,
              doc: "Which model to use",
              default: "claude-3-7-sonnet-20250219"
            ],
            http_adapter: [
              type: :any,
              doc: "An HTTP client adapter to use for the request. Defaults to Req."
            ],
            tools: [
              type: :non_empty_keyword_list,
              keys: [
                function_declarations: [required: true, type: {:list, :any}]
              ]
            ]
          )

  @typedoc """
  #{NimbleOptions.docs(@schema)}  
  """
  @type t() :: [unquote(NimbleOptions.option_typespec(@schema))]

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.LLM.Errors.InvalidConfig
  alias BeamMePrompty.Tool

  @spec validate(String.t(), [Tool.t()], LLMParams.t()) ::
          {:ok, t()} | {:error, Splode.Error.t()}
  def validate(model, tools, config) do
    config =
      Keyword.reject(
        [
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          top_p: config.top_p,
          top_k: config.top_k,
          api_key: api_key(config.api_key),
          thinking_budget: config.thinking_budget,
          tools: parse_dsl_tools(tools),
          model: model
        ],
        fn {_, v} -> is_nil(v) end
      )

    case NimbleOptions.validate(config, @schema) do
      {:ok, parsed_config} ->
        {:ok, parsed_config}

      {:error, error} ->
        {:error, InvalidConfig.exception(module: __MODULE__, cause: error.message)}
    end
  end

  defp api_key(key) when is_binary(key), do: key

  defp api_key(func_key) when is_function(func_key) do
    case func_key.() do
      key when is_binary(key) -> key
      _ -> nil
    end
  end

  defp parse_dsl_tools(nil), do: nil

  defp parse_dsl_tools([]), do: nil

  defp parse_dsl_tools(tools) do
    [
      function_declarations:
        Enum.map(tools, fn tool ->
          %{
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters
          }
        end)
    ]
  end
end
