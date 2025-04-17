defmodule BeamMePrompty.PipelineTest do
  use ExUnit.Case, async: true

  import Hammox

  alias BeamMePrompty.TestPipeline

  setup :verify_on_exit!

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
      input = %{"text" => "what's this animal?"}

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.5
        assert Keyword.get(opts, :max_tokens) == 100
        assert Keyword.get(opts, :key) == "test-key"

        assert [
                 user: "Process this input: what's this animal?",
                 system: "You are a helpful assistant."
               ] == messages

        {:ok, %{"result" => "wassup"}}
      end)
      |> expect(:completion, fn messages, _opts ->
        assert [user: "Analyze this further: wassup", system: "You are a helpful assistant."] ==
                 messages

        {:ok, %{"analysis" => "Yes, it's a platypus"}}
      end)
      |> expect(:completion, fn _messages, _opts ->
        {:ok, %{"final_result" => "And it's Perry the Platypus!"}}
      end)

      assert {:ok, results} = BeamMePrompty.execute(TestPipeline.pipeline(), input)

      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
    end
  end
end
