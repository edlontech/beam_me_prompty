defmodule BeamMePrompty.Agent.Internals.ErrorHandler do
  @moduledoc """
  Centralized error handling for agent execution.

  This module provides a consistent interface for handling various types of errors
  that can occur during DAG execution, including stage errors, planning errors,
  and agent callback errors.
  """
  @moduledoc section: :agent_internals

  require Logger

  alias BeamMePrompty.Agent.Internals.BatchManager
  alias BeamMePrompty.Agent.Internals.ResultManager
  alias BeamMePrompty.Agent.Internals.StateManager
  alias BeamMePrompty.Errors

  @type agent_module :: module()
  @type agent_state :: any()
  @type error_detail :: Splode.Error.t()
  @type data_struct :: map()
  @type error_response ::
          {:retry, agent_state()}
          | {:stop, any()}
          | {:restart, any()}

  @doc """
  Handles execution errors using the agent's error handling strategy.

  ## Parameters
  - `error_detail`: The error details (can be various formats)
  - `data`: The current execution data struct

  ## Returns
  A state machine transition tuple based on the agent's error handling response:
  - `{:next_state, :waiting_for_plan, reset_data, actions}` for retry
  - `{:stop, reason, data}` for stopping execution
  """
  @spec handle_execution_error(error_detail(), data_struct()) ::
          {:next_state, atom(), data_struct(), list()}
          | {:stop, any(), data_struct()}
  def handle_execution_error(error_detail, data) do
    Logger.debug(
      "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) handling error: #{inspect(error_detail)}"
    )

    error_class = Errors.to_class(error_detail)

    case StateManager.safe_execute(
           fn ->
             StateManager.execute_error_callback(
               data.agent_spec,
               error_class,
               data.current_state
             )
           end,
           "error callback"
         ) do
      {:ok, agent_response} ->
        process_agent_error_response(agent_response, data)

      {:error, callback_error} ->
        Logger.error(
          "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Error in agent error callback: #{inspect(callback_error)}"
        )

        {:stop, {:error_callback_failed, callback_error}, data}
    end
  end

  @doc """
  Handles stage execution errors specifically.

  ## Parameters
  - `node_name`: Name of the failed node
  - `error_reason`: The reason for the stage failure
  - `data`: The current execution data struct

  ## Returns
  A state machine transition tuple
  """
  @spec handle_stage_error(atom(), any(), data_struct()) ::
          {:next_state, atom(), data_struct(), list()}
          | {:stop, any(), data_struct()}
  def handle_stage_error(node_name, error_reason, data) do
    Logger.error(
      "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Stage execution failed for node #{node_name}: #{inspect(error_reason)}"
    )

    stage_execution_error =
      Errors.ExecutionError.exception(
        stage: node_name,
        cause: error_reason
      )

    cleaned_data = clear_batch_state(data)

    handle_execution_error(stage_execution_error, cleaned_data)
  end

  @doc """
  Handles planning errors (when no nodes are ready to execute).

  ## Parameters
  - `data`: The current execution data struct

  ## Returns
  A state machine transition tuple
  """
  @spec handle_planning_error(data_struct()) ::
          {:next_state, atom(), data_struct(), list()}
          | {:stop, any(), data_struct()}
  def handle_planning_error(data) do
    Logger.error(
      "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Planning error: No nodes ready to execute after agent's handle_plan"
    )

    planning_error =
      Errors.ExecutionError.exception(
        stage: :waiting_for_plan,
        cause: "No nodes are ready to execute after agent's handle_plan"
      )

    handle_execution_error(planning_error, data)
  end

  @doc """
  Handles supervisor startup errors.

  ## Parameters
  - `reason`: The reason for supervisor startup failure

  ## Returns
  A stop tuple for the state machine
  """
  @spec handle_supervisor_error(any()) :: {:stop, any()}
  def handle_supervisor_error(reason) do
    Logger.error("[ErrorHandler] Failed to start stages supervisor: #{inspect(reason)}")

    {:stop, {:failed_to_start_stages_supervisor, reason}}
  end

  @doc """
  Handles stage worker startup errors.

  ## Parameters
  - `node_name`: Name of the node for which stage worker failed to start
  - `reason`: The reason for stage worker startup failure

  ## Returns
  Raises an exception as this is typically a fatal error
  """
  @spec handle_stage_worker_error(atom(), any()) :: no_return()
  def handle_stage_worker_error(node_name, reason) do
    error_msg = "Failed to start stage worker for #{node_name}: #{inspect(reason)}"
    Logger.error("[ErrorHandler] #{error_msg}")
    raise BeamMePrompty.Errors.ExecutionError.exception(cause: error_msg)
  end

  @doc """
  Handles unexpected events in state machine states.

  ## Parameters
  - `state_name`: The current state name
  - `event_type`: Type of the unexpected event
  - `event_content`: Content of the unexpected event
  - `data`: The current execution data struct

  ## Returns
  `:keep_state_and_data` to maintain current state
  """
  @spec handle_unexpected_event(atom(), any(), any(), data_struct()) :: :keep_state_and_data
  def handle_unexpected_event(state_name, event_type, event_content, data) do
    Logger.warning(
      "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) unexpected event in #{state_name}: #{inspect(event_type)} - #{inspect(event_content)}"
    )

    :keep_state_and_data
  end

  # Private helper functions

  defp process_agent_error_response(agent_response, data) do
    case agent_response do
      {:retry, new_agent_state_for_retry} ->
        Logger.debug(
          "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Agent requested retry with new state"
        )

        reset_data = reset_for_retry(data, new_agent_state_for_retry)
        {:next_state, :waiting_for_plan, reset_data, [{:next_event, :internal, :plan}]}

      {:stop, stop_reason} ->
        Logger.debug(
          "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Agent requested stop: #{inspect(stop_reason)}"
        )

        {:stop, {:agent_stopped_execution, stop_reason}, data}

      {:restart, restart_reason} ->
        Logger.debug(
          "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Agent requested restart: #{inspect(restart_reason)}"
        )

        {:stop, {:restart_requested, restart_reason}, data}

      unexpected_response ->
        Logger.error(
          "[ErrorHandler] Agent [#{inspect(data.agent_spec)}] (sid: #{inspect(data.session_id)}) Unexpected response from agent's handle_error: #{inspect(unexpected_response)}. Stopping."
        )

        {:stop, {:unexpected_handle_error_response, unexpected_response}, data}
    end
  end

  defp reset_for_retry(data, new_agent_state) do
    # Reset execution state for retry while preserving core configuration
    %{
      data
      | current_state: new_agent_state,
        result_manager:
          case data.result_manager do
            # Keep existing results for retry
            %ResultManager{} = rm -> rm
            # Fallback if not using ResultManager yet
            _ -> ResultManager.new()
          end,
        # Clear batch execution state
        nodes_to_execute: [],
        batch_manager: BatchManager.new()
    }
  end

  defp clear_batch_state(data) do
    %{
      data
      | # Clear partial batch results as this batch errored
        batch_manager: BatchManager.new(),
        nodes_to_execute: []
    }
  end
end
