defmodule BeamMePrompty.AgentTest do
  use ExUnit.Case, async: false

  import BeamMePrompty.Agent.Dsl.Part
  import ExUnit.CaptureLog
  import Hammox

  alias BeamMePrompty.LLM.Errors.ToolError
  alias BeamMePrompty.TestAgent

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "agent execution" do
    test "executes a simple agent" do
      input = %{"text" => "bonk bonk bonk"}

      expect(BeamMePrompty.TestTool, :run, fn args, _context ->
        assert args == %{"val1" => "test1", "val2" => "test2"}
        {:ok, "Yes, it's a platypus"}
      end)

      expect(BeamMePrompty.TestTool, :tool_info, fn ->
        %BeamMePrompty.Tool{
          name: :test_tool,
          description: "Test tool",
          module: BeamMePrompty.TestTool,
          parameters: %{
            type: "object",
            properties: %{
              val1: %{
                type: "string",
                description: "First value"
              },
              val2: %{
                type: "string",
                description: "Second value"
              }
            },
            required: ["val1", "val2"]
          }
        }
      end)

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _model, messages, llm_params, _tools, _opts ->
        assert llm_params.temperature == 0.5
        assert llm_params.top_p == 0.9
        assert llm_params.frequency_penalty == 0.1
        assert llm_params.presence_penalty == 0.2

        assert [
                 system: [text_part("You are a helpful assistant.")],
                 user: [text_part("Wat dis bonk bonk bonk")]
               ] == messages

        {:ok, %{"result" => "wassup"}}
      end)
      |> expect(:completion, fn _model, messages, _, tools, _opts ->
        assert [
                 system: [text_part("You are a helpful assistant.")],
                 user: [text_part("Call the TestTool")]
               ] == messages

        assert tools == [
                 %BeamMePrompty.Tool{
                   parameters: %{
                     type: "object",
                     required: ["val1", "val2"],
                     properties: %{
                       val1: %{type: "string", description: "First value"},
                       val2: %{type: "string", description: "Second value"}
                     }
                   },
                   description: "Test tool",
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
      |> expect(:completion, fn _model, messages, _llm_params, _tools, _opts ->
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
      |> expect(:completion, fn _model, messages, _llm_params, _tools, _opts ->
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

    test "handles tool execution errors gracefully" do
      expect(BeamMePrompty.TestTool, :run, fn _args, _context ->
        {:error,
         ToolError.exception(
           module: BeamMePrompty.TestTool,
           cause: "Boinkers do bonk"
         )}
      end)

      expect(BeamMePrompty.TestTool, :tool_info, fn ->
        %BeamMePrompty.Tool{
          name: :test_tool,
          description: "Test tool",
          module: BeamMePrompty.TestTool,
          parameters: %{
            type: "object",
            properties: %{
              val1: %{
                type: "string",
                description: "First value"
              },
              val2: %{
                type: "string",
                description: "Second value"
              }
            },
            required: ["val1", "val2"]
          }
        }
      end)

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _model, _messages, _llm_params, _tools, _opts ->
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
      |> expect(:completion, fn _model, messages, _llm_params, _tools, _opts ->
        assert [
                 system: [
                   %BeamMePrompty.Agent.Dsl.TextPart{
                     text: "You are a helpful assistant.",
                     type: :text
                   }
                 ],
                 user: [%BeamMePrompty.Agent.Dsl.TextPart{text: "Bonk Bonk", type: :text}],
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
                     result: "Error executing tool test_tool (call_id: N/A): Boinkers do bonk",
                     name: :test_tool,
                     id: nil
                   }
                 ]
               ] == messages

        {:ok, "And it's Perry the Platypus!"}
      end)

      defmodule BonkedToolAgent do
        @moduledoc false
        use BeamMePrompty.Agent

        agent do
          stage :first_stage do
            llm "test-model", BeamMePrompty.FakeLlmClient do
              message :system, [text_part("You are a helpful assistant.")]
              message :user, [text_part("Bonk Bonk")]

              tools [BeamMePrompty.TestTool]
            end
          end
        end
      end

      capture_log(fn ->
        assert {:ok, _results} = BonkedToolAgent.run_sync(%{})
      end)
    end

    test "handles LLM client errors" do
      input = %{"text" => "error test"}

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _, _, _, _, _ ->
        {:error, BeamMePrompty.LLM.Errors.UnexpectedLLMResponse.exception()}
      end)

      capture_log(fn ->
        assert {:error, _reason} = TestAgent.run_sync(input)
      end)
    end

    test "properly handles nested tool calls" do
      input = %{"text" => "nested tools"}

      # Setup expectations for a chain of tool calls
      expect(BeamMePrompty.TestTool, :run, 2, fn args, _ ->
        case args do
          %{"val1" => "first_call"} -> {:ok, "First tool result"}
          %{"val1" => "second_call"} -> {:ok, "Second tool result"}
        end
      end)

      expect(BeamMePrompty.TestTool, :tool_info, fn ->
        %BeamMePrompty.Tool{
          name: :test_tool,
          description: "Test tool",
          module: BeamMePrompty.TestTool,
          parameters: %{
            type: "object",
            properties: %{
              val1: %{
                type: "string",
                description: "First value"
              },
              val2: %{
                type: "string",
                description: "Second value"
              }
            },
            required: ["val1", "val2"]
          }
        }
      end)

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _, _, _, _, _ ->
        {:ok, "Initial response"}
      end)
      |> expect(:completion, fn _, _, _, _, _ ->
        # First function call
        {:ok,
         %{
           function_call: %{
             name: "test_tool",
             arguments: %{"val1" => "first_call", "val2" => "test"}
           }
         }}
      end)
      |> expect(:completion, fn _, messages, _llm_params, _tools, _ ->
        # Verify the first tool result was returned
        assert Enum.any?(messages, fn
                 {:user,
                  [%BeamMePrompty.Agent.Dsl.FunctionResultPart{result: "First tool result"}]} ->
                   true

                 _ ->
                   false
               end)

        # Second function call
        {:ok,
         %{
           function_call: %{
             name: "test_tool",
             arguments: %{"val1" => "second_call", "val2" => "test"}
           }
         }}
      end)
      |> expect(:completion, fn _, messages, _, _, _ ->
        # Verify the second tool result was returned
        assert Enum.any?(messages, fn
                 {:user,
                  [%BeamMePrompty.Agent.Dsl.FunctionResultPart{result: "Second tool result"}]} ->
                   true

                 _ ->
                   false
               end)

        {:ok, "Multiple tool calls worked"}
      end)
      |> expect(:completion, fn _, _, _, _, _ ->
        {:ok, "Final stage complete"}
      end)

      assert {:ok, results} = TestAgent.run_sync(input)
      assert results.second_stage == "Multiple tool calls worked"
    end

    test "handles undefined tools gracefully" do
      input = %{"text" => "undefined tool"}

      expect(BeamMePrompty.TestTool, :tool_info, fn ->
        %BeamMePrompty.Tool{
          name: :test_tool,
          description: "Test tool",
          module: BeamMePrompty.TestTool,
          parameters: %{
            type: "object",
            properties: %{
              val1: %{
                type: "string",
                description: "First value"
              },
              val2: %{
                type: "string",
                description: "Second value"
              }
            },
            required: ["val1", "val2"]
          }
        }
      end)

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _, _, _, _, _ ->
        {:ok, "Initial response"}
      end)
      |> expect(:completion, fn _, _, _, _tools, _ ->
        {:ok, %{function_call: %{name: "nonexistent_tool", arguments: %{"val1" => "test"}}}}
      end)
      |> expect(:completion, fn _, messages, _, _, _ ->
        assert Enum.any?(messages, fn
                 {:user, [%BeamMePrompty.Agent.Dsl.FunctionResultPart{result: result}]} ->
                   String.contains?(result, "Tool not defined")

                 _ ->
                   false
               end)

        {:ok, "Handled undefined tool"}
      end)
      |> expect(:completion, fn _, _, _, _, _ ->
        {:ok, "Final stage"}
      end)

      assert {:ok, results} = TestAgent.run_sync(input)
      assert results.second_stage == "Handled undefined tool"
    end

    test "handles data parts in messages" do
      input = %{"text" => "data test"}

      BeamMePrompty.FakeLlmClient
      |> expect(:completion, fn _, _, _, _, _ ->
        {:ok, "First stage"}
      end)
      |> expect(:completion, fn _, _, _, _, _ ->
        {:ok, "Second stage"}
      end)
      |> expect(:completion, fn _model, messages, _, _tools, _opts ->
        assert Enum.any?(messages, fn
                 {:user, parts} ->
                   Enum.any?(parts, fn
                     %BeamMePrompty.Agent.Dsl.DataPart{
                       data: %{complex: "data structure", with: [1, 2, 3]}
                     } ->
                       true

                     _ ->
                       false
                   end)

                 _ ->
                   false
               end)

        {:ok, "Data part handled"}
      end)

      # Create agent with complex data part
      defmodule DataPartAgent do
        use BeamMePrompty.Agent

        agent do
          stage :first_stage do
            llm "test-model", BeamMePrompty.FakeLlmClient do
              message :user, [text_part("Test")]
            end
          end

          stage :second_stage do
            depends_on [:first_stage]

            llm "test-model", BeamMePrompty.FakeLlmClient do
              message :user, [text_part("Test")]
            end
          end

          stage :third_stage do
            depends_on [:second_stage]

            llm "test-model", BeamMePrompty.FakeLlmClient do
              message :user, [data_part(%{complex: "data structure", with: [1, 2, 3]})]
              message :user, [text_part("Test after data")]
            end
          end
        end
      end

      assert {:ok, results} = DataPartAgent.run_sync(input)
      assert results.third_stage == "Data part handled"
    end
  end
end
