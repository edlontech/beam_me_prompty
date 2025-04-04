defmodule BeamMePrompty.PipelineTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.TestPipeline

  # Mock LLM client for testing
  defmodule MockLLMClient do
    def completion(_messages, _opts) do
      # Return a mock response based on the messages
      {:ok, %{"result" => "mock result", "analysis" => "mock analysis"}}
    end
  end

  describe "pipeline structure" do
    test "each pipeline has a name" do
      assert TestPipeline.pipeline_name() == "simple_test"
    end

    test "pipeline has stages" do
      pipeline = TestPipeline.pipeline()
      assert is_list(pipeline.stages)
      assert length(pipeline.stages) == 3

      # Check stage names
      stage_names = Enum.map(pipeline.stages, & &1.name)
      assert :first_stage in stage_names
      assert :second_stage in stage_names
      assert :third_stage in stage_names
    end
  end

  describe "pipeline execution" do
    test "executes a simple pipeline" do
      input = %{"text" => "test input"}

      assert {:ok, results} =
               BeamMePrompty.execute(TestPipeline.pipeline(), input, llm_client: MockLLMClient)

      # Verify results contain all stages
      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      # Verify third stage processed the data correctly
      third_stage_result = Map.get(results, :third_stage)
      assert Map.has_key?(third_stage_result, :uppercase_result)
    end
  end
end
