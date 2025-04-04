defmodule BeamMePrompty.Agent.Internals.BatchManager do
  @moduledoc """
  Handles batch execution of DAG nodes.

  This module manages the lifecycle of batch execution including:
  - Preparing node contexts for execution
  - Dispatching nodes to stage workers
  - Tracking batch progress and results
  - Managing pending node states
  """
  @moduledoc section: :agent_internals

  require Logger

  alias BeamMePrompty.Errors

  defstruct [
    :batch_details,
    :temp_results,
    :pending_nodes
  ]

  @type node_name :: atom() | String.t()
  @type node_definition :: map()
  @type node_context :: map()
  @type node_tuple :: {node_name(), node_definition(), node_context()}
  @type batch_details :: %{node_name() => {node_definition(), node_context()}}
  @type temp_results :: %{node_name() => any()}
  @type pending_nodes :: [node_name()]
  @type stage_workers :: %{node_name() => pid()}
  @type caller_pid :: pid()
  @type stage_result :: any()

  @type t :: %__MODULE__{
          batch_details: batch_details(),
          temp_results: temp_results(),
          pending_nodes: pending_nodes()
        }

  @doc """
  Creates a new empty batch manager.

  ## Examples
      iex> batch = BatchManager.new()
      iex> map_size(batch.batch_details)
      0
      iex> map_size(batch.temp_results)
      0
      iex> length(batch.pending_nodes)
      0
  """
  @spec new() :: t()
  def new() do
    %__MODULE__{
      batch_details: %{},
      temp_results: %{},
      pending_nodes: []
    }
  end

  @doc """
  Prepares a batch of nodes for execution.

  ## Parameters
  - `nodes_to_execute`: List of {node_name, node_def, node_context} tuples
  - `agent_state`: Current agent state to include in contexts

  ## Returns
  A new batch manager with prepared batch details and pending nodes

  ## Examples
      iex> nodes = [{:node1, %{type: :llm}, %{input: "test"}}]
      iex> batch = BatchManager.prepare_batch(nodes, "agent_state")
      iex> length(batch.pending_nodes)
      1
  """
  @spec prepare_batch([node_tuple()], any()) :: t()
  def prepare_batch(nodes_to_execute, agent_state) when is_list(nodes_to_execute) do
    nodes_with_updated_context =
      Enum.map(nodes_to_execute, fn {name, node_def, node_ctx} ->
        updated_ctx = Map.put(node_ctx, :current_agent_state, agent_state)
        {name, node_def, updated_ctx}
      end)

    batch_details_map =
      Enum.into(nodes_with_updated_context, %{}, fn {name, node_def, updated_ctx} ->
        {name, {node_def, updated_ctx}}
      end)

    pending_node_names =
      Enum.map(nodes_with_updated_context, fn {name, _, _} -> name end)

    %__MODULE__{
      batch_details: batch_details_map,
      temp_results: %{},
      pending_nodes: pending_node_names
    }
  end

  @doc """
  Dispatches all nodes in the batch to their respective stage workers.

  ## Parameters
  - `batch`: The batch manager with prepared nodes
  - `stage_workers`: Map of node names to stage worker PIDs
  - `caller_pid`: PID of the calling process (for responses)

  ## Returns
  `:ok` after dispatching all nodes
  """
  @spec dispatch_nodes(t(), stage_workers(), caller_pid()) :: :ok
  def dispatch_nodes(%__MODULE__{} = batch, stage_workers, caller_pid)
      when is_map(stage_workers) and is_pid(caller_pid) do
    Enum.each(batch.batch_details, fn {node_name, {node_def, node_ctx}} ->
      case Map.get(stage_workers, node_name) do
        nil ->
          Logger.error("[BatchManager] No stage worker found for node #{node_name}")

        stage_pid ->
          Logger.debug(
            "[BatchManager] Dispatching node #{node_name} to worker #{inspect(stage_pid)}"
          )

          GenStateMachine.cast(
            stage_pid,
            {:execute, node_name, node_def, node_ctx, caller_pid}
          )
      end
    end)

    :ok
  end

  @doc """
  Handles the completion of a single stage in the batch.

  ## Parameters
  - `batch`: The current batch manager
  - `node_name`: Name of the completed node
  - `result`: Result from the completed stage

  ## Returns
  `{:batch_complete, updated_batch}` if all nodes are done,
  `{:batch_pending, updated_batch}` if more nodes are pending

  ## Examples
      iex> batch = BatchManager.prepare_batch([{:node1, %{}, %{}}], "state")
      iex> {status, updated} = BatchManager.handle_stage_completion(batch, :node1, "result")
      iex> status
      :batch_complete
      iex> updated.temp_results[:node1]
      "result"
  """
  @spec handle_stage_completion(t(), node_name(), stage_result()) ::
          {:batch_complete, t()} | {:batch_pending, t()}
  def handle_stage_completion(%__MODULE__{} = batch, node_name, result) do
    updated_temp_results = Map.put(batch.temp_results, node_name, result)

    updated_pending_nodes = List.delete(batch.pending_nodes, node_name)

    updated_batch = %{
      batch
      | temp_results: updated_temp_results,
        pending_nodes: updated_pending_nodes
    }

    if Enum.empty?(updated_pending_nodes) do
      {:batch_complete, updated_batch}
    else
      {:batch_pending, updated_batch}
    end
  end

  @doc """
  Gets the current batch results.

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  Map of node names to their results
  """
  @spec get_batch_results(t()) :: temp_results()
  def get_batch_results(%__MODULE__{} = batch) do
    batch.temp_results
  end

  @doc """
  Gets the list of pending node names.

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  List of pending node names
  """
  @spec get_pending_nodes(t()) :: pending_nodes()
  def get_pending_nodes(%__MODULE__{} = batch) do
    batch.pending_nodes
  end

  @doc """
  Gets the batch details for a specific node.

  ## Parameters
  - `batch`: The batch manager
  - `node_name`: Name of the node

  ## Returns
  `{:ok, {node_def, node_ctx}}` if found, `:error` if not found
  """
  @spec get_node_details(t(), node_name()) ::
          {:ok, {node_definition(), node_context()}} | {:error, Errors.ExecutionError.t()}
  def get_node_details(%__MODULE__{} = batch, node_name) do
    case Map.get(batch.batch_details, node_name) do
      nil ->
        {:error,
         Errors.ExecutionError.exception(
           cause: "Node details not found in batch_details for node: #{inspect(node_name)}"
         )}

      details ->
        {:ok, details}
    end
  end

  @doc """
  Checks if the batch is complete (no pending nodes).

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  `true` if complete, `false` if pending nodes remain
  """
  @spec complete?(t()) :: boolean()
  def complete?(%__MODULE__{} = batch) do
    Enum.empty?(batch.pending_nodes)
  end

  @doc """
  Gets the count of completed nodes in the batch.

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  Number of completed nodes
  """
  @spec completed_count(t()) :: non_neg_integer()
  def completed_count(%__MODULE__{} = batch) do
    map_size(batch.temp_results)
  end

  @doc """
  Gets the total count of nodes in the batch.

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  Total number of nodes in the batch
  """
  @spec total_count(t()) :: non_neg_integer()
  def total_count(%__MODULE__{} = batch) do
    map_size(batch.batch_details)
  end

  @doc """
  Checks if a specific node is pending in the batch.

  ## Parameters
  - `batch`: The batch manager
  - `node_name`: Name of the node to check

  ## Returns
  `true` if the node is pending, `false` otherwise
  """
  @spec node_pending?(t(), node_name()) :: boolean()
  def node_pending?(%__MODULE__{} = batch, node_name) do
    node_name in batch.pending_nodes
  end

  @doc """
  Clears the batch, resetting all state.

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  A new empty batch manager
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{}) do
    new()
  end

  @doc """
  Gets batch execution statistics.

  ## Parameters
  - `batch`: The batch manager

  ## Returns
  Map with execution statistics
  """
  @spec get_stats(t()) :: %{
          total: non_neg_integer(),
          completed: non_neg_integer(),
          pending: non_neg_integer(),
          completion_percentage: float()
        }
  def get_stats(%__MODULE__{} = batch) do
    total = total_count(batch)
    completed = completed_count(batch)
    pending = length(batch.pending_nodes)

    completion_percentage =
      if total > 0, do: completed / total * 100.0, else: 0.0

    %{
      total: total,
      completed: completed,
      pending: pending,
      completion_percentage: completion_percentage
    }
  end
end
