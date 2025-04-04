defmodule BeamMePrompty.Agent.Internals.ResultManagerTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Internals.ResultManager

  describe "new/0" do
    test "creates an empty result manager" do
      manager = ResultManager.new()

      assert manager.dag_results == %{}
      assert manager.previous_results == []
    end
  end

  describe "new/1" do
    test "creates result manager with initial results" do
      initial_results = %{node1: "result1", node2: "result2"}
      manager = ResultManager.new(initial_results)

      assert manager.dag_results == initial_results
      assert manager.previous_results == []
    end

    test "creates result manager with empty initial results" do
      manager = ResultManager.new(%{})

      assert manager.dag_results == %{}
      assert manager.previous_results == []
    end

    test "creates result manager with mixed key types" do
      initial_results = %{:atom_key => "value1", "string_key" => "value2"}
      manager = ResultManager.new(initial_results)

      assert manager.dag_results == initial_results
    end
  end

  describe "add_result/3" do
    test "adds result to empty manager" do
      manager = ResultManager.new()
      updated = ResultManager.add_result(manager, :node1, "success")

      assert updated.dag_results[:node1] == "success"
      assert map_size(updated.dag_results) == 1
    end

    test "adds result to manager with existing results" do
      manager = ResultManager.new(%{existing: "value"})
      updated = ResultManager.add_result(manager, :node1, "success")

      assert updated.dag_results[:node1] == "success"
      assert updated.dag_results[:existing] == "value"
      assert map_size(updated.dag_results) == 2
    end

    test "overwrites existing result" do
      manager = ResultManager.new(%{node1: "old_value"})
      updated = ResultManager.add_result(manager, :node1, "new_value")

      assert updated.dag_results[:node1] == "new_value"
      assert map_size(updated.dag_results) == 1
    end

    test "handles string node names" do
      manager = ResultManager.new()
      updated = ResultManager.add_result(manager, "string_node", "result")

      assert updated.dag_results["string_node"] == "result"
    end

    test "handles various result types" do
      manager = ResultManager.new()

      # Test different result types
      manager = ResultManager.add_result(manager, :string_result, "text")
      manager = ResultManager.add_result(manager, :number_result, 42)
      manager = ResultManager.add_result(manager, :list_result, [1, 2, 3])
      manager = ResultManager.add_result(manager, :map_result, %{key: "value"})
      manager = ResultManager.add_result(manager, :nil_result, nil)

      assert manager.dag_results[:string_result] == "text"
      assert manager.dag_results[:number_result] == 42
      assert manager.dag_results[:list_result] == [1, 2, 3]
      assert manager.dag_results[:map_result] == %{key: "value"}
      assert manager.dag_results[:nil_result] == nil
    end
  end

  describe "commit_batch_results/2" do
    test "commits batch to empty manager" do
      manager = ResultManager.new()
      batch = %{node1: "result1", node2: "result2"}
      updated = ResultManager.commit_batch_results(manager, batch)

      assert updated.dag_results == batch
    end

    test "merges batch with existing results" do
      manager = ResultManager.new(%{existing: "value"})
      batch = %{node1: "result1", node2: "result2"}
      updated = ResultManager.commit_batch_results(manager, batch)

      expected = %{existing: "value", node1: "result1", node2: "result2"}
      assert updated.dag_results == expected
    end

    test "overwrites existing keys with batch values" do
      manager = ResultManager.new(%{node1: "old_value", existing: "keep"})
      batch = %{node1: "new_value", node2: "result2"}
      updated = ResultManager.commit_batch_results(manager, batch)

      expected = %{node1: "new_value", existing: "keep", node2: "result2"}
      assert updated.dag_results == expected
    end

    test "commits empty batch" do
      manager = ResultManager.new(%{existing: "value"})
      updated = ResultManager.commit_batch_results(manager, %{})

      assert updated.dag_results == %{existing: "value"}
    end
  end

  describe "archive_current_results/1" do
    test "archives results and resets current" do
      manager = ResultManager.new(%{node1: "result1", node2: "result2"})
      archived = ResultManager.archive_current_results(manager)

      assert archived.dag_results == %{}
      assert length(archived.previous_results) == 1
      assert hd(archived.previous_results) == %{node1: "result1", node2: "result2"}
    end

    test "archives empty results" do
      manager = ResultManager.new()
      archived = ResultManager.archive_current_results(manager)

      assert archived.dag_results == %{}
      assert length(archived.previous_results) == 1
      assert hd(archived.previous_results) == %{}
    end

    test "preserves previous archives" do
      manager = ResultManager.new(%{first: "execution"})
      manager = ResultManager.archive_current_results(manager)
      manager = ResultManager.add_result(manager, :second, "execution")
      manager = ResultManager.archive_current_results(manager)

      assert manager.dag_results == %{}
      assert length(manager.previous_results) == 2
      assert manager.previous_results == [%{first: "execution"}, %{second: "execution"}]
    end
  end

  describe "get_result/2" do
    test "returns existing result" do
      manager = ResultManager.new(%{node1: "success", node2: 42})

      assert ResultManager.get_result(manager, :node1) == {:ok, "success"}
      assert ResultManager.get_result(manager, :node2) == {:ok, 42}
    end

    test "returns error for missing result" do
      manager = ResultManager.new(%{node1: "success"})

      assert ResultManager.get_result(manager, :missing) == :error
    end

    test "handles string node names" do
      manager = ResultManager.new(%{"string_node" => "result"})

      assert ResultManager.get_result(manager, "string_node") == {:ok, "result"}
    end

    test "returns nil result" do
      manager = ResultManager.new(%{nil_node: nil})

      assert ResultManager.get_result(manager, :nil_node) == :error
    end
  end

  describe "get_all_results/1" do
    test "returns all current results" do
      results = %{node1: "result1", node2: "result2"}
      manager = ResultManager.new(results)

      assert ResultManager.get_all_results(manager) == results
    end

    test "returns empty map for new manager" do
      manager = ResultManager.new()

      assert ResultManager.get_all_results(manager) == %{}
    end
  end

  describe "get_execution_history/1" do
    test "returns current execution with no history" do
      manager = ResultManager.new(%{current: "result"})
      history = ResultManager.get_execution_history(manager)

      assert history.current_execution == %{current: "result"}
      assert history.previous_executions == []
    end

    test "returns history with archived executions" do
      manager = ResultManager.new(%{first: "execution"})
      manager = ResultManager.archive_current_results(manager)
      manager = ResultManager.add_result(manager, :second, "execution")
      manager = ResultManager.archive_current_results(manager)
      manager = ResultManager.add_result(manager, :third, "execution")

      history = ResultManager.get_execution_history(manager)

      assert history.current_execution == %{third: "execution"}
      assert length(history.previous_executions) == 2
      assert history.previous_executions == [%{first: "execution"}, %{second: "execution"}]
    end
  end

  describe "has_results?/2" do
    test "returns true when all nodes have results" do
      manager = ResultManager.new(%{node1: "result1", node2: "result2", node3: "result3"})

      assert ResultManager.has_results?(manager, [:node1, :node2]) == true
      assert ResultManager.has_results?(manager, [:node1, :node2, :node3]) == true
    end

    test "returns false when some nodes missing" do
      manager = ResultManager.new(%{node1: "result1", node2: "result2"})

      assert ResultManager.has_results?(manager, [:node1, :missing]) == false
      assert ResultManager.has_results?(manager, [:missing1, :missing2]) == false
    end

    test "returns true for empty list" do
      manager = ResultManager.new(%{node1: "result1"})

      assert ResultManager.has_results?(manager, []) == true
    end

    test "handles mixed key types" do
      manager = ResultManager.new(%{:atom_key => "value1", "string_key" => "value2"})

      assert ResultManager.has_results?(manager, [:atom_key, "string_key"]) == true
      assert ResultManager.has_results?(manager, [:atom_key, "missing"]) == false
    end
  end

  describe "completed_count/1" do
    test "returns count of completed nodes" do
      manager = ResultManager.new(%{node1: "result1", node2: "result2"})

      assert ResultManager.completed_count(manager) == 2
    end

    test "returns zero for empty manager" do
      manager = ResultManager.new()

      assert ResultManager.completed_count(manager) == 0
    end

    test "counts nodes with nil results" do
      manager = ResultManager.new(%{node1: "result", node2: nil})

      assert ResultManager.completed_count(manager) == 2
    end
  end

  describe "clear_all/1" do
    test "clears all results and history" do
      manager = ResultManager.new(%{node1: "result1"})
      manager = ResultManager.archive_current_results(manager)
      manager = ResultManager.add_result(manager, :node2, "result2")

      cleared = ResultManager.clear_all(manager)

      assert cleared.dag_results == %{}
      assert cleared.previous_results == []
    end

    test "clearing already empty manager" do
      manager = ResultManager.new()
      cleared = ResultManager.clear_all(manager)

      assert cleared.dag_results == %{}
      assert cleared.previous_results == []
    end
  end

  describe "integration scenarios" do
    test "complete workflow with multiple operations" do
      # Start with initial results
      manager = ResultManager.new(%{initial: "value"})

      # Add individual results
      manager = ResultManager.add_result(manager, :step1, "completed")
      manager = ResultManager.add_result(manager, :step2, "completed")

      # Commit batch results
      batch = %{batch1: "result1", batch2: "result2"}
      manager = ResultManager.commit_batch_results(manager, batch)

      # Verify all results present
      assert ResultManager.completed_count(manager) == 5
      assert ResultManager.has_results?(manager, [:initial, :step1, :step2, :batch1, :batch2])

      # Archive and start new execution
      manager = ResultManager.archive_current_results(manager)
      assert ResultManager.completed_count(manager) == 0

      # Add new results
      manager = ResultManager.add_result(manager, :new_step, "new_result")

      # Check history
      history = ResultManager.get_execution_history(manager)
      assert length(history.previous_executions) == 1
      assert history.current_execution == %{new_step: "new_result"}

      # Get specific results
      assert ResultManager.get_result(manager, :new_step) == {:ok, "new_result"}

      # From previous execution
      assert ResultManager.get_result(manager, :initial) == :error
    end

    test "multiple archive cycles" do
      manager = ResultManager.new()

      # First execution cycle
      manager = ResultManager.add_result(manager, :cycle1, "result1")
      manager = ResultManager.archive_current_results(manager)

      # Second execution cycle
      manager = ResultManager.add_result(manager, :cycle2, "result2")
      manager = ResultManager.archive_current_results(manager)

      # Third execution cycle
      manager = ResultManager.add_result(manager, :cycle3, "result3")

      # Verify history structure
      history = ResultManager.get_execution_history(manager)
      assert length(history.previous_executions) == 2
      assert history.previous_executions == [%{cycle1: "result1"}, %{cycle2: "result2"}]
      assert history.current_execution == %{cycle3: "result3"}
    end
  end
end
