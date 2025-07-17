defmodule BeamMePrompty.IntegrationAgents.Gemini.AgentWithStructuredResponse do
  @moduledoc "Gemini agent with structured response but without memory or tools"
  use BeamMePrompty.Agent

  agent do
    stage :structured_analysis do
      llm "gemini-2.5-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_GOOGLE_AI_API_KEY") end

          structured_response %OpenApiSpex.Schema{
            type: :object,
            properties: %{
              analysis: %OpenApiSpex.Schema{
                type: :string,
                description: "The analysis result"
              },
              confidence: %OpenApiSpex.Schema{
                type: :number,
                description: "Confidence score between 0 and 1"
              },
              recommendations: %OpenApiSpex.Schema{
                type: :array,
                items: %{type: :string},
                description: "List of recommendations"
              }
            },
            required: [:analysis, :confidence, :recommendations]
          }
        end

        message :system, [text_part("You are an analyst that provides structured JSON responses")]

        message :user, [
          text_part("Analyze this topic and provide structured output: <%= topic %>")
        ]
      end
    end
  end
end
