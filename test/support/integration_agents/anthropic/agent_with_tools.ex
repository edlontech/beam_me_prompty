defmodule BeamMePrompty.IntegrationAgents.Anthropic.AgentWithTools do
  @moduledoc "Anthropic agent with tools but without memory or structured responses"
  use BeamMePrompty.Agent

  alias BeamMePrompty.TestTools.Calculator
  alias BeamMePrompty.TestTools.Weather

  agent do
    name "Anthropic Agent with Tools"

    stage :calculate do
      llm "claude-3-5-haiku-20241022", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_ANTHROPIC_AI_API_KEY") end
        end

        message :system, [
          text_part("You are a helpful assistant with access to calculation and weather tools")
        ]

        message :user, [text_part("Calculate: <%= expression %>")]

        tools [Calculator, Weather]
      end
    end

    stage :weather_check do
      depends_on [:calculate]

      llm "claude-3-5-haiku-20241022", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_ANTHROPIC_AI_API_KEY") end
        end

        message :system, [
          text_part("You are a helpful assistant with access to weather information")
        ]

        message :user, [text_part("What's the weather like in <%= location %>?")]

        tools [Weather]
      end
    end
  end
end
