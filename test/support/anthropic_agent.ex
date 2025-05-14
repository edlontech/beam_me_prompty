defmodule BeamMePrompty.AnthropicAgent do
  use BeamMePrompty.Agent

  alias BeamMePrompty.Agent.Dsl.TextPart

  agent do
    stage :first_stage do
      llm "claude-3-5-haiku-20241022", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_ANTHROPIC_AI_API_KEY") end
        end

        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Tell me a Joke"}]
      end
    end
  end

  agent do
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

        tool :sounds_of_the_fox do
          module BeamMePrompty.WhatDoesTheFoxSayTool
          description "A tool that returns the sounds of a fox."

          parameters %{
            type: :object,
            properties: %{
              fox_species: %{type: :string, description: "Fox species"}
            },
            required: [:fox_species]
          }
        end
      end
    end
  end
end
