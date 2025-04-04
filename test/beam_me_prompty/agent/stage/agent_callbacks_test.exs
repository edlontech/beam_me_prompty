defmodule BeamMePrompty.Agent.Stage.AgentCallbacksTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.Stage.AgentCallbacks

  defmodule MockAgentSuccess do
    def handle_stage_start(_node_def, state) do
      Map.put(state, :stage_started, true)
    end

    def handle_tool_call(_tool_name, _tool_args, state) do
      {:ok, Map.put(state, :tool_called, true)}
    end

    def handle_tool_result(_tool_name, _tool_result, state) do
      {:ok, Map.put(state, :tool_result_handled, true)}
    end
  end

  defmodule MockAgentVariousResponses do
    def handle_stage_start(_node_def, state) do
      Map.put(state, :custom_stage_response, true)
    end

    def handle_tool_call(:return_ok, _tool_args, _state) do
      :ok
    end

    def handle_tool_call(:return_ok_with_state, _tool_args, state) do
      {:ok, Map.put(state, :tool_call_modified, true)}
    end

    def handle_tool_call(:return_error, _tool_args, _state) do
      {:error, "Tool call failed"}
    end

    def handle_tool_call(:return_unexpected, _tool_args, _state) do
      :unexpected_response
    end

    def handle_tool_result(:return_ok, _tool_result, _state) do
      :ok
    end

    def handle_tool_result(:return_ok_with_state, _tool_result, state) do
      {:ok, Map.put(state, :tool_result_modified, true)}
    end

    def handle_tool_result(:return_error, _tool_result, _state) do
      {:error, "Tool result handling failed"}
    end

    def handle_tool_result(:return_unexpected, _tool_result, _state) do
      :unexpected_response
    end
  end

  defmodule MockAgentExceptions do
    def handle_stage_start(_node_def, _state) do
      raise RuntimeError, "Stage start callback failed"
    end

    def handle_tool_call(_tool_name, _tool_args, _state) do
      raise RuntimeError, "Tool call callback failed"
    end

    def handle_tool_result(_tool_name, _tool_result, _state) do
      raise RuntimeError, "Tool result callback failed"
    end
  end

  describe "call_stage_start/3" do
    test "returns {:ok, agent_state} when agent_module is nil" do
      initial_state = %{existing: "value"}

      assert {:ok, ^initial_state} = AgentCallbacks.call_stage_start(nil, %{}, initial_state)
    end

    test "calls handle_stage_start on agent module and returns result" do
      node_def = %{name: :test_stage}
      initial_state = %{counter: 0}

      assert {:ok, result_state} =
               AgentCallbacks.call_stage_start(MockAgentSuccess, node_def, initial_state)

      assert result_state.stage_started == true
      assert result_state.counter == 0
    end

    test "handles exceptions in handle_stage_start gracefully" do
      node_def = %{name: :test_stage}
      initial_state = %{counter: 0}

      log =
        capture_log(fn ->
          assert {:ok, ^initial_state} =
                   AgentCallbacks.call_stage_start(MockAgentExceptions, node_def, initial_state)
        end)

      assert log =~ "Agent callback handle_stage_start failed"
      assert log =~ "RuntimeError"
    end

    test "preserves original state when callback raises exception" do
      node_def = %{name: :test_stage}
      initial_state = %{important: "data", nested: %{value: 42}}

      capture_log(fn ->
        assert {:ok, result_state} =
                 AgentCallbacks.call_stage_start(MockAgentExceptions, node_def, initial_state)

        assert result_state == initial_state
      end)
    end
  end

  describe "call_tool_call/4" do
    test "returns {:ok, agent_state} when agent_module is nil" do
      initial_state = %{existing: "value"}

      assert {:ok, ^initial_state} =
               AgentCallbacks.call_tool_call(nil, :test_tool, %{}, initial_state)
    end

    test "handles :ok response from agent module" do
      initial_state = %{counter: 0}

      assert {:ok, ^initial_state} =
               AgentCallbacks.call_tool_call(
                 MockAgentVariousResponses,
                 :return_ok,
                 %{arg: "value"},
                 initial_state
               )
    end

    test "handles {:ok, new_state} response from agent module" do
      initial_state = %{counter: 0}

      assert {:ok, result_state} =
               AgentCallbacks.call_tool_call(
                 MockAgentVariousResponses,
                 :return_ok_with_state,
                 %{arg: "value"},
                 initial_state
               )

      assert result_state.tool_call_modified == true
      assert result_state.counter == 0
    end

    test "handles {:error, reason} response from agent module" do
      initial_state = %{counter: 0}

      assert {:error, ^initial_state} =
               AgentCallbacks.call_tool_call(
                 MockAgentVariousResponses,
                 :return_error,
                 %{arg: "value"},
                 initial_state
               )
    end

    test "handles unexpected response from agent module" do
      initial_state = %{counter: 0}

      log =
        capture_log(fn ->
          assert {:ok, ^initial_state} =
                   AgentCallbacks.call_tool_call(
                     MockAgentVariousResponses,
                     :return_unexpected,
                     %{arg: "value"},
                     initial_state
                   )
        end)

      assert log =~ "Unexpected handle_tool_call result"
      assert log =~ ":unexpected_response"
    end

    test "handles exceptions in handle_tool_call gracefully" do
      initial_state = %{counter: 0}

      log =
        capture_log(fn ->
          assert {:ok, ^initial_state} =
                   AgentCallbacks.call_tool_call(
                     MockAgentExceptions,
                     :test_tool,
                     %{arg: "value"},
                     initial_state
                   )
        end)

      assert log =~ "Agent callback handle_tool_call failed"
      assert log =~ "RuntimeError"
    end

    test "preserves original state when callback raises exception" do
      initial_state = %{important: "data", nested: %{value: 42}}

      capture_log(fn ->
        assert {:ok, result_state} =
                 AgentCallbacks.call_tool_call(
                   MockAgentExceptions,
                   :test_tool,
                   %{},
                   initial_state
                 )

        assert result_state == initial_state
      end)
    end
  end

  describe "call_tool_result/4" do
    test "returns {:ok, agent_state} when agent_module is nil" do
      initial_state = %{existing: "value"}

      assert {:ok, ^initial_state} =
               AgentCallbacks.call_tool_result(
                 nil,
                 :test_tool,
                 {:ok, "result"},
                 initial_state
               )
    end

    test "handles :ok response from agent module" do
      initial_state = %{counter: 0}

      assert {:ok, ^initial_state} =
               AgentCallbacks.call_tool_result(
                 MockAgentVariousResponses,
                 :return_ok,
                 {:ok, "result"},
                 initial_state
               )
    end

    test "handles {:ok, new_state} response from agent module" do
      initial_state = %{counter: 0}

      assert {:ok, result_state} =
               AgentCallbacks.call_tool_result(
                 MockAgentVariousResponses,
                 :return_ok_with_state,
                 {:ok, "result"},
                 initial_state
               )

      assert result_state.tool_result_modified == true
      assert result_state.counter == 0
    end

    test "handles {:error, reason} response from agent module" do
      initial_state = %{counter: 0}

      assert {:error, ^initial_state} =
               AgentCallbacks.call_tool_result(
                 MockAgentVariousResponses,
                 :return_error,
                 {:error, "tool failed"},
                 initial_state
               )
    end

    test "handles unexpected response from agent module" do
      initial_state = %{counter: 0}

      log =
        capture_log(fn ->
          assert {:ok, ^initial_state} =
                   AgentCallbacks.call_tool_result(
                     MockAgentVariousResponses,
                     :return_unexpected,
                     {:ok, "result"},
                     initial_state
                   )
        end)

      assert log =~ "Unexpected handle_tool_result result"
      assert log =~ ":unexpected_response"
    end

    test "handles exceptions in handle_tool_result gracefully" do
      initial_state = %{counter: 0}

      log =
        capture_log(fn ->
          assert {:ok, ^initial_state} =
                   AgentCallbacks.call_tool_result(
                     MockAgentExceptions,
                     :test_tool,
                     {:ok, "result"},
                     initial_state
                   )
        end)

      assert log =~ "Agent callback handle_tool_result failed"
      assert log =~ "RuntimeError"
    end

    test "preserves original state when callback raises exception" do
      initial_state = %{important: "data", nested: %{value: 42}}

      capture_log(fn ->
        assert {:ok, result_state} =
                 AgentCallbacks.call_tool_result(
                   MockAgentExceptions,
                   :test_tool,
                   {:error, "failed"},
                   initial_state
                 )

        assert result_state == initial_state
      end)
    end

    test "handles different types of tool results" do
      initial_state = %{counter: 0}

      # Test with success result
      assert {:ok, success_state} =
               AgentCallbacks.call_tool_result(
                 MockAgentSuccess,
                 :test_tool,
                 {:ok, %{data: "success"}},
                 initial_state
               )

      assert success_state.tool_result_handled == true

      # Test with error result
      assert {:ok, error_state} =
               AgentCallbacks.call_tool_result(
                 MockAgentSuccess,
                 :test_tool,
                 {:error, "tool execution failed"},
                 initial_state
               )

      assert error_state.tool_result_handled == true
    end
  end

  describe "update_agent_state_from_callback/3" do
    test "returns new_state when status is :ok" do
      new_state = %{updated: true, value: 42}
      fallback_state = %{original: true, value: 0}

      result = AgentCallbacks.update_agent_state_from_callback(:ok, new_state, fallback_state)
      assert result == new_state
    end

    test "returns fallback_state when status is :error" do
      new_state = %{updated: true, value: 42}
      fallback_state = %{original: true, value: 0}

      result = AgentCallbacks.update_agent_state_from_callback(:error, new_state, fallback_state)
      assert result == fallback_state
    end

    test "returns fallback_state when status is {:error, reason}" do
      new_state = %{updated: true, value: 42}
      fallback_state = %{original: true, value: 0}

      result =
        AgentCallbacks.update_agent_state_from_callback(
          {:error, "failed"},
          new_state,
          fallback_state
        )

      assert result == fallback_state
    end

    test "returns fallback_state when status is any other value" do
      new_state = %{updated: true, value: 42}
      fallback_state = %{original: true, value: 0}

      result =
        AgentCallbacks.update_agent_state_from_callback(
          :unknown_status,
          new_state,
          fallback_state
        )

      assert result == fallback_state

      result2 = AgentCallbacks.update_agent_state_from_callback(nil, new_state, fallback_state)
      assert result2 == fallback_state

      result3 =
        AgentCallbacks.update_agent_state_from_callback(
          {:some, :tuple},
          new_state,
          fallback_state
        )

      assert result3 == fallback_state
    end

    test "handles nil states correctly" do
      # When new_state is nil but status is :ok
      result = AgentCallbacks.update_agent_state_from_callback(:ok, nil, %{fallback: true})
      assert result == nil

      # When fallback_state is nil and status is not :ok
      result2 = AgentCallbacks.update_agent_state_from_callback(:error, %{new: true}, nil)
      assert result2 == nil
    end

    test "preserves complex state structures" do
      complex_new_state = %{
        user: %{id: 123, name: "John"},
        settings: %{theme: "dark", notifications: true},
        data: [1, 2, 3, %{nested: "value"}]
      }

      complex_fallback_state = %{
        user: %{id: 456, name: "Jane"},
        settings: %{theme: "light", notifications: false},
        data: [4, 5, 6]
      }

      # Should return complex new state when :ok
      result =
        AgentCallbacks.update_agent_state_from_callback(
          :ok,
          complex_new_state,
          complex_fallback_state
        )

      assert result == complex_new_state
      assert result.user.id == 123

      # Should return complex fallback state when not :ok
      result2 =
        AgentCallbacks.update_agent_state_from_callback(
          :error,
          complex_new_state,
          complex_fallback_state
        )

      assert result2 == complex_fallback_state
      assert result2.user.id == 456
    end
  end

  describe "integration scenarios" do
    test "complete workflow with successful agent callbacks" do
      initial_state = %{workflow_step: 0}
      node_def = %{name: :integration_test}
      tool_name = :test_integration_tool
      tool_args = %{action: "process"}
      tool_result = {:ok, "processed successfully"}

      # Step 1: Stage start
      {:ok, state_after_start} =
        AgentCallbacks.call_stage_start(MockAgentSuccess, node_def, initial_state)

      assert state_after_start.stage_started == true

      # Step 2: Tool call
      {:ok, state_after_tool_call} =
        AgentCallbacks.call_tool_call(
          MockAgentSuccess,
          tool_name,
          tool_args,
          state_after_start
        )

      assert state_after_tool_call.tool_called == true
      assert state_after_tool_call.stage_started == true

      # Step 3: Tool result
      {:ok, final_state} =
        AgentCallbacks.call_tool_result(
          MockAgentSuccess,
          tool_name,
          tool_result,
          state_after_tool_call
        )

      assert final_state.tool_result_handled == true
      assert final_state.tool_called == true
      assert final_state.stage_started == true
    end

    test "workflow with mixed success and failure responses" do
      initial_state = %{step: 1}

      # Successful stage start
      {:ok, state1} = AgentCallbacks.call_stage_start(MockAgentSuccess, %{}, initial_state)

      # Failed tool call
      {:error, state2} =
        AgentCallbacks.call_tool_call(
          MockAgentVariousResponses,
          :return_error,
          %{},
          state1
        )

      # State should be preserved from before the failed tool call
      assert state2 == state1
      assert state2.stage_started == true

      # Successful tool result handling  
      {:ok, final_state} =
        AgentCallbacks.call_tool_result(
          MockAgentSuccess,
          :recovery_tool,
          {:ok, "recovered"},
          state2
        )

      assert final_state.tool_result_handled == true
      assert final_state.stage_started == true
    end
  end
end
