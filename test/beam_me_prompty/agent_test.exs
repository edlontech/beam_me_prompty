defmodule BeamMePrompty.AgentTest do
  use ExUnit.Case, async: false
  use Mimic.DSL

  import BeamMePrompty.Agent.Dsl.Part
  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.AgentWithMemory
  alias BeamMePrompty.FakeLlmClient
  alias BeamMePrompty.LLM.Errors.ToolError
  alias BeamMePrompty.TestAgent

  setup :set_mimic_global
  setup :verify_on_exit!

  describe "agent execution" do
    test "executes a simple agent" do
      input = %{"text" => "bonk bonk bonk"}

      expect(BeamMePrompty.TestTool.run(%{"val1" => "test1", "val2" => "test2"}, _context),
        do: {:ok, "Yes, it's a platypus"}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [data_part(%{"result" => "wassup"})]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do:
          {:ok,
           [
             function_call_part("id", "test_tool", %{
               "val1" => "test1",
               "val2" => "test2"
             })
           ]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("And it's Perry the Platypus!")]}
      )

      assert {:ok, results} = TestAgent.run_sync(input)

      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      assert results.first_stage == [
               %Dsl.DataPart{data: %{"result" => "wassup"}, type: :data}
             ]

      assert results.second_stage == [
               %Dsl.TextPart{text: "And it's Perry the Platypus!", type: :text}
             ]

      assert results.third_stage == [
               %Dsl.TextPart{text: "bonk bonk", type: :text}
             ]

      [
        [
          "test-model",
          [
            system: [
              %Dsl.TextPart{
                text: "You are a helpful assistant.",
                type: :text
              }
            ],
            user: [
              %Dsl.TextPart{text: "Wat dis bonk bonk bonk", type: :text}
            ]
          ],
          %BeamMePrompty.Agent.Dsl.LLMParams{
            other_params: nil,
            api_key: _,
            structured_response: nil,
            thinking_budget: nil,
            presence_penalty: 0.2,
            frequency_penalty: 0.1,
            top_k: nil,
            top_p: 0.9,
            temperature: 0.5,
            max_tokens: nil
          },
          [],
          []
        ],
        [
          "test-model",
          [
            system: [
              %Dsl.TextPart{
                text: "You are a helpful assistant.",
                type: :text
              }
            ],
            user: [
              %Dsl.TextPart{
                text: "Call the TestTool",
                type: :text
              }
            ]
          ],
          _,
          [
            %BeamMePrompty.Tool{
              module: BeamMePrompty.TestTool,
              parameters: %{
                type: :object,
                required: [:arg1],
                properties: %{
                  arg1: %{
                    type: :string,
                    description: "First argument for the test tool"
                  },
                  arg2: %{
                    type: :integer,
                    description: "Second argument for the test tool"
                  }
                }
              },
              description: "A tool for testing purposes",
              name: :test_tool
            }
          ],
          []
        ],
        [
          "test-model",
          [
            system: [
              %Dsl.TextPart{
                text: "You are a helpful assistant.",
                type: :text
              }
            ],
            user: [
              %Dsl.TextPart{
                text: "Call the TestTool",
                type: :text
              }
            ],
            assistant: [
              %Dsl.FunctionCallPart{
                function_call: %{
                  id: "id",
                  name: "test_tool",
                  arguments: %{"val1" => "test1", "val2" => "test2"}
                }
              }
            ],
            user: [
              %Dsl.FunctionResultPart{
                result: "Yes, it's a platypus",
                name: "test_tool",
                id: "id"
              }
            ]
          ],
          _,
          [
            %BeamMePrompty.Tool{
              module: BeamMePrompty.TestTool,
              parameters: %{
                type: :object,
                required: [:arg1],
                properties: %{
                  arg1: %{
                    type: :string,
                    description: "First argument for the test tool"
                  },
                  arg2: %{
                    type: :integer,
                    description: "Second argument for the test tool"
                  }
                }
              },
              description: "A tool for testing purposes",
              name: :test_tool
            }
          ],
          []
        ]
      ] = calls(&FakeLlmClient.completion/5)
    end
  end

  test "handles tool execution errors gracefully" do
    expect(
      BeamMePrompty.TestTool.run(_args, _context),
      do:
        {:error,
         ToolError.exception(
           module: BeamMePrompty.TestTool,
           cause: "Boinkers do bonk"
         )}
    )

    expect(
      BeamMePrompty.TestTool.tool_info(),
      do: %BeamMePrompty.Tool{
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
    )

    expect(
      FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
      do:
        {:ok,
         [
           %Dsl.FunctionCallPart{
             function_call: %{
               arguments: %{
                 "val1" => "test1",
                 "val2" => "test2"
               },
               name: "test_tool"
             }
           }
         ]}
    )

    expect(
      FakeLlmClient.completion(_model, messages, _llm_params, _tools, _opts),
      do:
        (
          assert [
                   system: [
                     %Dsl.TextPart{
                       text: "You are a helpful assistant.",
                       type: :text
                     }
                   ],
                   user: [%Dsl.TextPart{text: "Bonk Bonk", type: :text}],
                   assistant: [
                     %Dsl.FunctionCallPart{
                       function_call: %{
                         name: "test_tool",
                         arguments: %{"val1" => "test1", "val2" => "test2"}
                       }
                     }
                   ],
                   user: [
                     %Dsl.FunctionResultPart{
                       result: err_res,
                       name: "test_tool",
                       id: nil
                     }
                   ]
                 ] = messages

          assert err_res =~ "Boinkers"

          {:ok, [text_part("And it's Perry the Platypus!")]}
        )
    )

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

    assert {:ok, _results} = BonkedToolAgent.run_sync(%{})
  end

  test "handles LLM client errors" do
    input = %{"text" => "error test"}

    expect(
      FakeLlmClient.completion(_, _, _, _, _),
      do: {:error, BeamMePrompty.LLM.Errors.UnexpectedLLMResponse.exception()}
    )

    capture_log(fn ->
      assert {:error, _reason} = TestAgent.run_sync(input)
    end)
  end

  test "handles undefined tools gracefully" do
    input = %{"text" => "undefined tool"}

    expect(
      BeamMePrompty.TestTool.tool_info(),
      do: %BeamMePrompty.Tool{
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
    )

    expect(
      FakeLlmClient.completion(_, _, _, _, _),
      do: {:ok, [text_part("initial response")]}
    )

    expect(
      FakeLlmClient.completion(_, _, _, _tools, _),
      do:
        {:ok,
         [
           %Dsl.FunctionCallPart{
             function_call: %{name: "nonexistent_tool", arguments: %{"val1" => "test"}}
           }
         ]}
    )

    expect(
      FakeLlmClient.completion(_, messages, _, _, _),
      do:
        (
          assert Enum.any?(messages, fn
                   {:user, [%Dsl.FunctionResultPart{result: result}]} ->
                     String.contains?(result, "Tool not defined")

                   _ ->
                     false
                 end)

          {:ok, [text_part("Handled undefined tool")]}
        )
    )

    expect(
      FakeLlmClient.completion(_, _, _, _, _),
      do: {:ok, [text_part("Final stage")]}
    )

    assert {:ok, results} = TestAgent.run_sync(input)

    assert results.second_stage == [
             %Dsl.TextPart{text: "Handled undefined tool", type: :text}
           ]
  end

  test "handles data parts in messages" do
    input = %{"text" => "data test"}

    expect(
      FakeLlmClient.completion(_, _, _, _, _),
      do: {:ok, [text_part("First Stage")]}
    )

    expect(
      FakeLlmClient.completion(_, _, _, _, _),
      do: {:ok, [text_part("Second Stage")]}
    )

    expect(
      FakeLlmClient.completion(_model, messages, _, _tools, _opts),
      do:
        (
          assert Enum.any?(messages, fn
                   {:user, parts} ->
                     Enum.any?(parts, fn
                       %Dsl.DataPart{
                         data: %{complex: "data structure", with: [1, 2, 3]}
                       } ->
                         true

                       _ ->
                         false
                     end)

                   _ ->
                     false
                 end)

          {:ok, [text_part("Data Part Handled")]}
        )
    )

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

    assert results.third_stage == [
             %Dsl.TextPart{text: "Data Part Handled", type: :text}
           ]
  end

  describe "agent with memory" do
    test "should have memory tools" do
      expect(
        FakeLlmClient.completion(_, _, _, tools, _),
        do:
          (
            assert 6 = length(tools)

            {:ok, [text_part("First Stage")]}
          )
      )

      assert {:ok, _results} = AgentWithMemory.run_sync()
    end
  end
end
