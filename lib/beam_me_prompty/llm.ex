defmodule BeamMePrompty.LLM do
  @moduledoc """
  Defines the behaviour for Large Language Model (LLM) clients.

  Implementations of this behaviour provide standardized ways to interact
  with different LLM providers (e.g., OpenAI, Google Gemini, local models).
  """

  @type roles :: :system | :user | :assistant

  @typedoc "Represents a message in a conversation history."
  @type message :: binary() | {roles(), binary()}

  @typedoc "Represents the response from an LLM provider."
  @type response :: binary() | map()

  @typedoc "Options passed to the completion function."
  @type completion_opts :: keyword()

  @doc """
  Generates a completion based on the provided messages and options.

  Implementations should handle communication with the specific LLM provider,
  passing the messages and applying any relevant options (like temperature,
  max tokens, model selection within the provider, etc.).

  It should aim to return a structured map, potentially conforming to a
  schema if requested via options.
  """
  @callback completion(model :: String.t(), messages :: [message()], opts :: completion_opts()) ::
              {:ok, response} | {:error, any()}

  @doc """
  A convenience function to call the `completion/3` callback on a specific client module.
  """
  def completion(client_module, model, messages, opts \\ []) do
    client_module.completion(model, messages, opts)
  end
end
