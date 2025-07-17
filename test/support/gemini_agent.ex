defmodule BeamMePrompty.GeminiAgent do
  @moduledoc false
  use BeamMePrompty.Agent

  agent do
    name "Gemini Agent"

    stage :first_stage do
      llm "gemini-2.0-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_GOOGLE_AI_API_KEY") end
        end

        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Tell me a Joke")]
      end
    end

    stage :second_stage do
      llm "gemini-2.0-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_GOOGLE_AI_API_KEY") end
        end

        message :system, [text_part("You are a helpful assistant.")]

        message :user, [
          text_part(
            "Call the sounds_of_the_fox tool with Vulpes Vulpes species name to understand the sounds of a fox."
          )
        ]

        tools [BeamMePrompty.WhatDoesTheFoxSayTool]
      end
    end
  end
end
