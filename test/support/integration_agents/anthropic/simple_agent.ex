defmodule BeamMePrompty.IntegrationAgents.Anthropic.SimpleAgent do
  @moduledoc "Simple Anthropic agent without memory, tools, or structured responses"
  use BeamMePrompty.Agent

  agent do
    stage :simple_response do
      llm "claude-3-5-haiku-20241022", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_ANTHROPIC_AI_API_KEY") end
        end

        message :system, [text_part("You are a helpful assistant")]
        message :user, [text_part("Answer this question: <%= question %>")]
      end
    end
  end
end

