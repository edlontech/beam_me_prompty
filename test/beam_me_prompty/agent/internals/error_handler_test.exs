defmodule BeamMePrompty.Agent.Internals.ErrorHandlerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.AgentSpec
  alias BeamMePrompty.Agent.Internals.BatchManager
  alias BeamMePrompty.Agent.Internals.ErrorHandler
  alias BeamMePrompty.Agent.Internals.ResultManager
  alias BeamMePrompty.Agent.Internals.StateManager
  alias BeamMePrompty.Errors

  setup :verify_on_exit!

  describe "handle_execution_error/2" do
    setup do
      agent_spec = %AgentSpec{
        stages: [],
        memory_sources: [],
        agent_config: %{name: "Mock Agent", version: "1.0"},
        callback_module: MockAgent
      }

      data = %{
        agent_spec: agent_spec,
        session_id: "test_session_123",
        current_state: %{some: "state"},
        result_manager: ResultManager.new(),
        batch_manager: BatchManager.new(),
        nodes_to_execute: [:node1, :node2]
      }

      %{data: data}
    end

    test "handles retry response from agent error callback", %{data: data} do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      new_agent_state = %{retry: "state"}

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, error_class, current_state ->
          assert agent_spec.callback_module == MockAgent
          assert is_struct(error_class, Errors.Framework)
          assert current_state == data.current_state
          {:retry, new_agent_state}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:next_state, :waiting_for_plan, reset_data, [{:next_event, :internal, :plan}]} =
                 result

        # Verify the data was reset properly for retry
        assert reset_data.current_state == new_agent_state
        assert reset_data.nodes_to_execute == []
        assert %BatchManager{} = reset_data.batch_manager
        assert %ResultManager{} = reset_data.result_manager
      end)
    end

    test "handles stop response from agent error callback", %{data: data} do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      stop_reason = "agent decided to stop"

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, _error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          {:stop, stop_reason}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:agent_stopped_execution, ^stop_reason}, ^data} = result
      end)
    end

    test "handles restart response from agent error callback", %{data: data} do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      restart_reason = "timeout occurred, restart needed"

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, _error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          {:restart, restart_reason}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:restart_requested, ^restart_reason}, ^data} = result
      end)
    end

    test "handles unexpected response from agent error callback", %{data: data} do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      unexpected_response = {:unknown, "what is this?"}

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, _error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          unexpected_response
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:unexpected_handle_error_response, ^unexpected_response}, ^data} = result
      end)
    end

    test "handles error callback failure", %{data: data} do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      callback_error = {:error, "callback crashed"}

      expect(StateManager, :safe_execute, fn _fun, _description ->
        {:error, callback_error}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:error_callback_failed, ^callback_error}, ^data} = result
      end)
    end
  end

  describe "handle_stage_error/3" do
    test "creates ExecutionError and delegates to handle_execution_error" do
      error_reason = "stage timeout"

      agent_spec = %AgentSpec{
        stages: [],
        memory_sources: [],
        agent_config: %{name: "Mock Agent", version: "1.0"},
        callback_module: MockAgent
      }

      data = %{
        agent_spec: agent_spec,
        session_id: "test_session",
        current_state: %{},
        result_manager: ResultManager.new(),
        batch_manager: BatchManager.new(),
        nodes_to_execute: [:node1]
      }

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          assert is_struct(error_class, Errors.Framework)
          {:stop, "stage failed"}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_stage_error(:some_stage, error_reason, data)

        assert {:stop, {:agent_stopped_execution, "stage failed"}, cleaned_data} = result

        # Verify batch state was cleared
        assert %BatchManager{} = cleaned_data.batch_manager
        assert cleaned_data.nodes_to_execute == []
      end)
    end
  end

  describe "handle_planning_error/1" do
    test "creates planning ExecutionError and delegates to handle_execution_error" do
      agent_spec = %AgentSpec{
        stages: [],
        memory_sources: [],
        agent_config: %{name: "Mock Agent", version: "1.0"},
        callback_module: MockAgent
      }

      data = %{
        agent_spec: agent_spec,
        session_id: "planning_session",
        current_state: %{planning: true},
        result_manager: ResultManager.new(),
        batch_manager: BatchManager.new(),
        nodes_to_execute: []
      }

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          assert is_struct(error_class, Errors.Framework)
          [error | _] = error_class.errors

          assert error.stage == :waiting_for_plan
          assert error.cause == "No nodes are ready to execute after agent's handle_plan"
          {:retry, %{new: "state"}}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_planning_error(data)

        assert {:next_state, :waiting_for_plan, _reset_data, [{:next_event, :internal, :plan}]} =
                 result
      end)
    end
  end

  describe "handle_supervisor_error/1" do
    test "returns stop tuple with supervisor error reason" do
      reason = {:shutdown, :supervisor_init_failed}

      capture_log(fn ->
        result = ErrorHandler.handle_supervisor_error(reason)

        assert {:stop, {:failed_to_start_stages_supervisor, ^reason}} = result
      end)
    end
  end

  describe "handle_stage_worker_error/2" do
    test "raises Framework exception" do
      node_name = :worker_node
      reason = {:error, :worker_init_failed}

      capture_log(fn ->
        assert_raise BeamMePrompty.Errors.ExecutionError, fn ->
          ErrorHandler.handle_stage_worker_error(node_name, reason)
        end
      end)
    end
  end

  describe "handle_unexpected_event/4" do
    test "returns :keep_state_and_data and logs warning" do
      agent_spec = %AgentSpec{
        stages: [],
        memory_sources: [],
        agent_config: %{name: "Mock Agent", version: "1.0"},
        callback_module: MockAgent
      }

      data = %{
        agent_spec: agent_spec,
        session_id: "unexpected_session"
      }

      capture_log(fn ->
        result =
          ErrorHandler.handle_unexpected_event(
            :some_state,
            :weird_event,
            %{unexpected: "content"},
            data
          )

        assert result == :keep_state_and_data
      end)
    end
  end

  describe "private functions integration tests" do
    test "reset_for_retry preserves core configuration but clears execution state" do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      agent_spec = %AgentSpec{
        stages: [],
        memory_sources: [],
        agent_config: %{},
        callback_module: MockAgent
      }

      original_data = %{
        agent_spec: agent_spec,
        session_id: "test_session",
        current_state: %{old: "state"},
        result_manager: ResultManager.new(),
        batch_manager: BatchManager.new(),
        nodes_to_execute: [:node1, :node2]
      }

      new_agent_state = %{new: "state"}

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, _error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          {:retry, new_agent_state}
      end)

      capture_log(fn ->
        {:next_state, :waiting_for_plan, reset_data, _actions} =
          ErrorHandler.handle_execution_error(error_detail, original_data)

        # Verify core configuration is preserved
        assert reset_data.agent_spec == original_data.agent_spec
        assert reset_data.session_id == original_data.session_id
        assert %ResultManager{} = reset_data.result_manager

        # Verify state was updated
        assert reset_data.current_state == new_agent_state

        # Verify execution state was cleared
        assert reset_data.nodes_to_execute == []
        assert %BatchManager{} = reset_data.batch_manager
      end)
    end

    test "clear_batch_state clears batch-specific fields" do
      agent_spec = %AgentSpec{
        stages: [],
        memory_sources: [],
        agent_config: %{name: "Mock Agent", version: "1.0"},
        callback_module: MockAgent
      }

      original_data = %{
        agent_spec: agent_spec,
        session_id: "test_session",
        current_state: %{preserved: "state"},
        result_manager: ResultManager.new(),
        batch_manager: BatchManager.new(),
        nodes_to_execute: [:node1, :node2]
      }

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        agent_spec, _error_class, _current_state ->
          assert agent_spec.callback_module == MockAgent
          {:stop, "batch failed"}
      end)

      capture_log(fn ->
        {:stop, _reason, cleaned_data} =
          ErrorHandler.handle_stage_error(:test_node, "test error", original_data)

        assert cleaned_data.agent_spec == original_data.agent_spec
        assert cleaned_data.session_id == original_data.session_id
        assert cleaned_data.current_state == original_data.current_state
        assert cleaned_data.result_manager == original_data.result_manager

        # Verify batch state was cleared
        assert %BatchManager{} = cleaned_data.batch_manager
        assert cleaned_data.nodes_to_execute == []
      end)
    end
  end
end
