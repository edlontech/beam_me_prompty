defmodule BeamMePrompty.Telemetry do
  @moduledoc """
  Helper module for emitting telemetry events.
  """
  @moduledoc section: :telemetry

  @event_prefix [:beam_me_prompty]

  # --- Agent Execution Span ---

  @doc """
  Emits a telemetry event when agent execution starts.

  This function emits a telemetry event to track the beginning of agent execution,
  including metadata about the agent configuration and input parameters.

  ## Parameters

  - `agent_module` - The agent module being executed
  - `session_id` - Unique identifier for the agent session
  - `input` - Global input data for the agent
  - `initial_agent_state` - The initial state of the agent
  - `opts` - Additional execution options

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :agent_execution, :start]`

  ## Examples

      BeamMePrompty.Telemetry.agent_execution_start(
        MyAgent,
        session_ref,
        %{name: "Alice"},
        %{},
        []
      )

  """
  @spec agent_execution_start(module(), reference(), map(), map(), keyword()) :: :ok
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

  @doc """
  Emits a telemetry event when agent execution stops.

  This function emits a telemetry event to track the completion of agent execution,
  including the reason for stopping and result information.

  ## Parameters

  - `agent_module` - The agent module that was executed
  - `session_id` - Unique identifier for the agent session
  - `reason` - The reason for stopping (e.g., :normal, :error)
  - `result_manager` - The result manager containing execution results

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :agent_execution, :stop]`

  ## Examples

      BeamMePrompty.Telemetry.agent_execution_stop(
        MyAgent,
        session_ref,
        :normal,
        result_manager
      )

  """
  @spec agent_execution_stop(module(), reference(), atom(), term()) :: :ok
  def agent_execution_stop(agent_module, session_id, reason, result_manager) do
    metadata = %{
      agent_module: agent_module,
      session_id: session_id,
      reason: reason,
      num_results: BeamMePrompty.Agent.Internals.ResultManager.completed_count(result_manager)
    }

    :telemetry.execute(
      @event_prefix ++ [:agent_execution, :stop],
      %{system_time: System.system_time(:nanosecond)},
      metadata
    )
  end

  # --- DAG Planning Span ---

  @doc """
  Emits a telemetry event when DAG planning starts.

  This function emits a telemetry event to track the beginning of DAG (Directed Acyclic Graph)
  planning phase, including information about the current state of node completion.

  ## Parameters

  - `agent_module` - The agent module performing DAG planning
  - `session_id` - Unique identifier for the agent session
  - `completed_nodes_count` - Number of nodes already completed in the DAG
  - `total_nodes_count` - Total number of nodes in the DAG

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :dag_planning, :start]`

  ## Examples

      BeamMePrompty.Telemetry.dag_planning_start(
        MyAgent,
        session_ref,
        5,
        10
      )

  """
  @spec dag_planning_start(module(), reference(), non_neg_integer(), non_neg_integer()) :: :ok
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

  @doc """
  Emits a telemetry event when DAG planning stops.

  This function emits a telemetry event to track the completion of DAG planning,
  including detailed information about the planning results and node status.

  ## Parameters

  - `agent_module` - The agent module that performed DAG planning
  - `session_id` - Unique identifier for the agent session
  - `ready_nodes_from_dag_count` - Number of nodes ready for execution from DAG analysis
  - `planned_nodes_count` - Total number of nodes included in the planning
  - `effective_ready_nodes_count` - Number of nodes effectively ready for execution
  - `plan_status` - The status of the planning operation (e.g., :success, :partial)

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :dag_planning, :stop]`

  ## Examples

      BeamMePrompty.Telemetry.dag_planning_stop(
        MyAgent,
        session_ref,
        3,
        5,
        2,
        :success
      )

  """
  @spec dag_planning_stop(
          module(),
          reference(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          atom()
        ) :: :ok
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

  @doc """
  Emits a telemetry event when stage execution starts.

  This function emits a telemetry event to track the beginning of individual stage execution,
  including both the stage module name and the specific DAG node being processed.

  ## Parameters

  - `agent_module` - The agent module containing the stage
  - `session_id` - Unique identifier for the agent session
  - `stage_name` - The stage module's own name from its state
  - `node_name` - The specific node name from the DAG being processed

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :stage_execution, :start]`

  ## Examples

      BeamMePrompty.Telemetry.stage_execution_start(
        MyAgent,
        session_ref,
        :user_input_stage,
        :collect_user_data
      )

  """
  @spec stage_execution_start(module(), reference(), atom(), atom()) :: :ok
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

  @doc """
  Emits a telemetry event when stage execution stops.

  This function emits a telemetry event to track the completion of individual stage execution,
  including the execution result status and payload type for analysis.

  ## Parameters

  - `agent_module` - The agent module containing the stage
  - `session_id` - Unique identifier for the agent session
  - `stage_name` - The stage module's own name from its state
  - `node_name` - The specific node name from the DAG that was processed
  - `result_status` - The execution result status (e.g., :ok, :error)
  - `result_payload` - The payload returned from stage execution

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :stage_execution, :stop]`

  ## Examples

      BeamMePrompty.Telemetry.stage_execution_stop(
        MyAgent,
        session_ref,
        :user_input_stage,
        :collect_user_data,
        :ok,
        %{user_name: "Alice", age: 30}
      )

  """
  @spec stage_execution_stop(module(), reference(), atom(), atom(), atom(), term()) :: :ok
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

  @doc """
  Emits a telemetry event when an LLM call starts.

  This function emits a telemetry event to track the beginning of LLM API calls,
  including information about the model, message count, and available tools.

  ## Parameters

  - `agent_module` - The agent module making the LLM call
  - `session_id` - Unique identifier for the agent session
  - `stage_name` - The stage name making the LLM call
  - `llm_client_module` - The LLM client module (e.g., Anthropic, OpenAI)
  - `model` - The specific model being called (e.g., "claude-3-sonnet")
  - `message_count` - Number of messages in the conversation
  - `tool_count` - Number of tools available for the LLM call

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :llm_call, :start]`

  ## Examples

      BeamMePrompty.Telemetry.llm_call_start(
        MyAgent,
        session_ref,
        :reasoning_stage,
        BeamMePrompty.LLM.Anthropic,
        "claude-3-sonnet",
        3,
        2
      )

  """
  @spec llm_call_start(
          module(),
          reference(),
          atom(),
          module(),
          String.t(),
          non_neg_integer(),
          non_neg_integer()
        ) :: :ok
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

  @doc """
  Emits a telemetry event when an LLM call stops.

  This function emits a telemetry event to track the completion of LLM API calls,
  including the response status and response type for analysis and monitoring.

  ## Parameters

  - `agent_module` - The agent module that made the LLM call
  - `session_id` - Unique identifier for the agent session
  - `stage_name` - The stage name that made the LLM call
  - `llm_client_module` - The LLM client module (e.g., Anthropic, OpenAI)
  - `model` - The specific model that was called
  - `status` - The call status (`:ok` or `:error`)
  - `response_or_error` - The response payload or error information

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :llm_call, :stop]`

  ## Examples

      BeamMePrompty.Telemetry.llm_call_stop(
        MyAgent,
        session_ref,
        :reasoning_stage,
        BeamMePrompty.LLM.Anthropic,
        "claude-3-sonnet",
        :ok,
        [text_part("Hello, how can I help you?")]
      )

  """
  @spec llm_call_stop(module(), reference(), atom(), module(), String.t(), atom(), term()) :: :ok
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

  @doc """
  Emits a telemetry event when tool execution starts.

  This function emits a telemetry event to track the beginning of tool execution,
  including the tool name and argument keys for monitoring tool usage patterns.

  ## Parameters

  - `agent_module` - The agent module executing the tool
  - `session_id` - Unique identifier for the agent session
  - `stage_name` - The stage name executing the tool
  - `tool_name` - The name of the tool being executed
  - `tool_args` - The arguments passed to the tool

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :tool_execution, :start]`

  ## Examples

      BeamMePrompty.Telemetry.tool_execution_start(
        MyAgent,
        session_ref,
        :data_processing_stage,
        :memory_store,
        %{key: "user_data", value: %{name: "Alice"}}
      )

  """
  @spec tool_execution_start(module(), reference(), atom(), atom(), map()) :: :ok
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

  @doc """
  Emits a telemetry event when tool execution stops.

  This function emits a telemetry event to track the completion of tool execution,
  including the execution status and result/error information for monitoring.

  ## Parameters

  - `agent_module` - The agent module that executed the tool
  - `session_id` - Unique identifier for the agent session
  - `stage_name` - The stage name that executed the tool
  - `tool_name` - The name of the tool that was executed
  - `status` - The execution status (`:ok` or `:error`)
  - `result_or_error` - The result payload or error information

  ## Telemetry Event

  Emits: `[:beam_me_prompty, :tool_execution, :stop]`

  ## Examples

      BeamMePrompty.Telemetry.tool_execution_stop(
        MyAgent,
        session_ref,
        :data_processing_stage,
        :memory_store,
        :ok,
        "Data stored successfully"
      )

  """
  @spec tool_execution_stop(module(), reference(), atom(), atom(), atom(), term()) :: :ok
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
      Map.put(
        %{
          agent_module: agent_module,
          session_id: session_id,
          stage_name: stage_name,
          tool_name: tool_name,
          status: status
        },
        elem(detail_type, 0),
        elem(detail_type, 1)
      )

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
        get_payload_type(result_or_error.cause)

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
