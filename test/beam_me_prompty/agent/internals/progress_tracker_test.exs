defmodule BeamMePrompty.Agent.Internals.ProgressTrackerTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Internals.ProgressTracker

  describe "new/1" do
    test "creates a new progress tracker with valid total_nodes" do
      tracker = ProgressTracker.new(5)

      assert tracker.total_nodes == 5
      assert tracker.completed_nodes == 0
      assert is_integer(tracker.started_at)
    end

    test "creates tracker with zero total_nodes" do
      tracker = ProgressTracker.new(0)

      assert tracker.total_nodes == 0
      assert tracker.completed_nodes == 0
    end

    test "sets started_at to current monotonic time" do
      before_time = System.monotonic_time(:millisecond)
      tracker = ProgressTracker.new(3)
      after_time = System.monotonic_time(:millisecond)

      assert tracker.started_at >= before_time
      assert tracker.started_at <= after_time
    end
  end

  describe "update_progress/2" do
    test "updates completed_nodes count" do
      tracker = ProgressTracker.new(10)
      updated = ProgressTracker.update_progress(tracker, 7)

      assert updated.completed_nodes == 7
      assert updated.total_nodes == 10
      assert updated.started_at == tracker.started_at
    end

    test "allows completed count to be zero" do
      tracker = ProgressTracker.new(5) |> ProgressTracker.update_progress(3)
      updated = ProgressTracker.update_progress(tracker, 0)

      assert updated.completed_nodes == 0
    end

    test "allows completed count to exceed total (edge case)" do
      tracker = ProgressTracker.new(5)
      updated = ProgressTracker.update_progress(tracker, 8)

      assert updated.completed_nodes == 8
    end
  end

  describe "get_progress_info/1" do
    test "returns correct progress information" do
      tracker = ProgressTracker.new(4) |> ProgressTracker.update_progress(2)
      info = ProgressTracker.get_progress_info(tracker)

      assert info.completed == 2
      assert info.total == 4
      assert info.percentage == 50.0
      assert is_integer(info.elapsed_ms)
      assert info.elapsed_ms >= 0
    end

    test "calculates percentage correctly for different ratios" do
      tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(1)
      info = ProgressTracker.get_progress_info(tracker)

      assert_in_delta info.percentage, 33.33, 0.1
    end

    test "handles zero total_nodes" do
      tracker = ProgressTracker.new(0)
      info = ProgressTracker.get_progress_info(tracker)

      assert info.completed == 0
      assert info.total == 0
      assert info.percentage == 0.0
    end

    test "handles completed count greater than total" do
      tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(5)
      info = ProgressTracker.get_progress_info(tracker)

      assert info.completed == 5
      assert info.total == 3
      assert_in_delta info.percentage, 166.67, 0.1
    end

    test "elapsed_ms increases over time" do
      tracker = ProgressTracker.new(5)
      info1 = ProgressTracker.get_progress_info(tracker)

      # Small delay to ensure time passes
      :timer.sleep(10)

      info2 = ProgressTracker.get_progress_info(tracker)

      assert info2.elapsed_ms > info1.elapsed_ms
    end
  end

  describe "complete?/1" do
    test "returns true when completed equals total" do
      tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(3)

      assert ProgressTracker.complete?(tracker) == true
    end

    test "returns true when completed exceeds total" do
      tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(5)

      assert ProgressTracker.complete?(tracker) == true
    end

    test "returns false when completed is less than total" do
      tracker = ProgressTracker.new(5) |> ProgressTracker.update_progress(3)

      assert ProgressTracker.complete?(tracker) == false
    end

    test "returns false for new tracker" do
      tracker = ProgressTracker.new(5)

      assert ProgressTracker.complete?(tracker) == false
    end

    test "handles zero total_nodes" do
      tracker = ProgressTracker.new(0)

      assert ProgressTracker.complete?(tracker) == true
    end
  end

  describe "reset/1" do
    test "resets completed_nodes and started_at but keeps total_nodes" do
      original_tracker = ProgressTracker.new(7) |> ProgressTracker.update_progress(4)

      # Small delay to ensure different timestamps
      :timer.sleep(10)

      reset_tracker = ProgressTracker.reset(original_tracker)

      assert reset_tracker.completed_nodes == 0
      assert reset_tracker.total_nodes == 7
      assert reset_tracker.started_at > original_tracker.started_at
    end

    test "reset tracker is not complete even if original was" do
      original_tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(3)
      assert ProgressTracker.complete?(original_tracker) == true

      reset_tracker = ProgressTracker.reset(original_tracker)
      assert ProgressTracker.complete?(reset_tracker) == false
    end

    test "reset tracker has fresh elapsed time" do
      original_tracker = ProgressTracker.new(5)

      # Let some time pass
      :timer.sleep(20)

      original_info = ProgressTracker.get_progress_info(original_tracker)
      reset_tracker = ProgressTracker.reset(original_tracker)
      reset_info = ProgressTracker.get_progress_info(reset_tracker)

      assert reset_info.elapsed_ms < original_info.elapsed_ms
    end
  end

  describe "integration scenarios" do
    test "typical progress tracking workflow" do
      # Start with 5 nodes
      tracker = ProgressTracker.new(5)

      # Progress through execution
      tracker = ProgressTracker.update_progress(tracker, 1)
      refute ProgressTracker.complete?(tracker)

      tracker = ProgressTracker.update_progress(tracker, 3)
      info = ProgressTracker.get_progress_info(tracker)
      assert info.percentage == 60.0

      tracker = ProgressTracker.update_progress(tracker, 5)
      assert ProgressTracker.complete?(tracker)

      # Reset for new cycle
      tracker = ProgressTracker.reset(tracker)
      refute ProgressTracker.complete?(tracker)
      assert tracker.completed_nodes == 0
      assert tracker.total_nodes == 5
    end

    test "multiple reset cycles" do
      tracker = ProgressTracker.new(3)

      # First cycle
      tracker = ProgressTracker.update_progress(tracker, 3)
      assert ProgressTracker.complete?(tracker)

      # Reset and second cycle
      tracker = ProgressTracker.reset(tracker)
      tracker = ProgressTracker.update_progress(tracker, 2)
      refute ProgressTracker.complete?(tracker)

      # Reset and third cycle
      tracker = ProgressTracker.reset(tracker)
      tracker = ProgressTracker.update_progress(tracker, 3)
      assert ProgressTracker.complete?(tracker)
    end
  end
end
