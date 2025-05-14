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

  alias BeamMePrompty.LLM.Errors.InvalidConfig
  alias BeamMePrompty.Agent.Dsl.{LLMParams, Tool}

  @spec validate(String.t(), Tool.t(), LLMParams.t()) ::
          {:ok, t()} | {:error, InvalidConfig.t()}
  def validate(model, tools, config) do
    config =
      [
        max_output_tokens: config.max_tokens,
        temperature: config.temperature,
        top_p: config.top_p,
        top_k: config.top_k,
        key: api_key(config.api_key),
        response_schema: config.structured_response,
        thinking_budget: config.thinking_budget,
        tools: parse_dsl_tools(tools),
        model: model
      ]
      |> Keyword.reject(fn {_, v} -> is_nil(v) end)

    case NimbleOptions.validate(config, @schema) do
      {:ok, parsed_config} ->
        {:ok, parsed_config}

      {:error, error} ->
        {:error, InvalidConfig.exception(%{module: __MODULE__, cause: error.message})}
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
