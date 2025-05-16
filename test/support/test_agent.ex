defmodule BeamMePrompty.TestAgent do
  @moduledoc false
  use BeamMePrompty.Agent

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

        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Wat dis {{text}}")]
      end
    end

    stage :second_stage do
      depends_on [:first_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Call the TestTool")]

        tool :test_tool do
          description "Test tool description"
          module BeamMePrompty.TestTool

          parameters %{
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
      depends_on [:second_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [data_part(%{this: "that"})]
        message :user, [text_part("Result: {{ second_stage }}")]
      end
    end
  end
end
