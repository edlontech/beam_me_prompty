defmodule BeamMePrompty.TestAgent do
  use BeamMePrompty.Agent

  agent "simple_test" do
    stage :first_stage do
      using model: "test-model", llm_client: BeamMePrompty.FakeLlmClient

      with_params max_tokens: 100, temperature: 0.5, key: {:env, "TEST_KEY"}

      message :system, "You are a helpful assistant."
      message :user, "Process this input: {{input.text}}"

      expect_output %{
        "result" => :string
      }
    end

    stage :second_stage, depends_on: [:first_stage] do
      using model: "test-model", llm_client: BeamMePrompty.FakeLlmClient

      with_input from: :first_stage, select: "result"
      with_params max_tokens: 100, temperature: 0.5

      message :system, "You are a helpful assistant."
      message :user, "Analyze this further: {{input.selected_input}}"

      expect_output %{
        "analysis" => :string
      }
    end

    stage :third_stage, depends_on: [:first_stage, :second_stage] do
      using model: "test-model", llm_client: BeamMePrompty.FakeLlmClient

      with_input from: :second_stage, select: "analysis"
      with_params max_tokens: 100, temperature: 0.5

      message :system, "You are a helpful assistant."
      message :user, "Boink Boink"

      call fn _stage_input, llm_output ->
        {:ok, "Echoing: #{inspect(llm_output)}"}
      end

      expect_output %{
        "final_result" => :string
      }
    end
  end
end
