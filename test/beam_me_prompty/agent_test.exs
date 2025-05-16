defmodule BeamMePrompty.AgentTest do
  use ExUnit.Case, async: false

  import BeamMePrompty.Agent.Dsl.Part
  import Hammox

  alias BeamMePrompty.TestAgent

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "agent execution" do
    test "executes a simple agent" do
      input = %{"text" => "bonk bonk bonk"}

      expect(BeamMePrompty.TestTool, :run, fn args ->
        assert args == %{"val1" => "test1", "val2" => "test2"}
        {:ok, "Yes, it's a platypus"}
      end)

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _model, messages, _tools, opts ->
        assert opts.temperature == 0.5
        assert opts.top_p == 0.9
        assert opts.frequency_penalty == 0.1
        assert opts.presence_penalty == 0.2

        assert [
                 system: [text_part("You are a helpful assistant.")],
                 user: [text_part("Wat dis bonk bonk bonk")]
               ] == messages

        {:ok, %{"result" => "wassup"}}
      end)
      |> expect(:completion, fn _model, messages, tools, _opts ->
        assert [
                 system: [text_part("You are a helpful assistant.")],
                 user: [text_part("Call the TestTool")]
               ] == messages

        assert tools == [
                 %BeamMePrompty.Agent.Dsl.Tool{
                   parameters: %{
                     type: :object,
                     properties: %{
                       val1: %{type: :string, description: "First value"},
                       val2: %{type: :string, description: "Second value"}
                     }
                   },
                   description: "Test tool description",
                   name: :test_tool,
                   module: BeamMePrompty.TestTool
                 }
               ]

        {:ok,
         %{
           function_call: %{
             arguments: %{
               "val1" => "test1",
               "val2" => "test2"
             },
             name: "test_tool"
           }
         }}
      end)
      |> expect(:completion, fn _model, messages, _tools, _opts ->
        assert [
                 system: [
                   %BeamMePrompty.Agent.Dsl.TextPart{
                     text: "You are a helpful assistant.",
                     type: :text
                   }
                 ],
                 user: [
                   %BeamMePrompty.Agent.Dsl.TextPart{text: "Call the TestTool", type: :text}
                 ],
                 assistant: [
                   %BeamMePrompty.Agent.Dsl.FunctionCallPart{
                     function_call: %{
                       name: "test_tool",
                       arguments: %{"val1" => "test1", "val2" => "test2"}
                     }
                   }
                 ],
                 user: [
                   %BeamMePrompty.Agent.Dsl.FunctionResultPart{
                     result: "Yes, it's a platypus",
                     name: :test_tool,
                     id: nil
                   }
                 ]
               ] == messages

        {:ok, "And it's Perry the Platypus!"}
      end)
      |> expect(:completion, fn _model, messages, _tools, _opts ->
        assert [
                 system: [
                   %BeamMePrompty.Agent.Dsl.TextPart{
                     text: "You are a helpful assistant.",
                     type: :text
                   }
                 ],
                 user: [%BeamMePrompty.Agent.Dsl.DataPart{data: %{this: "that"}, type: :data}],
                 user: [
                   %BeamMePrompty.Agent.Dsl.TextPart{
                     text: "Result: And it's Perry the Platypus!",
                     type: :text
                   }
                 ]
               ] == messages

        {:ok, "boink boink"}
      end)

      assert {:ok, results} = TestAgent.run_sync(input)

      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      assert results.first_stage == %{"result" => "wassup"}
      assert results.second_stage == "And it's Perry the Platypus!"
      assert results.third_stage == "boink boink"
    end
  end
end
