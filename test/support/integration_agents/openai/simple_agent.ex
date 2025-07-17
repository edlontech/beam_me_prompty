defmodule BeamMePrompty.IntegrationAgents.OpenAI.SimpleAgent do
  @moduledoc "Simple OpenAI agent without memory, tools, or structured responses"
  use BeamMePrompty.Agent

  agent do
    stage :simple_response do
      llm "gpt-4o-mini", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_OPENAI_API_KEY") end
        end

        message :system, [text_part("You are a helpful assistant")]
        message :user, [text_part("Answer this question: <%= question %>")]
      end
    end
  end
end
