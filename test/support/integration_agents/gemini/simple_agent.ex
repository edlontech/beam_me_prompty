defmodule BeamMePrompty.IntegrationAgents.Gemini.SimpleAgent do
  @moduledoc "Simple Gemini agent without memory, tools, or structured responses"
  use BeamMePrompty.Agent

  agent do
    stage :simple_response do
      llm "gemini-2.5-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_GOOGLE_AI_API_KEY") end
        end

        message :system, [text_part("You are a helpful assistant")]
        message :user, [text_part("Answer this question: <%= question %>")]
      end
    end
  end
end
