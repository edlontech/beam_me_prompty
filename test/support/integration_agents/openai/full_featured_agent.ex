defmodule BeamMePrompty.IntegrationAgents.OpenAI.FullFeaturedAgent do
  @moduledoc "OpenAI agent with memory, tools, and structured responses"
  use BeamMePrompty.Agent

  alias BeamMePrompty.TestTools.Calculator
  alias BeamMePrompty.TestTools.DataProcessor
  alias BeamMePrompty.TestTools.Weather

  memory do
    memory_source :short_term, BeamMePrompty.Agent.Memory.ETS,
      description: "Short-term memory storage for full-featured OpenAI agent",
      opts: [
        table: :openai_full_agent_memory
      ],
      default: true
  end

  agent do
    name "OpenAI Full Featured Agent"

    stage :collect_data do
      llm "gpt-4o-mini", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_OPENAI_API_KEY") end
        end

        message :system, [
          text_part("You are a data collector that gathers information and stores it in memory")
        ]

        message :user, [text_part("Collect and store information about: <%= topic %>")]

        tools [Calculator, Weather]
      end
    end

    stage :analyze_data do
      depends_on [:collect_data]

      llm "gpt-4o-mini", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_OPENAI_API_KEY") end

          structured_response %OpenApiSpex.Schema{
            type: :object,
            properties: %{
              summary: %OpenApiSpex.Schema{
                type: :string,
                description: "Summary of the analysis"
              },
              key_findings: %OpenApiSpex.Schema{
                type: :array,
                items: %{type: :string},
                description: "Key findings from the analysis"
              },
              confidence_score: %OpenApiSpex.Schema{
                type: :number,
                description: "Confidence score between 0 and 1"
              },
              next_steps: %OpenApiSpex.Schema{
                type: :array,
                items: %{type: :string},
                description: "Recommended next steps"
              }
            },
            required: [:summary, :key_findings, :confidence_score, :next_steps]
          }
        end

        message :system, [
          text_part(
            "You are an analyst that processes stored data and provides structured analysis"
          )
        ]

        message :user, [text_part("Analyze the collected data and provide structured insights")]

        tools [DataProcessor]
      end
    end
  end
end
