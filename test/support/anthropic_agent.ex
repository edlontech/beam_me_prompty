defmodule BeamMePrompty.AnthropicAgent do
  @moduledoc false
  use BeamMePrompty.Agent

  alias BeamMePrompty.Agent.Dsl.TextPart

  agent do
    name "Anthropic Agent"

    stage :first_stage do
      llm "claude-3-5-haiku-20241022", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_ANTHROPIC_AI_API_KEY") end
        end

        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Tell me a Joke"}]
      end
    end

    stage :second_stage do
      llm "claude-3-5-haiku-20241022", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_ANTHROPIC_AI_API_KEY") end
        end

        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]

        message :user, [
          %TextPart{
            type: :text,
            text:
              "Call the sounds_of_the_fox tool with Vulpes Vulpes species name to understand the sounds of a fox."
          }
        ]

        tools [BeamMePrompty.WhatDoesTheFoxSayTool]
      end
    end
  end
end
