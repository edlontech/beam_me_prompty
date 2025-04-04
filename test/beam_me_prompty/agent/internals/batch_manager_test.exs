defmodule BeamMePrompty.Agent.Internals.BatchManagerTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Internals.BatchManager

  describe "new/0" do
    test "creates an empty batch manager" do
      batch = BatchManager.new()
      assert %BatchManager{} = batch
      assert batch.batch_details == %{}
      assert batch.temp_results == %{}
      assert batch.pending_nodes == []
    end
  end

  describe "prepare_batch/2" do
    test "prepares a batch with nodes and agent state" do
      nodes_to_execute = [
        {:node1, %{type: :llm}, %{input: "input1"}},
        {:node2, %{type: :tool}, %{params: %{a: 1}}}
      ]

      agent_state = %{user_id: 123}

      batch = BatchManager.prepare_batch(nodes_to_execute, agent_state)

      assert %BatchManager{} = batch
      assert Map.keys(batch.batch_details) == [:node1, :node2]
      assert batch.pending_nodes == [:node1, :node2]
      assert batch.temp_results == %{}

      # Check if agent_state is added to node context
      assert batch.batch_details.node1 |> elem(1) |> Map.get(:current_agent_state) == agent_state
      assert batch.batch_details.node2 |> elem(1) |> Map.get(:current_agent_state) == agent_state
      assert batch.batch_details.node1 |> elem(1) |> Map.get(:input) == "input1"
    end

    test "prepares an empty batch if no nodes are provided" do
      batch = BatchManager.prepare_batch([], "some_state")
      assert %BatchManager{} = batch
      assert batch.batch_details == %{}
      assert batch.temp_results == %{}
      assert batch.pending_nodes == []
    end
  end

  describe "handle_stage_completion/3" do
    test "updates batch when a stage completes" do
      nodes = [{:node1, %{}, %{}}, {:node2, %{}, %{}}]
      initial_batch = BatchManager.prepare_batch(nodes, "state")

      {:batch_pending, batch_after_node1} =
        BatchManager.handle_stage_completion(initial_batch, :node1, "result1")

      assert batch_after_node1.temp_results == %{node1: "result1"}
      assert batch_after_node1.pending_nodes == [:node2]
      assert BatchManager.completed_count(batch_after_node1) == 1
      assert not BatchManager.complete?(batch_after_node1)

      {:batch_complete, batch_after_node2} =
        BatchManager.handle_stage_completion(batch_after_node1, :node2, "result2")

      assert batch_after_node2.temp_results == %{node1: "result1", node2: "result2"}
      assert batch_after_node2.pending_nodes == []
      assert BatchManager.completed_count(batch_after_node2) == 2
      assert BatchManager.complete?(batch_after_node2)
    end

    test "handles completion of a non-existent node gracefully (removes if pending)" do
      nodes = [{:node1, %{}, %{}}]
      initial_batch = BatchManager.prepare_batch(nodes, "state")

      # Simulate :node_missing was in pending_nodes but somehow not in batch_details
      batch_with_extra_pending = %{initial_batch | pending_nodes: [:node1, :node_missing]}

      {:batch_pending, updated_batch} =
        BatchManager.handle_stage_completion(
          batch_with_extra_pending,
          :node_missing,
          "result_missing"
        )

      assert updated_batch.temp_results == %{node_missing: "result_missing"}
      assert updated_batch.pending_nodes == [:node1]
    end
  end

  describe "get_batch_results/1" do
    test "returns current temporary results" do
      nodes = [{:node1, %{}, %{}}]
      batch = BatchManager.prepare_batch(nodes, "state")

      {:batch_complete, completed_batch} =
        BatchManager.handle_stage_completion(batch, :node1, "result_data")

      assert BatchManager.get_batch_results(completed_batch) == %{node1: "result_data"}
      assert BatchManager.get_batch_results(BatchManager.new()) == %{}
    end
  end

  describe "get_pending_nodes/1" do
    test "returns the list of pending node names" do
      nodes = [{:nodeA, %{}, %{}}, {:nodeB, %{}, %{}}]
      batch = BatchManager.prepare_batch(nodes, "state")
      assert BatchManager.get_pending_nodes(batch) == [:nodeA, :nodeB]

      {:batch_pending, updated_batch} =
        BatchManager.handle_stage_completion(batch, :nodeA, "done")

      assert BatchManager.get_pending_nodes(updated_batch) == [:nodeB]
    end
  end

  describe "get_node_details/2" do
    test "returns node definition and context if node exists" do
      node_def = %{type: :llm_call}
      node_ctx = %{input: "hello", current_agent_state: "agent_s1"}

      # Context before agent_state is added
      nodes = [{:my_node, node_def, %{input: "hello"}}]
      batch = BatchManager.prepare_batch(nodes, "agent_s1")

      assert BatchManager.get_node_details(batch, :my_node) == {:ok, {node_def, node_ctx}}
    end

    test "returns :error if node does not exist" do
      batch = BatchManager.new()
      assert {:error, _reason} = BatchManager.get_node_details(batch, :non_existent_node)
    end
  end

  describe "complete?/1" do
    test "returns true if all nodes are completed" do
      nodes = [{:n1, %{}, %{}}]
      batch = BatchManager.prepare_batch(nodes, "state")
      refute BatchManager.complete?(batch)

      {:batch_complete, completed_batch} =
        BatchManager.handle_stage_completion(batch, :n1, "res")

      assert BatchManager.complete?(completed_batch)
    end

    test "returns true for an empty batch" do
      assert BatchManager.complete?(BatchManager.new())
      assert BatchManager.complete?(BatchManager.prepare_batch([], "state"))
    end
  end

  describe "completed_count/1" do
    test "returns the number of completed nodes" do
      nodes = [{:a, %{}, %{}}, {:b, %{}, %{}}]
      batch = BatchManager.prepare_batch(nodes, "state")
      assert BatchManager.completed_count(batch) == 0

      {:batch_pending, batch1} = BatchManager.handle_stage_completion(batch, :a, "r1")
      assert BatchManager.completed_count(batch1) == 1

      {:batch_complete, batch2} = BatchManager.handle_stage_completion(batch1, :b, "r2")
      assert BatchManager.completed_count(batch2) == 2
    end
  end

  describe "total_count/1" do
    test "returns the total number of nodes in the batch" do
      nodes = [{:x, %{}, %{}}, {:y, %{}, %{}}, {:z, %{}, %{}}]
      batch = BatchManager.prepare_batch(nodes, "state")
      assert BatchManager.total_count(batch) == 3
      assert BatchManager.total_count(BatchManager.new()) == 0
    end
  end

  describe "node_pending?/2" do
    test "checks if a specific node is pending" do
      nodes = [{:p1, %{}, %{}}, {:p2, %{}, %{}}]
      batch = BatchManager.prepare_batch(nodes, "state")

      assert BatchManager.node_pending?(batch, :p1)
      assert BatchManager.node_pending?(batch, :p2)
      refute BatchManager.node_pending?(batch, :p3)

      {:batch_pending, updated_batch} =
        BatchManager.handle_stage_completion(batch, :p1, "done")

      refute BatchManager.node_pending?(updated_batch, :p1)
      assert BatchManager.node_pending?(updated_batch, :p2)
    end
  end

  describe "clear/1" do
    test "resets the batch manager to an empty state" do
      nodes = [{:node1, %{detail: "abc"}, %{ctx: 1}}]
      batch = BatchManager.prepare_batch(nodes, "initial_state")

      {:batch_complete, completed_batch} =
        BatchManager.handle_stage_completion(batch, :node1, "res1")

      cleared_batch = BatchManager.clear(completed_batch)
      assert %BatchManager{} = cleared_batch
      assert cleared_batch.batch_details == %{}
      assert cleared_batch.temp_results == %{}
      assert cleared_batch.pending_nodes == []
    end
  end

  describe "get_stats/1" do
    test "returns correct batch execution statistics" do
      nodes = [
        {:s_node1, %{}, %{}},
        {:s_node2, %{}, %{}},
        {:s_node3, %{}, %{}},
        {:s_node4, %{}, %{}}
      ]

      batch = BatchManager.prepare_batch(nodes, "state")

      stats_initial = BatchManager.get_stats(batch)
      assert stats_initial.total == 4
      assert stats_initial.completed == 0
      assert stats_initial.pending == 4
      assert stats_initial.completion_percentage == 0.0

      {:batch_pending, batch1} =
        BatchManager.handle_stage_completion(batch, :s_node1, "r1")

      stats_after_1 = BatchManager.get_stats(batch1)
      assert stats_after_1.total == 4
      assert stats_after_1.completed == 1
      assert stats_after_1.pending == 3
      assert stats_after_1.completion_percentage == 25.0

      {:batch_pending, batch2} =
        BatchManager.handle_stage_completion(batch1, :s_node2, "r2")

      {:batch_pending, batch3} =
        BatchManager.handle_stage_completion(batch2, :s_node3, "r3")

      {:batch_complete, batch4} =
        BatchManager.handle_stage_completion(batch3, :s_node4, "r4")

      stats_final = BatchManager.get_stats(batch4)
      assert stats_final.total == 4
      assert stats_final.completed == 4
      assert stats_final.pending == 0
      assert stats_final.completion_percentage == 100.0
    end

    test "returns correct stats for an empty batch" do
      empty_batch = BatchManager.new()
      stats_empty = BatchManager.get_stats(empty_batch)
      assert stats_empty.total == 0
      assert stats_empty.completed == 0
      assert stats_empty.pending == 0
      assert stats_empty.completion_percentage == 0.0
    end
  end
end
