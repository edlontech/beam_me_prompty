defmodule BeamMePrompty.LLM.OpenAIOpts do
  @moduledoc """
  Defines and validates configuration options for the OpenAI LLM adapter.
  Uses NimbleOptions to enforce required parameters (e.g., API key, model) and
  acceptable types for generation settings like temperature, top_p, and max_tokens.
  """
  @moduledoc section: :llm_integration

  @schema NimbleOptions.new!(
            max_tokens: [
              type: :non_neg_integer,
              doc: "The maximum number of tokens that can be generated in the chat completion."
            ],
            temperature: [
              type: :float,
              doc: """
              What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic.
              """
            ],
            top_p: [
              type: :float,
              doc: """
              An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top_p probability mass.
              """
            ],
            frequency_penalty: [
              type: :float,
              doc: """
              Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far.
              """
            ],
            presence_penalty: [
              type: :float,
              doc: """
              Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far.
              """
            ],
            key: [
              type: :string,
              doc: "OpenAI API key."
            ],
            model: [
              type: :string,
              doc: "Which model to use",
              default: "gpt-4o"
            ],
            response_format: [
              type: :map,
              doc: """
              An object specifying the format that the model must output. Compatible with GPT-4o, GPT-4o mini, GPT-4 Turbo and all GPT-3.5 Turbo models newer than gpt-3.5-turbo-1106.
              """
            ],
            seed: [
              type: :integer,
              doc: """
              This feature is in Beta. If specified, our system will make a best effort to sample deterministically.
              """
            ],
            http_adapter: [
              type: :any,
              doc: "An HTTP client adapter to use for the request. Defaults to Req."
            ],
            tools: [
              type: {:list, :map},
              doc:
                "A list of tools the model may call. Currently, only functions are supported as a tool."
            ],
            tool_choice: [
              type: {:or, [:string, :map]},
              doc: """
              Controls which (if any) tool is called by the model. Can be 'none', 'auto', 'required', or a specific tool choice object.
              """
            ]
          )

  @typedoc """
  #{NimbleOptions.docs(@schema)}  
  """
  @type t() :: [unquote(NimbleOptions.option_typespec(@schema))]

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.LLM.Errors.InvalidConfig
  alias BeamMePrompty.Tool

  @doc """
  Validates the configuration for the OpenAI LLM adapter.
  """
  @spec validate(String.t(), [Tool.t()], LLMParams.t()) ::
          {:ok, t()} | {:error, Splode.Error.t()}
  def validate(model, tools, config) do
    config =
      Keyword.reject(
        [
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          top_p: config.top_p,
          frequency_penalty: config.frequency_penalty,
          presence_penalty: config.presence_penalty,
          key: api_key(config.api_key),
          response_format: format_response_schema(config.structured_response),
          seed: get_in(config.other_params, [:seed]),
          tools: parse_dsl_tools(tools),
          tool_choice: get_in(config.other_params, [:tool_choice]),
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

  defp format_response_schema(nil), do: nil

  defp format_response_schema(schema) when is_map(schema) do
    %{
      type: "json_schema",
      json_schema: %{
        name: "response_schema",
        schema: schema,
        strict: true
      }
    }
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
    Enum.map(tools, fn tool ->
      %{
        type: "function",
        function: %{
          name: tool.name,
          description: tool.description,
          parameters: tool.parameters
        }
      }
    end)
  end
end
