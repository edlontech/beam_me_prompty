defmodule BeamMePrompty.FullAgent do
  @moduledoc false
  use BeamMePrompty.Agent

  def get_test_api_key do
    System.get_env("TEST_API_KEY")
  end

  memory do
    memory_source :short_term, BeamMePrompty.Agent.Memory.ETS,
      description: "Short-Term memory storage",
      opts: [
        table: :my_agent_memory
      ],
      default: true
  end

  agent do
    name "Full Test Agent"
    version "0.1.0"
    agent_state :stateless

    stage :first_stage do
      llm "test-model", BeamMePrompty.FakeLlmClient do
        with_params do
          temperature 0.5
          top_p 0.9
          frequency_penalty 0.1
          presence_penalty 0.2
          api_key &__MODULE__.get_test_api_key/0
        end

        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Wat dis <%= text %>")]
      end
    end

    stage :second_stage do
      depends_on [:first_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Call the TestTool")]

        tools [BeamMePrompty.TestTool]
      end
    end

    stage :third_stage do
      depends_on [:second_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [data_part(%{this: "that"})]
        message :user, [text_part("Result: <%= inspect(second_stage) %>")]
      end
    end
  end
end
