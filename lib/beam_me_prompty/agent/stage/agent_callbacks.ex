defmodule BeamMePrompty.Agent.Stage.AgentCallbacks do
  @moduledoc """
  Helper functions for managing agent callback interactions.

  Centralizes the logic for calling agent lifecycle callbacks and managing
  agent state transitions consistently across the stage execution pipeline.
  """
  @moduledoc section: :agent_stage_and_execution

  require Logger

  @doc """
  Calls the agent's handle_stage_start callback if the agent module is available.
  """
  def call_stage_start(nil, _node_def, agent_state), do: {:ok, agent_state}

  def call_stage_start(agent_module, node_def, agent_state) do
    result = agent_module.handle_stage_start(node_def, agent_state)
    {:ok, result}
  rescue
    e ->
      Logger.warning("[BeamMePrompty] Agent callback handle_stage_start failed: #{inspect(e)}")
      {:ok, agent_state}
  end

  @doc """
  Calls the agent's handle_tool_call callback and manages state transitions.
  """
  def call_tool_call(nil, _tool_name, _tool_args, agent_state) do
    {:ok, agent_state}
  end

  def call_tool_call(agent_module, tool_name, tool_args, agent_state) do
    case agent_module.handle_tool_call(tool_name, tool_args, agent_state) do
      :ok ->
        {:ok, agent_state}

      {:ok, new_state} ->
        {:ok, new_state}

      {:error, _} ->
        {:error, agent_state}

      other ->
        Logger.warning("[BeamMePrompty] Unexpected handle_tool_call result: #{inspect(other)}")
        {:ok, agent_state}
    end
  rescue
    e ->
      Logger.warning("[BeamMePrompty] Agent callback handle_tool_call failed: #{inspect(e)}")
      {:ok, agent_state}
  end

  @doc """
  Calls the agent's handle_tool_result callback and manages state transitions.
  """
  def call_tool_result(nil, _tool_name, _tool_result, agent_state) do
    {:ok, agent_state}
  end

  def call_tool_result(agent_module, tool_name, tool_result, agent_state) do
    case agent_module.handle_tool_result(tool_name, tool_result, agent_state) do
      :ok ->
        {:ok, agent_state}

      {:ok, new_state} ->
        {:ok, new_state}

      {:error, _err} ->
        {:error, agent_state}

      other ->
        Logger.warning("[BeamMePrompty] Unexpected handle_tool_result result: #{inspect(other)}")

        {:ok, agent_state}
    end
  rescue
    e ->
      Logger.warning("[BeamMePrompty] Agent callback handle_tool_result failed: #{inspect(e)}")
      {:ok, agent_state}
  end

  @doc """
  Safely updates agent state based on callback status.
  """
  def update_agent_state_from_callback(:ok, new_state, _fallback_state), do: new_state
  def update_agent_state_from_callback(_, _new_state, fallback_state), do: fallback_state
end
