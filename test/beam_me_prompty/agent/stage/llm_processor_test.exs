defmodule BeamMePrompty.Agent.Stage.LlmProcessorTest do
  use ExUnit.Case, async: true
  use Mimic.DSL

  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Stage.LLMProcessor
  alias BeamMePrompty.Agent.Stage.ToolExecutor
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors
  alias BeamMePrompty.LLM.GoogleGemini

  setup :verify_on_exit!

  describe "maybe_call_llm/7 - basic functionality" do
    setup do
      valid_config = %Dsl.LLM{
        model: "gpt-4",
        llm_client: GoogleGemini,
        tools: [],
        messages: [
          %Dsl.Message{
            role: :user,
            content: [Dsl.Part.text_part("Hello, this is a test message.")]
          }
        ],
        params: [%Dsl.LLMParams{}]
      }

      %{
        valid_config: valid_config,
        input: %{"test" => "test"},
        initial_messages: [],
        agent_module: BeamMePrompty.TestAgent,
        current_agent_state: %{memory_manager: nil},
        session_id: make_ref(),
        stage_name: :test_stage
      }
    end

    test "should call an llm successfully with simple text response", context do
      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [Dsl.Part.text_part("LLM Response")]}
      )

      assert {:ok, [%Dsl.TextPart{text: "LLM Response", type: :text}], history, %{}} =
               LLMProcessor.maybe_call_llm(
                 context.valid_config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )

      # Verify history contains both user and assistant messages
      assert length(history) == 2
      assert Keyword.has_key?(history, :user)
      assert Keyword.has_key?(history, :assistant)
    end

    test "should skip processing when no llm config provided", context do
      assert {:ok, [], [], %{}} =
               LLMProcessor.maybe_call_llm(
                 [],
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should return error for invalid config format", context do
      assert {:error, %BeamMePrompty.Errors.ExecutionError{cause: :unhandled_config_format}, [],
              %{}} =
               LLMProcessor.maybe_call_llm(
                 "invalid config",
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle LLM client error", context do
      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:error, %Errors.UnexpectedLLMResponse{status: 500, cause: "API Error"}}
      )

      assert {:error, %Errors.UnexpectedLLMResponse{}, [], %{}} =
               LLMProcessor.maybe_call_llm(
                 context.valid_config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle empty LLM response", context do
      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, []})

      assert {:error, %BeamMePrompty.Errors.ExecutionError{cause: :empty_llm_response}, _, %{}} =
               LLMProcessor.maybe_call_llm(
                 context.valid_config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end
  end

  describe "structured response validation" do
    setup do
      %{
        input: %{},
        initial_messages: [],
        agent_module: TestAgent,
        current_agent_state: %{memory_manager: nil},
        session_id: make_ref(),
        stage_name: :test_stage
      }
    end

    test "should validate structured response successfully", context do
      schema = %OpenApiSpex.Schema{
        type: :object,
        properties: %{message: %OpenApiSpex.Schema{type: :string}}
      }

      config = %Dsl.LLM{
        model: "gpt-4",
        llm_client: GoogleGemini,
        tools: [],
        messages: [%Dsl.Message{role: :user, content: [Dsl.Part.text_part("Test")]}],
        params: [%Dsl.LLMParams{structured_response: schema}]
      }

      response_data = Dsl.Part.data_part(%{"message" => "Hello"})

      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, [response_data]})

      assert {:ok, %{message: "Hello"}, _, %{}} =
               LLMProcessor.maybe_call_llm(
                 config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle structured response validation failure", context do
      schema = %OpenApiSpex.Schema{
        type: :object,
        properties: %{message: %OpenApiSpex.Schema{type: :string}},
        required: [:message]
      }

      config = %Dsl.LLM{
        model: "gpt-4",
        llm_client: GoogleGemini,
        tools: [],
        messages: [%Dsl.Message{role: :user, content: [Dsl.Part.text_part("Test")]}],
        params: [%Dsl.LLMParams{structured_response: schema}]
      }

      response_data = Dsl.Part.data_part(%{"invalid" => "data"})

      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, [response_data]})

      capture_log(fn ->
        assert {:error, %BeamMePrompty.Errors.ValidationError{}, _, %{}} =
                 LLMProcessor.maybe_call_llm(
                   config,
                   context.input,
                   context.initial_messages,
                   context.agent_module,
                   context.current_agent_state,
                   context.session_id,
                   context.stage_name
                 )
      end)
    end
  end

  describe "tool calling functionality" do
    setup do
      config = %Dsl.LLM{
        model: "gpt-4",
        llm_client: GoogleGemini,
        tools: [BeamMePrompty.TestTool],
        messages: [%Dsl.Message{role: :user, content: [Dsl.Part.text_part("Use the tool")]}],
        params: [%Dsl.LLMParams{}]
      }

      %{
        config: config,
        input: %{},
        initial_messages: [],
        agent_module: BeamMePrompty.TestAgent,
        current_agent_state: %{memory_manager: nil},
        session_id: make_ref(),
        stage_name: :test_stage
      }
    end

    test "should execute single tool call successfully", context do
      function_call = %FunctionCallPart{
        function_call: %{id: "call_1", name: "test_tool", arguments: %{}}
      }

      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [function_call]}
      )

      expect(ToolExecutor.execute_tool(_, _, _),
        do: {:ok, "tool result"}
      )

      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [Dsl.Part.text_part("Final response")]}
      )

      assert {:ok, [%Dsl.TextPart{text: "Final response"}], _, %{}} =
               LLMProcessor.maybe_call_llm(
                 context.config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle tool not found error", context do
      function_call = %FunctionCallPart{
        function_call: %{id: "call_1", name: "unknown_tool", arguments: %{}}
      }

      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, [function_call]})

      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [Dsl.Part.text_part("Tool not found error handled")]}
      )

      assert {:ok, [%Dsl.TextPart{text: "Tool not found error handled"}], _, %{}} =
               LLMProcessor.maybe_call_llm(
                 context.config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle tool execution error", context do
      function_call = %FunctionCallPart{
        function_call: %{id: "call_1", name: "test_tool", arguments: %{}}
      }

      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, [function_call]})

      expect(ToolExecutor.execute_tool(_, _, _),
        do: {:error, "tool failed"}
      )

      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [Dsl.Part.text_part("Handled tool execution error")]}
      )

      assert {:ok, [%Dsl.TextPart{text: "Handled tool execution error"}], _, %{}} =
               LLMProcessor.maybe_call_llm(
                 context.config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle multiple tool calls in one response", context do
      function_calls = [
        %FunctionCallPart{
          function_call: %{id: "call_1", name: "test_tool", arguments: %{param: "value1"}}
        },
        %FunctionCallPart{
          function_call: %{id: "call_2", name: "test_tool", arguments: %{param: "value2"}}
        }
      ]

      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, function_calls})

      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [Dsl.Part.text_part("All tools executed successfully")]}
      )

      assert {:ok, [%Dsl.TextPart{text: "All tools executed successfully"}], _, %{}} =
               LLMProcessor.maybe_call_llm(
                 context.config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end

    test "should handle mixed content and tool calls", context do
      mixed_response = [
        Dsl.Part.text_part("I'll help you with that. Let me use a tool:"),
        %FunctionCallPart{
          function_call: %{id: "call_1", name: "test_tool", arguments: %{}}
        }
      ]

      expect(GoogleGemini.completion(_, _, _, _, _), do: {:ok, mixed_response})

      expect(GoogleGemini.completion(_, _, _, _, _),
        do: {:ok, [Dsl.Part.text_part("Based on the tool result, here's my final answer")]}
      )

      assert {:ok, [%Dsl.TextPart{text: "Based on the tool result, here's my final answer"}], _,
              %{}} =
               LLMProcessor.maybe_call_llm(
                 context.config,
                 context.input,
                 context.initial_messages,
                 context.agent_module,
                 context.current_agent_state,
                 context.session_id,
                 context.stage_name
               )
    end
  end
end
