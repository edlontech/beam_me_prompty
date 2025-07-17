defmodule BeamMePrompty.AgentWithMemory do
  @moduledoc false
  use BeamMePrompty.Agent

  memory do
    memory_source :short_term, BeamMePrompty.Agent.Memory.ETS,
      description: "Short-Term memory storage",
      opts: [
        table: :my_agent_memory
      ],
      default: true
  end

  agent do
    name "Agent with Memory"

    stage :first_stage do
      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Wat dis {{text}}")]
      end
    end
  end
end
