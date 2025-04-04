defmodule BeamMePrompty.Agent.Internals.ProgressTracker do
  @moduledoc """
  Tracks and reports execution progress for DAG node execution.

  This module provides a clean interface for tracking the progress of DAG execution,
  including timing information and completion ratios.
  """
  @moduledoc section: :agent_internals

  defstruct [
    :started_at,
    :total_nodes,
    :completed_nodes
  ]

  @type t :: %__MODULE__{
          started_at: integer(),
          total_nodes: non_neg_integer(),
          completed_nodes: non_neg_integer()
        }

  @doc """
  Creates a new progress tracker.

  ## Parameters
  - `total_nodes`: The total number of nodes to be executed

  ## Examples
      iex> tracker = ProgressTracker.new(5)
      iex> tracker.total_nodes
      5
      iex> tracker.completed_nodes
      0
  """
  @spec new(non_neg_integer()) :: t()
  def new(total_nodes) when is_integer(total_nodes) and total_nodes >= 0 do
    %__MODULE__{
      started_at: System.monotonic_time(:millisecond),
      total_nodes: total_nodes,
      completed_nodes: 0
    }
  end

  @doc """
  Updates the progress tracker with the current completed node count.

  ## Parameters
  - `tracker`: The progress tracker struct
  - `completed_count`: The number of completed nodes

  ## Examples
      iex> tracker = ProgressTracker.new(5)
      iex> updated = ProgressTracker.update_progress(tracker, 3)
      iex> updated.completed_nodes
      3
  """
  @spec update_progress(t(), non_neg_integer()) :: t()
  def update_progress(%__MODULE__{} = tracker, completed_count)
      when is_integer(completed_count) and completed_count >= 0 do
    %{tracker | completed_nodes: completed_count}
  end

  @doc """
  Gets comprehensive progress information including timing.

  ## Parameters
  - `tracker`: The progress tracker struct

  ## Returns
  A map containing:
  - `:completed`: Number of completed nodes
  - `:total`: Total number of nodes
  - `:elapsed_ms`: Elapsed time in milliseconds
  - `:percentage`: Completion percentage (0-100)

  ## Examples
      iex> tracker = ProgressTracker.new(4) |> ProgressTracker.update_progress(2)
      iex> info = ProgressTracker.get_progress_info(tracker)
      iex> info.completed
      2
      iex> info.total
      4
      iex> info.percentage
      50.0
  """
  @spec get_progress_info(t()) :: %{
          completed: non_neg_integer(),
          total: non_neg_integer(),
          elapsed_ms: integer(),
          percentage: float()
        }
  def get_progress_info(%__MODULE__{} = tracker) do
    elapsed_ms = System.monotonic_time(:millisecond) - tracker.started_at
    percentage = calculate_percentage(tracker.completed_nodes, tracker.total_nodes)

    %{
      completed: tracker.completed_nodes,
      total: tracker.total_nodes,
      elapsed_ms: elapsed_ms,
      percentage: percentage
    }
  end

  @doc """
  Checks if the execution is complete.

  ## Parameters
  - `tracker`: The progress tracker struct

  ## Examples
      iex> tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(3)
      iex> ProgressTracker.complete?(tracker)
      true

      iex> tracker = ProgressTracker.new(3) |> ProgressTracker.update_progress(2)
      iex> ProgressTracker.complete?(tracker)
      false
  """
  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{} = tracker) do
    tracker.completed_nodes >= tracker.total_nodes
  end

  @doc """
  Resets the progress tracker for a new execution cycle.
  Keeps the total_nodes but resets completed count and start time.

  ## Parameters
  - `tracker`: The progress tracker struct

  ## Examples
      iex> tracker = ProgressTracker.new(5) |> ProgressTracker.update_progress(3)
      iex> reset = ProgressTracker.reset(tracker)
      iex> reset.completed_nodes
      0
      iex> reset.total_nodes
      5
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = tracker) do
    %{tracker | started_at: System.monotonic_time(:millisecond), completed_nodes: 0}
  end

  # Private helper functions

  defp calculate_percentage(_completed, total) when total == 0, do: 0.0
  defp calculate_percentage(completed, total), do: completed / total * 100.0
end
