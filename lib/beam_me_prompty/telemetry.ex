defmodule BeamMePrompty.Telemetry do
  @moduledoc """
  Helper module for emitting telemetry events.
  """
  @moduledoc section: :telemetry

  @event_prefix [:beam_me_prompty]

  # --- Agent Execution Span ---

  def agent_execution_start(agent_module, session_id, input, initial_agent_state, opts) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      input_keys: Map.keys(input || %{}),
      initial_state_keys: Map.keys(initial_agent_state || %{}),
      opts_keys: Keyword.keys(opts || [])
    }

    :telemetry.execute(
      @event_prefix ++ [:agent_execution, :start],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  def agent_execution_stop(agent_module, session_id, reason, result_manager) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      reason: reason,
      num_results: result_manager |> BeamMePrompty.Agent.Internals.ResultManager.completed_count()
    }

    :telemetry.execute(
      @event_prefix ++ [:agent_execution, :stop],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  # --- DAG Planning Span ---

  def dag_planning_start(agent_module, session_id, completed_nodes_count, total_nodes_count) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      completed_nodes_count: completed_nodes_count,
      total_nodes_count: total_nodes_count
    }

    :telemetry.execute(
      @event_prefix ++ [:dag_planning, :start],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  def dag_planning_stop(
        agent_module,
        session_id,
        ready_nodes_from_dag_count,
        planned_nodes_count,
        effective_ready_nodes_count,
        plan_status
      ) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      ready_nodes_from_dag_count: ready_nodes_from_dag_count,
      planned_nodes_count: planned_nodes_count,
      effective_ready_nodes_count: effective_ready_nodes_count,
      plan_status: plan_status
    }

    :telemetry.execute(
      @event_prefix ++ [:dag_planning, :stop],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  # --- Stage Execution Span ---

  def stage_execution_start(agent_module, session_id, stage_name, node_name) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,

      # This is the stage module's own name from its state
      stage_name: stage_name,

      # This is the specific node_name from the DAG being processed
      node_name: node_name
    }

    :telemetry.execute(
      @event_prefix ++ [:stage_execution, :start],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  def stage_execution_stop(
        agent_module,
        session_id,
        stage_name,
        node_name,
        result_status,
        result_payload
      ) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      stage_name: stage_name,
      node_name: node_name,
      result_status: result_status,
      result_payload_type: get_payload_type(result_payload)
    }

    :telemetry.execute(
      @event_prefix ++ [:stage_execution, :stop],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  defp get_payload_type(payload) when is_binary(payload), do: :binary
  defp get_payload_type(payload) when is_map(payload), do: :map
  defp get_payload_type(payload) when is_list(payload), do: :list
  defp get_payload_type(payload) when is_atom(payload), do: :atom
  defp get_payload_type(payload) when is_number(payload), do: :number
  defp get_payload_type(payload) when is_boolean(payload), do: :boolean
  defp get_payload_type(nil), do: nil
  defp get_payload_type(_), do: :other

  # --- LLM Call Span ---

  def llm_call_start(
        agent_module,
        session_id,
        stage_name,
        llm_client_module,
        model,
        message_count,
        tool_count
      ) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      stage_name: stage_name,
      llm_client_module: llm_client_module,
      model: model,
      message_count: message_count,
      tool_count: tool_count
    }

    :telemetry.execute(
      @event_prefix ++ [:llm_call, :start],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  def llm_call_stop(
        agent_module,
        session_id,
        stage_name,
        llm_client_module,
        model,
        status,
        response_or_error
      ) do
    response_type = determine_llm_response_type(status, response_or_error)

    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      stage_name: stage_name,
      llm_client_module: llm_client_module,
      model: model,
      status: status,
      response_type: response_type
    }

    :telemetry.execute(
      @event_prefix ++ [:llm_call, :stop],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  defp determine_llm_response_type(:ok, response_or_error) do
    cond do
      is_map(response_or_error) and Map.has_key?(response_or_error, :function_call) ->
        :function_call

      # Assuming it's a list of content parts
      is_list(response_or_error) ->
        :list_of_parts

      is_binary(response_or_error) ->
        :text

      # Could be structured response
      is_map(response_or_error) ->
        :map

      true ->
        :unknown_ok_response
    end
  end

  defp determine_llm_response_type(:error, response_or_error) do
    cond do
      is_struct(response_or_error) ->
        response_or_error.__struct__

      is_atom(response_or_error) ->
        response_or_error

      is_map(response_or_error) and Map.has_key?(response_or_error, :__struct__) ->
        Map.get(response_or_error, :__struct__)

      # Generic map error if not a struct
      is_map(response_or_error) ->
        :map_error

      true ->
        :unknown_error
    end
  end

  # --- Tool Execution Span ---

  def tool_execution_start(agent_module, session_id, stage_name, tool_name, tool_args) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      stage_name: stage_name,
      tool_name: tool_name,
      tool_args_keys: Map.keys(tool_args || %{})
    }

    :telemetry.execute(
      @event_prefix ++ [:tool_execution, :start],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  def tool_execution_stop(
        agent_module,
        session_id,
        stage_name,
        tool_name,
        status,
        result_or_error
      ) do
    detail_type = determine_tool_execution_detail_type(status, result_or_error)

    metadata =
      %{
        agent_module: agent_module,
        session_id: session_id,
        stage_name: stage_name,
        tool_name: tool_name,
        status: status
      }
      |> Map.put(elem(detail_type, 0), elem(detail_type, 1))

    :telemetry.execute(
      @event_prefix ++ [:tool_execution, :stop],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  defp determine_tool_execution_detail_type(:ok, result_or_error) do
    {:result_type, get_payload_type(result_or_error)}
  end

  defp determine_tool_execution_detail_type(:error, result_or_error) do
    reason = determine_tool_error_reason_type(result_or_error)
    {:error_reason_type, reason}
  end

  defp determine_tool_error_reason_type(result_or_error) do
    cond do
      is_struct(result_or_error, BeamMePrompty.LLM.Errors.ToolError) ->
        result_or_error.cause |> get_payload_type()

      is_struct(result_or_error) ->
        result_or_error.__struct__

      is_atom(result_or_error) ->
        result_or_error

      is_map(result_or_error) ->
        handle_map_error_type(result_or_error)

      is_tuple(result_or_error) ->
        handle_tuple_error_type(result_or_error)

      true ->
        :unknown_error
    end
  end

  defp handle_map_error_type(result_or_error) do
    if Map.has_key?(result_or_error, :__struct__) do
      Map.get(result_or_error, :__struct__)
    else
      :map_error
    end
  end

  defp handle_tuple_error_type(result_or_error) do
    # Handle {error_atom, stacktrace}
    if elem(result_or_error, 1) == [] do
      elem(result_or_error, 0) |> get_payload_type()
    else
      :unknown_error
    end
  end
end
