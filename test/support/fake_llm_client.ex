defmodule BeamMePrompty.FakeLlmClient do
  @moduledoc false

  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Agent.Dsl.Part

  @impl true
  def completion(_model, _messages, _llm_params, _tools, _opts) do
    {:ok, [Part.text_part("bonk bonk")]}
  end
end
