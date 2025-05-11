defmodule BeamMePrompty.GeminiAgent do
  use BeamMePrompty.Agent

  alias BeamMePrompty.Agent.Dsl.TextPart

  agent do
    stage :first_stage do
      llm "gemini-2.0-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_GOOGLE_AI_API_KEY") end
        end

        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Tell me a Joke"}]
      end
    end
  end
end
