defmodule BeamMePrompty.GeminiAgent do
  @moduledoc false
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

    stage :second_stage do
      llm "gemini-2.0-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_GOOGLE_AI_API_KEY") end
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
