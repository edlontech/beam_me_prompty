defmodule BeamMePrompty.TestAgent do
  use BeamMePrompty.Agent

  alias BeamMePrompty.Agent.Dsl.TextPart

  agent do
    stage :first_stage do
      llm "test-model", BeamMePrompty.FakeLlmClient do
        with_params do
          temperature 0.5
          top_p 0.9
          frequency_penalty 0.1
          presence_penalty 0.2
        end

        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Wat dis {{text}}"}]
      end
    end

    stage :second_stage do
      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
      end
    end
  end
end
