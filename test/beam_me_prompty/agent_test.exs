defmodule BeamMePrompty.AgentTest do
  use ExUnit.Case, async: true

  import Hammox

  alias BeamMePrompty.TestAgent

  setup :verify_on_exit!

  describe "agent structure" do
    test "each agent has a name" do
      assert TestAgent.agent_name() == "simple_test"
    end

    test "agent has stages" do
      agent = TestAgent.agent()
      assert is_list(agent.stages)
      assert length(agent.stages) == 3

      # Check stage names
      stage_names = Enum.map(agent.stages, & &1.name)
      assert :first_stage in stage_names
      assert :second_stage in stage_names
      assert :third_stage in stage_names
    end
  end

  describe "agent execution" do
    test "executes a simple agent" do
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

        {:ok, "Yes, it's a platypus"}
      end)
      |> expect(:completion, fn _messages, _opts ->
        {:ok, "And it's Perry the Platypus!"}
      end)

      assert {:ok, results} = TestAgent.start_link([])

      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      assert results.first_stage == %{result: "wassup"}
      assert results.second_stage == "Yes, it's a platypus"
      assert results.third_stage == {:ok, "Echoing: \"And it's Perry the Platypus!\""}
    end
  end
end
