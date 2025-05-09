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
          api_key fn -> System.get_env("TEST_API_KEY") end
        end

        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Wat dis {{text}}"}]
      end
    end

    stage :second_stage do
      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Call the TestTool"}]

        tool do
          name "test_tool"
          description "Test tool description"
          module BeamMePrompty.TestTool

          parameters %OpenApiSpex.Schema{
            type: :object,
            properties: %{
              val1: %{
                type: :string,
                description: "First value"
              },
              val2: %{
                type: :string,
                description: "Second value"
              }
            }
          }
        end
      end
    end

    stage :third_stage do
      depends_on [:first_stage, :second_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [%TextPart{type: :text, text: "You are a helpful assistant."}]
        message :user, [%TextPart{type: :text, text: "Wat dis {{text}}"}]
      end
    end
  end
end
