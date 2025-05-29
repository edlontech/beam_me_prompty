defmodule BeamMePrompty.Agent.Stage.LlmProcessorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias BeamMePrompty.Agent.Stage.Config
  alias BeamMePrompty.Agent.Stage.LLMProcessor
  alias BeamMePrompty.Agent.Stage.LLMProcessor.Context
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.Agent.Stage.ToolExecutor
  alias BeamMePrompty.LLM
  alias BeamMePrompty.Telemetry
  alias BeamMePrompty.Validator

  describe "maybe_call_llm/7" do
    setup do
      session_id = "test-session"
      agent_module = TestAgent
      current_agent_state = %{test: "state"}
      stage_name = :test_stage
      input = "test input"
      initial_messages = [%{role: "user", content: "hello"}]

      {
        :ok,
        session_id: session_id,
        agent_module: agent_module,
        current_agent_state: current_agent_state,
        stage_name: stage_name,
        input: input,
        initial_messages: initial_messages
      }
    end

    test "processes valid LLM config successfully", context do
      config = %{
        model: "gpt-4",
        llm_client: MockLLMClient,
        params: [%BeamMePrompty.Agent.Dsl.LLMParams{}],
        tools: []
      }

      expect(Config, :default_max_tool_iterations, fn -> 5 end)

      expect(MessageManager, :prepare_messages_for_llm, fn _config, _input, _history ->
        [%{role: "user", content: "prepared message"}]
      end)

      expect(LLM, :completion, fn _client, _model, _messages, _params, _tools, _opts ->
        {:ok, "final response"}
      end)

      expect(Telemetry, :llm_call_start, fn _, _, _, _, _, _, _ -> :ok end)
      expect(Telemetry, :llm_call_stop, fn _, _, _, _, _, _, _ -> :ok end)

      expect(MessageManager, :combine_messages_for_llm, fn _history, _current ->
        [%{role: "user", content: "combined"}]
      end)

      expect(MessageManager, :format_response, fn response ->
        %{role: "assistant", content: response}
      end)

      expect(MessageManager, :append_assistant_response, fn messages, response ->
        messages ++ [response]
      end)

      result =
        LLMProcessor.maybe_call_llm(
          [config],
          context.input,
          context.initial_messages,
          context.agent_module,
          context.current_agent_state,
          context.session_id,
          context.stage_name
        )

      assert {:ok, "final response", _messages, _state} = result
    end

    test "handles invalid config with missing model", context do
      config = %{
        model: nil,
        llm_client: MockLLMClient,
        params: [],
        tools: []
      }

      result =
        LLMProcessor.maybe_call_llm(
          [config],
          context.input,
          context.initial_messages,
          context.agent_module,
          context.current_agent_state,
          context.session_id,
          context.stage_name
        )

      assert {:ok, %{}, _, _} = result
    end

    test "handles invalid config with missing llm_client", context do
      config = %{
        model: "gpt-4",
        llm_client: nil,
        params: [],
        tools: []
      }

      result =
        LLMProcessor.maybe_call_llm(
          [config],
          context.input,
          context.initial_messages,
          context.agent_module,
          context.current_agent_state,
          context.session_id,
          context.stage_name
        )

      assert {:ok, %{}, _, _} = result
    end

    test "handles empty config list", context do
      result =
        LLMProcessor.maybe_call_llm(
          [],
          context.input,
          context.initial_messages,
          context.agent_module,
          context.current_agent_state,
          context.session_id,
          context.stage_name
        )

      assert {:ok, %{}, _, _} = result
    end

    test "handles unhandled config format", context do
      result =
        LLMProcessor.maybe_call_llm(
          "invalid",
          context.input,
          context.initial_messages,
          context.agent_module,
          context.current_agent_state,
          context.session_id,
          context.stage_name
        )

      assert {:ok, %{}, _, _} = result
    end
  end

  describe "process_llm_interactions/2" do
    setup do
      context = %Context{
        session_id: "test-session",
        llm_client: MockLLMClient,
        model: "gpt-4",
        available_tools: [],
        llm_params: %BeamMePrompty.Agent.Dsl.LLMParams{},
        message_history: [],
        remaining_iterations: 5,
        agent_module: TestAgent,
        current_agent_state: %{},
        stage_name: :test_stage
      }

      {:ok, context: context}
    end

    test "returns error when max iterations reached", %{context: context} do
      zero_iterations_context = %Context{context | remaining_iterations: 0}
      messages = [%{role: "user", content: "test"}]

      result = LLMProcessor.process_llm_interactions(zero_iterations_context, messages)

      assert {:error, %BeamMePrompty.Errors.ExecutionError{}, [], %{}} = result
    end

    test "processes successful LLM completion", %{context: context} do
      messages = [%{role: "user", content: "test"}]
      llm_response = "test response"

      expect(MessageManager, :combine_messages_for_llm, fn _history, _current ->
        [%{role: "user", content: "combined"}]
      end)

      expect(Telemetry, :llm_call_start, fn _, _, _, _, _, _, _ -> :ok end)
      expect(Telemetry, :llm_call_stop, fn _, _, _, _, _, _, _ -> :ok end)

      expect(LLM, :completion, fn _client, _model, _messages, _params, _tools, _opts ->
        {:ok, llm_response}
      end)

      expect(MessageManager, :format_response, fn response ->
        %{role: "assistant", content: response}
      end)

      expect(MessageManager, :append_assistant_response, fn messages, response ->
        messages ++ [response]
      end)

      result = LLMProcessor.process_llm_interactions(context, messages)

      assert {:ok, "test response", _messages, _state} = result
    end

    test "handles LLM completion error", %{context: context} do
      messages = [%{role: "user", content: "test"}]
      error_reason = %{error: "API error"}

      expect(MessageManager, :combine_messages_for_llm, fn _history, _current ->
        [%{role: "user", content: "combined"}]
      end)

      expect(Telemetry, :llm_call_start, fn _, _, _, _, _, _, _ -> :ok end)
      expect(Telemetry, :llm_call_stop, fn _, _, _, _, _, _, _ -> :ok end)

      expect(LLM, :completion, fn _client, _model, _messages, _params, _tools, _opts ->
        {:error, error_reason}
      end)

      result = LLMProcessor.process_llm_interactions(context, messages)

      assert {:error, ^error_reason, [], %{}} = result
    end
  end

  describe "handle_llm_response/2" do
    setup do
      context = %Context{
        session_id: "test-session",
        llm_client: MockLLMClient,
        model: "gpt-4",
        available_tools: [],
        llm_params: %BeamMePrompty.Agent.Dsl.LLMParams{},
        message_history: [],
        remaining_iterations: 5,
        agent_module: TestAgent,
        current_agent_state: %{},
        stage_name: :test_stage
      }

      {:ok, context: context}
    end

    test "handles final response without tool calls", %{context: context} do
      llm_response = "This is a final response"

      result = LLMProcessor.handle_llm_response(context, llm_response)

      assert {:ok, "This is a final response", [], %{}} = result
    end

    test "handles tool call response", %{context: context} do
      tool_response = %{
        function_call: %{
          name: "test_tool",
          arguments: %{"param" => "value"}
        }
      }

      expect(ToolExecutor, :extract_tool_info, fn _tool_part ->
        %{name: "test_tool", arguments: %{"param" => "value"}}
      end)

      expect(ToolExecutor, :process_tool_call, fn _tool_info,
                                                  _tools,
                                                  _client,
                                                  _model,
                                                  _params,
                                                  _history,
                                                  _iterations,
                                                  _agent,
                                                  _state,
                                                  _stage,
                                                  _session ->
        {
          :continue_llm_interactions,
          MockLLMClient,
          "gpt-4",
          [],
          %BeamMePrompty.Agent.Dsl.LLMParams{},
          [],
          [%{role: "user", content: "tool result"}],
          4,
          TestAgent,
          %{}
        }
      end)

      expect(MessageManager, :combine_messages_for_llm, fn _history, _current ->
        [%{role: "user", content: "combined"}]
      end)

      expect(Telemetry, :llm_call_start, fn _, _, _, _, _, _, _ -> :ok end)
      expect(Telemetry, :llm_call_stop, fn _, _, _, _, _, _, _ -> :ok end)

      expect(LLM, :completion, fn _client, _model, _messages, _params, _tools, _opts ->
        {:ok, "final response after tool"}
      end)

      expect(MessageManager, :format_response, fn response ->
        %{role: "assistant", content: response}
      end)

      expect(MessageManager, :append_assistant_response, fn messages, response ->
        messages ++ [response]
      end)

      result = LLMProcessor.handle_llm_response(context, tool_response)

      assert {:ok, "final response after tool", _messages, _state} = result
    end
  end

  describe "function_call_response/1" do
    test "identifies function call in map response" do
      response = %{
        function_call: %{name: "test_function"},
        content: "some content"
      }

      result = LLMProcessor.function_call_response(response)

      assert {:tool, ^response} = result
    end

    test "identifies function call in list response" do
      function_call_part = %{function_call: %{name: "test_function"}}
      response = [%{content: "text"}, function_call_part, %{content: "more text"}]

      result = LLMProcessor.function_call_response(response)

      assert {:tool, ^function_call_part} = result
    end

    test "returns final response when no function calls in list" do
      response = [%{content: "text"}, %{content: "more text"}]

      result = LLMProcessor.function_call_response(response)

      assert {:ok, ^response} = result
    end

    test "returns final response for non-function call responses" do
      response = "simple string response"

      result = LLMProcessor.function_call_response(response)

      assert {:ok, ^response} = result
    end

    test "handles function call with empty name" do
      response = %{function_call: %{name: ""}}

      result = LLMProcessor.function_call_response(response)

      assert {:tool, %{function_call: %{name: ""}}} = result
    end

    test "handles function call with nil name" do
      response = %{function_call: %{name: nil}}

      result = LLMProcessor.function_call_response(response)

      assert {:ok, ^response} = result
    end
  end

  describe "validate_structured_response/2" do
    test "returns response when no structured_response schema" do
      llm_response = %{data: "test"}
      llm_params = %BeamMePrompty.Agent.Dsl.LLMParams{structured_response: nil}

      result = LLMProcessor.validate_structured_response(llm_response, llm_params)

      assert {:ok, ^llm_response} = result
    end

    test "validates response against schema successfully" do
      llm_response = %{data: "test"}
      schema = %{"type" => "object"}
      llm_params = %BeamMePrompty.Agent.Dsl.LLMParams{structured_response: schema}
      normalized_response = %{"data" => "test"}
      validated_data = %{"data" => "test"}

      expect(MessageManager, :normalize_response_for_validation, fn _response ->
        normalized_response
      end)

      expect(Validator, :validate, fn _schema, _data ->
        {:ok, validated_data}
      end)

      result = LLMProcessor.validate_structured_response(llm_response, llm_params)

      assert {:ok, ^validated_data} = result
    end

    test "handles validation error" do
      llm_response = %{data: "test"}
      schema = %{"type" => "object"}
      llm_params = %BeamMePrompty.Agent.Dsl.LLMParams{structured_response: schema}
      normalized_response = %{"data" => "test"}
      validation_error = %{error: "validation failed"}

      expect(MessageManager, :normalize_response_for_validation, fn _response ->
        normalized_response
      end)

      expect(Validator, :validate, fn _schema, _data ->
        {:error, validation_error}
      end)

      result = LLMProcessor.validate_structured_response(llm_response, llm_params)

      assert {:error, ^validation_error} = result
    end
  end
end
