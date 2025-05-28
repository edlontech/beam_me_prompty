defmodule BeamMePrompty.Agent.Internals.StateManager do
  @moduledoc """
  Manages agent state transitions and callback handling.

  This module centralizes the repetitive pattern of calling agent callbacks
  and handling their various return formats. It provides a consistent interface
  for state management across all agent callback types.
  """

  require Logger

  @type agent_module :: module()
  @type agent_state :: any()
  @type callback_status :: :ok | {:ok, any()} | any()
  @type dag :: any()
  @type ready_nodes :: [atom()]
  @type planned_nodes :: [atom()]
  @type node_definitions :: [tuple()]
  @type batch_results :: map()
  @type pending_nodes :: [atom()]
  @type progress_info :: map()
  @type stage_definition :: any()
  @type stage_result :: any()
  @type error_class :: any()

  @doc """
  Handles the standard agent callback response pattern.

  Most agent callbacks return either:
  - `:ok` with a new state
  - `{:ok, override_state}` with a specific state override
  - Any other value (treated as error, keeps current state)

  ## Parameters
  - `callback_result`: The result tuple from an agent callback
  - `current_state`: The current agent state to fall back to

  ## Returns
  The appropriate agent state based on the callback result

  ## Examples
      iex> StateManager.handle_callback_response({:ok, "new_state"}, "current")
      "new_state"
      iex> StateManager.handle_callback_response({:ok, {:override, "override_state"}}, "current")
      {:override, "override_state"}
      iex> StateManager.handle_callback_response(:error, "current")
      "current"
  """
  @spec handle_callback_response({callback_status(), agent_state()}, agent_state()) ::
          agent_state()
  def handle_callback_response({status, new_state}, current_state) do
    case status do
      :ok -> new_state
      {:ok, overridden_state} -> overridden_state
      _ -> current_state
    end
  end

  @doc """
  Executes the agent's handle_init callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `dag`: The DAG structure
  - `initial_state`: The initial agent state

  ## Returns
  `{status, final_state}` tuple where status indicates success/failure
  and final_state is the resolved agent state.
  """
  @spec execute_init_callback(agent_module(), dag(), agent_state()) ::
          {callback_status(), agent_state()}
  def execute_init_callback(agent_module, dag, initial_state) do
    Logger.debug("[StateManager] Executing init callback for #{inspect(agent_module)}")

    {status, new_state} = agent_module.handle_init(dag, initial_state)
    final_state = handle_callback_response({status, new_state}, initial_state)

    {status, final_state}
  end

  @doc """
  Executes the agent's handle_plan callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `ready_nodes`: List of nodes ready for execution
  - `current_state`: Current agent state

  ## Returns
  `{status, planned_nodes, final_state}` tuple
  """
  @spec execute_plan_callback(agent_module(), ready_nodes(), agent_state()) ::
          {callback_status(), planned_nodes(), agent_state()}
  def execute_plan_callback(agent_module, ready_nodes, current_state) do
    Logger.debug(
      "[StateManager] Executing plan callback for #{inspect(agent_module)} with ready nodes: #{inspect(ready_nodes)}"
    )

    {status, planned_nodes, new_state} = agent_module.handle_plan(ready_nodes, current_state)
    final_state = handle_callback_response({status, new_state}, current_state)

    {status, planned_nodes, final_state}
  end

  @doc """
  Executes the agent's handle_batch_start callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `nodes_to_execute`: List of node definitions to execute
  - `current_state`: Current agent state

  ## Returns
  `{status, final_state}` tuple
  """
  @spec execute_batch_start_callback(agent_module(), node_definitions(), agent_state()) ::
          {callback_status(), agent_state()}
  def execute_batch_start_callback(agent_module, nodes_to_execute, current_state) do
    Logger.debug(
      "[StateManager] Executing batch_start callback for #{inspect(agent_module)} with #{length(nodes_to_execute)} nodes"
    )

    {status, new_state} = agent_module.handle_batch_start(nodes_to_execute, current_state)
    final_state = handle_callback_response({status, new_state}, current_state)

    {status, final_state}
  end

  @doc """
  Executes the agent's handle_stage_finish callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `stage_definition`: The stage definition that finished
  - `stage_result`: The result from the stage
  - `current_state`: Current agent state

  ## Returns
  `{status, final_state}` tuple
  """
  @spec execute_stage_finish_callback(
          agent_module(),
          stage_definition(),
          stage_result(),
          agent_state()
        ) ::
          {callback_status(), agent_state()}
  def execute_stage_finish_callback(agent_module, stage_definition, stage_result, current_state) do
    Logger.debug("[StateManager] Executing stage_finish callback for #{inspect(agent_module)}")

    {status, new_state} =
      agent_module.handle_stage_finish(stage_definition, stage_result, current_state)

    final_state = handle_callback_response({status, new_state}, current_state)

    {status, final_state}
  end

  @doc """
  Executes the agent's handle_progress callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `progress_info`: Progress information map
  - `current_state`: Current agent state

  ## Returns
  `{status, final_state}` tuple
  """
  @spec execute_progress_callback(agent_module(), progress_info(), agent_state()) ::
          {callback_status(), agent_state()}
  def execute_progress_callback(agent_module, progress_info, current_state) do
    Logger.debug(
      "[StateManager] Executing progress callback for #{inspect(agent_module)} - #{progress_info.completed}/#{progress_info.total} completed"
    )

    {status, new_state} = agent_module.handle_progress(progress_info, current_state)
    final_state = handle_callback_response({status, new_state}, current_state)

    {status, final_state}
  end

  @doc """
  Executes the agent's handle_batch_complete callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `batch_results`: Results from the completed batch
  - `pending_nodes`: List of nodes still pending
  - `current_state`: Current agent state

  ## Returns
  `{status, final_state}` tuple
  """
  @spec execute_batch_complete_callback(
          agent_module(),
          batch_results(),
          pending_nodes(),
          agent_state()
        ) ::
          {callback_status(), agent_state()}
  def execute_batch_complete_callback(agent_module, batch_results, pending_nodes, current_state) do
    Logger.debug(
      "[StateManager] Executing batch_complete callback for #{inspect(agent_module)} with #{map_size(batch_results)} results"
    )

    {status, new_state} =
      agent_module.handle_batch_complete(batch_results, pending_nodes, current_state)

    final_state = handle_callback_response({status, new_state}, current_state)

    {status, final_state}
  end

  @doc """
  Executes the agent's handle_complete callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `final_results`: Final execution results
  - `current_state`: Current agent state

  ## Returns
  `{status, final_state}` tuple
  """
  @spec execute_complete_callback(agent_module(), map(), agent_state()) ::
          {callback_status(), agent_state()}
  def execute_complete_callback(agent_module, final_results, current_state) do
    Logger.debug("[StateManager] Executing complete callback for #{inspect(agent_module)}")

    {status, new_state} = agent_module.handle_complete(final_results, current_state)
    final_state = handle_callback_response({status, new_state}, current_state)

    {status, final_state}
  end

  @doc """
  Executes the agent's handle_error callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `error_class`: The error class/type
  - `current_state`: Current agent state

  ## Returns
  The agent's error handling response (varies by implementation)
  """
  @spec execute_error_callback(agent_module(), error_class(), agent_state()) :: any()
  def execute_error_callback(agent_module, error_class, current_state) do
    Logger.debug(
      "[StateManager] Executing error callback for #{inspect(agent_module)} with error: #{inspect(error_class)}"
    )

    agent_module.handle_error(error_class, current_state)
  end

  @doc """
  Executes the agent's handle_cleanup callback.

  ## Parameters
  - `agent_module`: The agent module to call
  - `execution_status`: The final execution status
  - `current_state`: Current agent state

  ## Returns
  The cleanup callback result (usually ignored)
  """
  @spec execute_cleanup_callback(agent_module(), atom(), agent_state()) :: any()
  def execute_cleanup_callback(agent_module, execution_status, current_state) do
    Logger.debug(
      "[StateManager] Executing cleanup callback for #{inspect(agent_module)} with status: #{inspect(execution_status)}"
    )

    agent_module.handle_cleanup(execution_status, current_state)
  end

  @doc """
  Safely executes a callback with error handling.

  ## Parameters
  - `callback_fn`: Function to execute
  - `error_context`: Context information for error logging

  ## Returns
  `{:ok, result}` on success or `{:error, reason}` on failure
  """
  @spec safe_execute(function(), String.t()) :: {:ok, any()} | {:error, any()}
  def safe_execute(callback_fn, error_context) do
    try do
      result = callback_fn.()
      {:ok, result}
    rescue
      error ->
        Logger.error("[StateManager] Error in #{error_context}: #{inspect(error)}")
        {:error, {:callback_error, error}}
    catch
      thrown_value ->
        Logger.error("[StateManager] Thrown value in #{error_context}: #{inspect(thrown_value)}")
        {:error, {:callback_thrown, thrown_value}}
    end
  end
end
