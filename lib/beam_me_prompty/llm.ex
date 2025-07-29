defmodule BeamMePrompty.LLM do
  @moduledoc """
  Defines the behaviour for Large Language Model (LLM) clients.

  Implementations of this behaviour provide standardized ways to interact
  with different LLM providers (e.g., OpenAI, Google Gemini, local models).
  """
  @moduledoc section: :llm_integration

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.Agent.Dsl.Part
  alias BeamMePrompty.Tool

  @type roles :: :system | :user | :assistant

  @typedoc "Represents a message in a conversation history."
  @type message :: {roles(), [Part.parts()]}

  @typedoc "Represents the response from an LLM provider."
  @type response :: [Part.parts()]

  @typedoc "Options passed to the completion function."
  @type completion_opts :: LLMParams.t()

  @typedoc "Request from the LLM to execute a function."
  @type function_call_request :: %{
          function_call: %{
            optional(:id) => String.t(),
            optional(:name) => String.t(),
            optional(:arguments) => map()
          }
        }

  @doc """
  Generates a completion based on the provided messages and options.

  Implementations should handle communication with the specific LLM provider,
  passing the messages and applying any relevant options (like temperature,
  max tokens, model selection within the provider, etc.).

  It should aim to return a structured map, potentially conforming to a
  schema if requested via options.
  """
  @callback completion(
              model :: String.t(),
              messages :: [message()],
              llm_params :: completion_opts(),
              tools :: [Tool.t()],
              opts :: keyword()
            ) ::
              {:ok, response} | {:error, any()}

  @doc """
  Retrieves a list of available models from the LLM provider.
  """
  @callback available_models(opts :: keyword()) :: {:ok, [String.t()]} | {:error, any()}

  @doc """
  A convenience function to call the `completion/4` callback on a specific client module.
  """
  def completion(client_module, model, messages, llm_params, tools \\ [], opts \\ []),
    do: client_module.completion(model, messages, llm_params, tools, opts)

  def available_models(client_module, opts \\ []), do: client_module.available_models(opts)
end
