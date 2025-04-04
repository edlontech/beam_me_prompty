defmodule BeamMePrompty.TestPipeline do
  use BeamMePrompty.Pipeline

  pipeline "simple_test" do
    stage :first_stage do
      using model: "test-model"
      with_params max_tokens: 100, temperature: 0.5
      message :system, "You are a helpful assistant."
      message :user, "Process this input: {{input.text}}"

      expect_output %{
        "result" => :string
      }
    end

    stage :second_stage, depends_on: [:first_stage] do
      with_input from: :first_stage, select: "result"
      using model: "test-model"
      with_params max_tokens: 100, temperature: 0.5
      message :system, "You are a helpful assistant."
      message :user, "Analyze this further: {{input.selected_input}}"

      expect_output %{
        "analysis" => :string
      }
    end

    stage :third_stage, depends_on: [:first_stage, :second_stage] do
      with_input from: :second_stage, select: "analysis"
      call module: String, function: :upcase, as: :uppercase_result
    end
  end
end
