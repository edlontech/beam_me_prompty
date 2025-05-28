defmodule BeamMePrompty.Agent.Internals.ErrorHandlerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.Internals.ErrorHandler
  alias BeamMePrompty.Agent.Internals.ResultManager
  alias BeamMePrompty.Agent.Internals.StateManager
  alias BeamMePrompty.Errors

  setup :verify_on_exit!

  describe "handle_execution_error/2" do
    setup do
      data = %{
        agent_module: MockAgent,
        session_id: "test_session_123",
        current_state: %{some: "state"},
        result_manager: ResultManager.new(),
        nodes_to_execute: [:node1, :node2],
        pending_nodes: [:node3],
        current_batch_details: %{batch_id: 1},
        temp_batch_results: %{node1: :result1}
      }

      %{data: data}
    end

    test "handles retry response from agent error callback", %{data: data} do
      error_detail = %Errors.ExecutionError{
        stage: :some_stage,
        cause: "Test error"
      }

      new_agent_state = %{retry: "state"}

      # Mock StateManager functions
      expect(StateManager, :safe_execute, fn fun, _description ->
        # Simulate successful callback execution
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, error_class, current_state ->
          assert is_struct(error_class, Errors.ExecutionError)
          assert current_state == data.current_state
          {:retry, new_agent_state}
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{stage: :some_stage, cause: "Test error"}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:next_state, :waiting_for_plan, reset_data, [{:next_event, :internal, :plan}]} =
                 result

        # Verify the data was reset properly for retry
        assert reset_data.current_state == new_agent_state
        assert reset_data.nodes_to_execute == []
        assert reset_data.pending_nodes == []
        assert reset_data.current_batch_details == %{}
        assert reset_data.temp_batch_results == %{}
        assert %ResultManager{} = reset_data.result_manager
      end)
    end

    test "handles stop response from agent error callback", %{data: data} do
      error_detail = "simple error string"
      stop_reason = "agent decided to stop"

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, _error_class, _current_state ->
          {:stop, stop_reason}
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{cause: "simple error string"}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:agent_stopped_execution, ^stop_reason}, ^data} = result
      end)
    end

    test "handles restart response from agent error callback", %{data: data} do
      error_detail = {:error, :timeout}
      restart_reason = "timeout occurred, restart needed"

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, _error_class, _current_state ->
          {:restart, restart_reason}
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{cause: "timeout"}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:restart_requested, ^restart_reason}, ^data} = result
      end)
    end

    test "handles unexpected response from agent error callback", %{data: data} do
      error_detail = %{custom: "error"}
      unexpected_response = {:unknown, "what is this?"}

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, _error_class, _current_state ->
          unexpected_response
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{cause: "custom error"}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:unexpected_handle_error_response, ^unexpected_response}, ^data} = result
      end)
    end

    test "handles error callback failure", %{data: data} do
      error_detail = "original error"
      callback_error = {:error, "callback crashed"}

      expect(StateManager, :safe_execute, fn _fun, _description ->
        {:error, callback_error}
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{cause: "original error"}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_execution_error(error_detail, data)

        assert {:stop, {:error_callback_failed, ^callback_error}, ^data} = result
      end)
    end
  end

  describe "handle_stage_error/3" do
    test "creates ExecutionError and delegates to handle_execution_error" do
      node_name = :failed_node
      error_reason = "stage timeout"

      data = %{
        agent_module: MockAgent,
        session_id: "test_session",
        current_state: %{},
        result_manager: ResultManager.new(),
        nodes_to_execute: [:node1],
        pending_nodes: [:node2],
        current_batch_details: %{batch_id: 1},
        temp_batch_results: %{node1: :result}
      }

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, error_class, _current_state ->
          assert is_struct(error_class, Errors.ExecutionError)
          assert error_class.stage == node_name
          assert error_class.cause == error_reason
          {:stop, "stage failed"}
      end)

      expect(Errors.ExecutionError, :exception, fn opts ->
        %Errors.ExecutionError{
          stage: opts[:stage],
          cause: opts[:cause]
        }
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{stage: node_name, cause: error_reason}
      end)

      capture_log(fn ->
        result = ErrorHandler.handle_stage_error(node_name, error_reason, data)

        assert {:stop, {:agent_stopped_execution, "stage failed"}, cleaned_data} = result

        # Verify batch state was cleared
        assert cleaned_data.temp_batch_results == %{}
        assert cleaned_data.pending_nodes == []
        assert cleaned_data.current_batch_details == %{}
        assert cleaned_data.nodes_to_execute == []
      end)
    end
  end

  describe "handle_planning_error/1" do
    test "creates planning ExecutionError and delegates to handle_execution_error" do
      data = %{
        agent_module: MockAgent,
        session_id: "planning_session",
        current_state: %{planning: true},
        result_manager: ResultManager.new(),
        nodes_to_execute: [],
        pending_nodes: [],
        current_batch_details: %{},
        temp_batch_results: %{}
      }

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, error_class, _current_state ->
          assert is_struct(error_class, Errors.ExecutionError)
          assert error_class.stage == :waiting_for_plan
          assert error_class.cause == "No nodes are ready to execute after agent's handle_plan"
          {:retry, %{new: "state"}}
      end)

      expect(Errors.ExecutionError, :exception, fn opts ->
        %Errors.ExecutionError{
          stage: opts[:stage],
          cause: opts[:cause]
        }
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{
          stage: :waiting_for_plan,
          cause: "No nodes are ready to execute after agent's handle_plan"
        }
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

      expect(BeamMePrompty.Errors.ExecutionError, :exception, fn _opts ->
        %BeamMePrompty.Errors.ExecutionError{
          cause: "Failed to start stage worker for #{node_name}: #{inspect(reason)}"
        }
      end)

      capture_log(fn ->
        assert_raise BeamMePrompty.Errors.ExecutionError, fn ->
          ErrorHandler.handle_stage_worker_error(node_name, reason)
        end
      end)
    end
  end

  describe "handle_unexpected_event/4" do
    test "returns :keep_state_and_data and logs warning" do
      data = %{
        agent_module: MockAgent,
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
      original_data = %{
        agent_module: MockAgent,
        session_id: "test_session",
        current_state: %{old: "state"},
        result_manager: ResultManager.new(),
        nodes_to_execute: [:node1, :node2],
        pending_nodes: [:node3],
        current_batch_details: %{batch_id: 1},
        temp_batch_results: %{node1: :result1}
      }

      new_agent_state = %{new: "state"}

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, _error_class, _current_state ->
          {:retry, new_agent_state}
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{cause: "test"}
      end)

      capture_log(fn ->
        {:next_state, :waiting_for_plan, reset_data, _actions} =
          ErrorHandler.handle_execution_error("test error", original_data)

        # Verify core configuration is preserved
        assert reset_data.agent_module == original_data.agent_module
        assert reset_data.session_id == original_data.session_id
        assert %ResultManager{} = reset_data.result_manager

        # Verify state was updated
        assert reset_data.current_state == new_agent_state

        # Verify execution state was cleared
        assert reset_data.nodes_to_execute == []
        assert reset_data.pending_nodes == []
        assert reset_data.current_batch_details == %{}
        assert reset_data.temp_batch_results == %{}
      end)
    end

    test "clear_batch_state clears batch-specific fields" do
      original_data = %{
        agent_module: MockAgent,
        session_id: "test_session",
        current_state: %{preserved: "state"},
        result_manager: ResultManager.new(),
        nodes_to_execute: [:node1, :node2],
        pending_nodes: [:node3],
        current_batch_details: %{batch_id: 1},
        temp_batch_results: %{node1: :result1}
      }

      expect(StateManager, :safe_execute, fn fun, _description ->
        result = fun.()
        {:ok, result}
      end)

      expect(StateManager, :execute_error_callback, fn
        MockAgent, _error_class, _current_state ->
          {:stop, "batch failed"}
      end)

      expect(Errors.ExecutionError, :exception, fn _opts ->
        %Errors.ExecutionError{stage: :test_node, cause: "test error"}
      end)

      expect(Errors, :to_class, fn _error_detail ->
        %Errors.ExecutionError{stage: :test_node, cause: "test error"}
      end)

      capture_log(fn ->
        {:stop, _reason, cleaned_data} =
          ErrorHandler.handle_stage_error(:test_node, "test error", original_data)

        assert cleaned_data.agent_module == original_data.agent_module
        assert cleaned_data.session_id == original_data.session_id
        assert cleaned_data.current_state == original_data.current_state
        assert cleaned_data.result_manager == original_data.result_manager

        assert cleaned_data.temp_batch_results == %{}
        assert cleaned_data.pending_nodes == []
        assert cleaned_data.current_batch_details == %{}
        assert cleaned_data.nodes_to_execute == []
      end)
    end
  end
end
