defmodule BeamMePrompty.IntegrationAgents.OpenAI.AgentWithMemory do
  @moduledoc "OpenAI agent with memory but without tools or structured responses"
  use BeamMePrompty.Agent

  memory do
    memory_source :short_term, BeamMePrompty.Agent.Memory.ETS,
      description: "Short-term memory storage for OpenAI agent",
      opts: [
        table: :openai_agent_memory
      ],
      default: true
  end

  agent do
    name "OpenAI Agent with Memory"

    stage :store_info do
      llm "gpt-4o-mini", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_OPENAI_API_KEY") end
        end

        message :system, [
          text_part("You are a helpful assistant that stores information in memory")
        ]

        message :user, [text_part("Store this information in memory: <%= info %>")]
      end
    end

    stage :recall_info do
      depends_on [:store_info]

      llm "gpt-4o-mini", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("INTELLIGENCE_OPENAI_API_KEY") end
        end

        message :system, [
          text_part("You are a helpful assistant that can retrieve information from memory")
        ]

        message :user, [text_part("Retrieve and tell me about: <%= query %>")]
      end
    end
  end
end
