defmodule BeamMePrompty.Agent.Internals.StateManagerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.Internals.StateManager

  defmodule MockAgent do
    def handle_init(_dag, state), do: {:ok, state}
    def handle_plan(ready_nodes, state), do: {:ok, ready_nodes, state}
    def handle_batch_start(_nodes, state), do: {:ok, state}
    def handle_stage_finish(_stage_def, _result, state), do: {:ok, state}
    def handle_progress(_progress, state), do: {:ok, state}
    def handle_batch_complete(_results, _pending, state), do: {:ok, state}
    def handle_complete(_results, state), do: {:ok, state}
    def handle_error(_error, state), do: {:error, state}
  end

  defmodule MockAgentWithOverride do
    def handle_init(_dag, _state), do: {{:ok, :override_state}, :new_state}
    def handle_plan(ready_nodes, _state), do: {{:ok, :override_state}, ready_nodes, :new_state}
    def handle_batch_start(_nodes, _state), do: {{:ok, :override_state}, :new_state}
    def handle_stage_finish(_stage_def, _result, _state), do: {{:ok, :override_state}, :new_state}
    def handle_progress(_progress, _state), do: {{:ok, :override_state}, :new_state}

    def handle_batch_complete(_results, _pending, _state),
      do: {{:ok, :override_state}, :new_state}

    def handle_complete(_results, _state), do: {{:ok, :override_state}, :new_state}
    def handle_error(_error, state), do: {:error, state}
  end

  defmodule MockAgentWithError do
    def handle_init(_dag, state), do: {:error, state}
    def handle_plan(_ready_nodes, state), do: {:error, [], state}
    def handle_batch_start(_nodes, state), do: {:error, state}
    def handle_stage_finish(_stage_def, _result, state), do: {:error, state}
    def handle_progress(_progress, state), do: {:error, state}
    def handle_batch_complete(_results, _pending, state), do: {:error, state}
    def handle_complete(_results, state), do: {:error, state}
    def handle_error(_error, state), do: {:error, state}
  end

  defmodule MockAgentWithException do
    def handle_init(_dag, _state), do: raise("Test exception")
    def handle_plan(_ready_nodes, _state), do: raise("Test exception")
    def handle_batch_start(_nodes, _state), do: raise("Test exception")
    def handle_stage_finish(_stage_def, _result, _state), do: raise("Test exception")
    def handle_progress(_progress, _state), do: raise("Test exception")
    def handle_batch_complete(_results, _pending, _state), do: raise("Test exception")
    def handle_complete(_results, _state), do: raise("Test exception")
    def handle_error(_error, _state), do: raise("Test exception")
  end

  describe "handle_callback_response/2" do
    test "returns new state when status is :ok" do
      result = StateManager.handle_callback_response({:ok, "new_state"}, "current_state")
      assert result == "new_state"
    end

    test "returns overridden state when status is {:ok, override}" do
      result =
        StateManager.handle_callback_response(
          {{:ok, "override_state"}, "new_state"},
          "current_state"
        )

      assert result == "override_state"
    end

    test "returns current state when status is error" do
      result = StateManager.handle_callback_response({:error, "new_state"}, "current_state")
      assert result == "current_state"
    end

    test "returns current state for any other status" do
      result = StateManager.handle_callback_response({:unknown, "new_state"}, "current_state")
      assert result == "current_state"
    end
  end

  describe "execute_init_callback/3" do
    test "executes successful init callback" do
      dag = %{}
      initial_state = "initial"

      {status, final_state} = StateManager.execute_init_callback(MockAgent, dag, initial_state)

      assert status == :ok
      assert final_state == initial_state
    end

    test "handles init callback with override" do
      dag = %{}
      initial_state = "initial"

      {status, final_state} =
        StateManager.execute_init_callback(MockAgentWithOverride, dag, initial_state)

      assert status == {:ok, :override_state}
      assert final_state == :override_state
    end

    test "handles init callback with error" do
      dag = %{}
      initial_state = "initial"

      {status, final_state} =
        StateManager.execute_init_callback(MockAgentWithError, dag, initial_state)

      assert status == :error
      assert final_state == initial_state
    end
  end

  describe "execute_plan_callback/3" do
    test "executes successful plan callback" do
      ready_nodes = [:node1, :node2]
      current_state = "current"

      {status, planned_nodes, final_state} =
        StateManager.execute_plan_callback(MockAgent, ready_nodes, current_state)

      assert status == :ok
      assert planned_nodes == ready_nodes
      assert final_state == current_state
    end

    test "handles plan callback with override" do
      ready_nodes = [:node1, :node2]
      current_state = "current"

      {status, planned_nodes, final_state} =
        StateManager.execute_plan_callback(MockAgentWithOverride, ready_nodes, current_state)

      assert status == {:ok, :override_state}
      assert planned_nodes == ready_nodes
      assert final_state == :override_state
    end

    test "handles plan callback with error" do
      ready_nodes = [:node1, :node2]
      current_state = "current"

      {status, planned_nodes, final_state} =
        StateManager.execute_plan_callback(MockAgentWithError, ready_nodes, current_state)

      assert status == :error
      assert planned_nodes == []
      assert final_state == current_state
    end
  end

  describe "execute_batch_start_callback/3" do
    test "executes successful batch start callback" do
      nodes_to_execute = [{:node1, %{}}, {:node2, %{}}]
      current_state = "current"

      {status, final_state} =
        StateManager.execute_batch_start_callback(MockAgent, nodes_to_execute, current_state)

      assert status == :ok
      assert final_state == current_state
    end

    test "handles batch start callback with override" do
      nodes_to_execute = [{:node1, %{}}, {:node2, %{}}]
      current_state = "current"

      {status, final_state} =
        StateManager.execute_batch_start_callback(
          MockAgentWithOverride,
          nodes_to_execute,
          current_state
        )

      assert status == {:ok, :override_state}
      assert final_state == :override_state
    end

    test "handles batch start callback with error" do
      nodes_to_execute = [{:node1, %{}}, {:node2, %{}}]
      current_state = "current"

      {status, final_state} =
        StateManager.execute_batch_start_callback(
          MockAgentWithError,
          nodes_to_execute,
          current_state
        )

      assert status == :error
      assert final_state == current_state
    end
  end

  describe "execute_stage_finish_callback/4" do
    test "executes successful stage finish callback" do
      stage_definition = %{name: :test_stage}
      stage_result = %{success: true}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_stage_finish_callback(
          MockAgent,
          stage_definition,
          stage_result,
          current_state
        )

      assert status == :ok
      assert final_state == current_state
    end

    test "handles stage finish callback with override" do
      stage_definition = %{name: :test_stage}
      stage_result = %{success: true}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_stage_finish_callback(
          MockAgentWithOverride,
          stage_definition,
          stage_result,
          current_state
        )

      assert status == {:ok, :override_state}
      assert final_state == :override_state
    end

    test "handles stage finish callback with error" do
      stage_definition = %{name: :test_stage}
      stage_result = %{success: false}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_stage_finish_callback(
          MockAgentWithError,
          stage_definition,
          stage_result,
          current_state
        )

      assert status == :error
      assert final_state == current_state
    end
  end

  describe "execute_progress_callback/3" do
    test "executes successful progress callback" do
      progress_info = %{completed: 5, total: 10}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_progress_callback(MockAgent, progress_info, current_state)

      assert status == :ok
      assert final_state == current_state
    end

    test "handles progress callback with override" do
      progress_info = %{completed: 5, total: 10}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_progress_callback(
          MockAgentWithOverride,
          progress_info,
          current_state
        )

      assert status == {:ok, :override_state}
      assert final_state == :override_state
    end

    test "handles progress callback with error" do
      progress_info = %{completed: 5, total: 10}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_progress_callback(MockAgentWithError, progress_info, current_state)

      assert status == :error
      assert final_state == current_state
    end
  end

  describe "execute_batch_complete_callback/4" do
    test "executes successful batch complete callback" do
      batch_results = %{node1: :success, node2: :success}
      pending_nodes = [:node3, :node4]
      current_state = "current"

      {status, final_state} =
        StateManager.execute_batch_complete_callback(
          MockAgent,
          batch_results,
          pending_nodes,
          current_state
        )

      assert status == :ok
      assert final_state == current_state
    end

    test "handles batch complete callback with override" do
      batch_results = %{node1: :success, node2: :success}
      pending_nodes = [:node3, :node4]
      current_state = "current"

      {status, final_state} =
        StateManager.execute_batch_complete_callback(
          MockAgentWithOverride,
          batch_results,
          pending_nodes,
          current_state
        )

      assert status == {:ok, :override_state}
      assert final_state == :override_state
    end

    test "handles batch complete callback with error" do
      batch_results = %{node1: :error, node2: :success}
      pending_nodes = [:node3, :node4]
      current_state = "current"

      {status, final_state} =
        StateManager.execute_batch_complete_callback(
          MockAgentWithError,
          batch_results,
          pending_nodes,
          current_state
        )

      assert status == :error
      assert final_state == current_state
    end
  end

  describe "execute_complete_callback/3" do
    test "executes successful complete callback" do
      final_results = %{total_nodes: 5, successful: 5, failed: 0}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_complete_callback(MockAgent, final_results, current_state)

      assert status == :ok
      assert final_state == current_state
    end

    test "handles complete callback with override" do
      final_results = %{total_nodes: 5, successful: 5, failed: 0}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_complete_callback(
          MockAgentWithOverride,
          final_results,
          current_state
        )

      assert status == {:ok, :override_state}
      assert final_state == :override_state
    end

    test "handles complete callback with error" do
      final_results = %{total_nodes: 5, successful: 3, failed: 2}
      current_state = "current"

      {status, final_state} =
        StateManager.execute_complete_callback(MockAgentWithError, final_results, current_state)

      assert status == :error
      assert final_state == current_state
    end
  end

  describe "execute_error_callback/3" do
    test "executes error callback" do
      error_class = :timeout_error
      current_state = "current"

      result = StateManager.execute_error_callback(MockAgent, error_class, current_state)

      assert result == {:error, current_state}
    end

    test "handles error callback that raises exception" do
      error_class = :critical_error
      current_state = "current"

      assert_raise RuntimeError, "Test exception", fn ->
        StateManager.execute_error_callback(MockAgentWithException, error_class, current_state)
      end
    end
  end

  describe "safe_execute/2" do
    test "executes function successfully" do
      callback_fn = fn -> {:success, "result"} end

      result = StateManager.safe_execute(callback_fn, "test_context")

      assert result == {:ok, {:success, "result"}}
    end

    test "handles function that raises exception" do
      callback_fn = fn -> raise("Test error") end

      capture_log(fn ->
        result = StateManager.safe_execute(callback_fn, "test_context")

        assert {:error,
                %BeamMePrompty.Errors.ExecutionError{
                  cause: %RuntimeError{message: "Test error", __exception__: true},
                  path: []
                }} = result
      end)
    end

    test "handles function that throws value" do
      callback_fn = fn -> throw("thrown_value") end

      capture_log(fn ->
        result = StateManager.safe_execute(callback_fn, "test_context")

        assert {:error,
                %BeamMePrompty.Errors.ExecutionError{
                  cause: "thrown_value",
                  path: []
                }} = result
      end)
    end
  end
end
