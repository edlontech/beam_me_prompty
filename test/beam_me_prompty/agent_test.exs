defmodule BeamMePrompty.AgentTest do
  use ExUnit.Case, async: false

  import Hammox

  alias BeamMePrompty.TestAgent

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "agent execution" do
    test "executes a simple agent" do
      input = %{"text" => "bonk bonk bonk"}

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn messages, opts ->
        assert opts.temperature == 0.5
        assert opts.top_p == 0.9
        assert opts.frequency_penalty == 0.1
        assert opts.presence_penalty == 0.2

        assert [
                 user: "Wat dis bonk bonk bonk",
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

      assert {:ok, results} = TestAgent.run_sync(input)

      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      assert results.first_stage == %{result: "wassup"}
      assert results.second_stage == "Yes, it's a platypus"
      assert results.third_stage == {:ok, "Echoing: \"And it's Perry the Platypus!\""}
    end
  end
end
