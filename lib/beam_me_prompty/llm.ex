defmodule BeamMePrompty.LLM do
  @moduledoc """
  Defines the behaviour for Large Language Model (LLM) clients.

  Implementations of this behaviour provide standardized ways to interact
  with different LLM providers (e.g., OpenAI, Google Gemini, local models).
  """

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.Agent.Dsl.Part
  alias BeamMePrompty.Tool

  @type roles :: :system | :user | :assistant

  @typedoc "Represents a message in a conversation history."
  @type message :: {roles(), [Part.parts()]}

  @typedoc "Represents the response from an LLM provider."
  @type response :: binary() | function_call_request() | map()

  @typedoc "Options passed to the completion function."
  @type completion_opts :: LLMParams.t() | keyword()

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
              tools :: [Tool.t()],
              opts :: completion_opts()
            ) ::
              {:ok, response} | {:error, any()}

  @doc """
  A convenience function to call the `completion/4` callback on a specific client module.
  """
  def completion(client_module, model, messages, tools \\ [], opts \\ []),
    do: client_module.completion(model, messages, tools, opts)
end
