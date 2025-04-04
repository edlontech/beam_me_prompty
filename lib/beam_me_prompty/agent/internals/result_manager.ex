defmodule BeamMePrompty.Agent.Internals.ResultManager do
  @moduledoc """
  Manages DAG execution results and result history.

  This module provides a clean interface for managing the results of DAG node execution,
  including current results, batch results, and historical results for stateful agents.
  """
  @moduledoc section: :agent_internals

  defstruct [
    :dag_results,
    :previous_results
  ]

  @type node_name :: atom() | String.t()
  @type node_result :: any()
  @type results_map :: %{node_name() => node_result()}

  @type t :: %__MODULE__{
          dag_results: results_map(),
          previous_results: [results_map()]
        }

  @doc """
  Creates a new result manager.

  ## Examples
      iex> manager = ResultManager.new()
      iex> map_size(manager.dag_results)
      0
      iex> length(manager.previous_results)
      0
  """
  @spec new() :: t()
  def new() do
    %__MODULE__{
      dag_results: %{},
      previous_results: []
    }
  end

  @doc """
  Creates a new result manager with initial results.

  ## Parameters
  - `initial_results`: Initial DAG results map

  ## Examples
      iex> initial = %{node1: "result1", node2: "result2"}
      iex> manager = ResultManager.new(initial)
      iex> manager.dag_results
      %{node1: "result1", node2: "result2"}
  """
  @spec new(results_map()) :: t()
  def new(initial_results) when is_map(initial_results) do
    %__MODULE__{
      dag_results: initial_results,
      previous_results: []
    }
  end

  @doc """
  Adds a single node result to the manager.

  ## Parameters
  - `manager`: The result manager struct
  - `node_name`: Name of the node
  - `result`: Result value for the node

  ## Examples
      iex> manager = ResultManager.new()
      iex> updated = ResultManager.add_result(manager, :node1, "success")
      iex> updated.dag_results[:node1]
      "success"
  """
  @spec add_result(t(), node_name(), node_result()) :: t()
  def add_result(%__MODULE__{} = manager, node_name, result) do
    updated_results = Map.put(manager.dag_results, node_name, result)
    %{manager | dag_results: updated_results}
  end

  @doc """
  Commits a batch of results to the main DAG results.

  ## Parameters
  - `manager`: The result manager struct
  - `batch_results`: Map of batch results to commit

  ## Examples
      iex> manager = ResultManager.new(%{existing: "value"})
      iex> batch = %{node1: "result1", node2: "result2"}
      iex> updated = ResultManager.commit_batch_results(manager, batch)
      iex> map_size(updated.dag_results)
      3
  """
  @spec commit_batch_results(t(), results_map()) :: t()
  def commit_batch_results(%__MODULE__{} = manager, batch_results)
      when is_map(batch_results) do
    updated_results = Map.merge(manager.dag_results, batch_results)
    %{manager | dag_results: updated_results}
  end

  @doc """
  Archives the current results and resets for a new execution cycle.
  Used primarily for stateful agents that can be re-executed.

  ## Parameters
  - `manager`: The result manager struct

  ## Examples
      iex> manager = ResultManager.new(%{node1: "result1"})
      iex> archived = ResultManager.archive_current_results(manager)
      iex> map_size(archived.dag_results)
      0
      iex> length(archived.previous_results)
      1
      iex> hd(archived.previous_results)
      %{node1: "result1"}
  """
  @spec archive_current_results(t()) :: t()
  def archive_current_results(%__MODULE__{} = manager) do
    %{
      manager
      | previous_results: manager.previous_results ++ [manager.dag_results],
        dag_results: %{}
    }
  end

  @doc """
  Gets the result for a specific node.

  ## Parameters
  - `manager`: The result manager struct
  - `node_name`: Name of the node to get result for

  ## Returns
  - `{:ok, result}` if the node result exists
  - `:error` if the node result doesn't exist

  ## Examples
      iex> manager = ResultManager.new(%{node1: "success"})
      iex> ResultManager.get_result(manager, :node1)
      {:ok, "success"}
      iex> ResultManager.get_result(manager, :missing)
      :error
  """
  @spec get_result(t(), node_name()) :: {:ok, node_result()} | :error
  def get_result(%__MODULE__{} = manager, node_name) do
    case Map.get(manager.dag_results, node_name) do
      nil -> :error
      result -> {:ok, result}
    end
  end

  @doc """
  Gets all current DAG results.

  ## Parameters
  - `manager`: The result manager struct

  ## Examples
      iex> manager = ResultManager.new(%{node1: "result1", node2: "result2"})
      iex> ResultManager.get_all_results(manager)
      %{node1: "result1", node2: "result2"}
  """
  @spec get_all_results(t()) :: results_map()
  def get_all_results(%__MODULE__{} = manager) do
    manager.dag_results
  end

  @doc """
  Gets the complete execution history including current and previous results.

  ## Parameters
  - `manager`: The result manager struct

  ## Examples
      iex> manager = ResultManager.new(%{current: "result"})
      iex> manager = ResultManager.archive_current_results(manager)
      iex> manager = ResultManager.add_result(manager, :new_node, "new_result")
      iex> history = ResultManager.get_execution_history(manager)
      iex> length(history.previous_executions)
      1
      iex> history.current_execution
      %{new_node: "new_result"}
  """
  @spec get_execution_history(t()) :: %{
          current_execution: results_map(),
          previous_executions: [results_map()]
        }
  def get_execution_history(%__MODULE__{} = manager) do
    %{
      current_execution: manager.dag_results,
      previous_executions: manager.previous_results
    }
  end

  @doc """
  Checks if all specified nodes have results.

  ## Parameters
  - `manager`: The result manager struct
  - `node_names`: List of node names to check

  ## Examples
      iex> manager = ResultManager.new(%{node1: "result1", node2: "result2"})
      iex> ResultManager.has_results?(manager, [:node1, :node2])
      true
      iex> ResultManager.has_results?(manager, [:node1, :missing])
      false
  """
  @spec has_results?(t(), [node_name()]) :: boolean()
  def has_results?(%__MODULE__{} = manager, node_names) when is_list(node_names) do
    Enum.all?(node_names, fn node_name ->
      Map.has_key?(manager.dag_results, node_name)
    end)
  end

  @doc """
  Gets the count of completed nodes.

  ## Parameters
  - `manager`: The result manager struct

  ## Examples
      iex> manager = ResultManager.new(%{node1: "result1", node2: "result2"})
      iex> ResultManager.completed_count(manager)
      2
  """
  @spec completed_count(t()) :: non_neg_integer()
  def completed_count(%__MODULE__{} = manager) do
    map_size(manager.dag_results)
  end

  @doc """
  Clears all results (current and previous).

  ## Parameters
  - `manager`: The result manager struct

  ## Examples
      iex> manager = ResultManager.new(%{node1: "result1"})
      iex> cleared = ResultManager.clear_all(manager)
      iex> map_size(cleared.dag_results)
      0
      iex> length(cleared.previous_results)
      0
  """
  @spec clear_all(t()) :: t()
  def clear_all(%__MODULE__{}) do
    new()
  end
end
