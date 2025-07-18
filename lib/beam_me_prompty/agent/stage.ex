defmodule BeamMePrompty.Agent.Stage do
  @moduledoc """
  A GenStateMachine implementation that handles the execution of individual stages within a BeamMePrompty Agent's DAG.

  This module is responsible for:

  * Processing LLM interactions for a single stage/node in the execution graph
  * Handling tool calling functionality, allowing LLMs to invoke tools during execution
  * Managing message history and state for each stage
  * Communicating results back to the parent agent process

  Each stage operates independently, processing its assigned node's configuration, executing
  LLM calls with appropriate context, handling any tool invocations, and returning the final
  result to the caller.

  The state machine primarily stays in an `:idle` state, processing execution requests 
  as they arrive and maintaining its conversation history between executions.

  This module is part of the internal execution engine of BeamMePrompty and is typically
  managed by the `BeamMePrompty.Agent.Internals` module through a supervisor.
  """
  @moduledoc section: :agent_stage_and_execution

  use GenStateMachine, callback_mode: :state_functions

  require Logger

  alias BeamMePrompty.Agent.Stage.AgentCallbacks
  alias BeamMePrompty.Agent.Stage.LLMProcessor
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.Errors
  alias BeamMePrompty.Telemetry

  defstruct [
    :stage_name,
    :session_id,
    :messages,
    :tool_responses,
    :agent_module,
    :current_agent_state
  ]

  @typedoc """
  Represents the internal state of a stage process.

  This struct maintains the state for a single stage within an agent's execution DAG,
  including the stage configuration, message history, and current execution context.

  ## Fields

  - `stage_name` - The name of the stage (atom or string)
  - `session_id` - Unique identifier for the agent session
  - `messages` - List of messages in the conversation history
  - `tool_responses` - List of tool execution responses
  - `agent_module` - The agent module this stage belongs to
  - `current_agent_state` - Current state of the agent including memory manager
  """
  @type t() :: %__MODULE__{
          stage_name: atom | String.t(),
          session_id: reference(),
          messages: list(),
          tool_responses: list(),
          agent_module: module,
          current_agent_state: map()
        }

  @doc """
  Starts a new stage GenStateMachine process.

  This function creates a new stage process that can handle the execution of a single
  stage within an agent's DAG. The stage process manages LLM interactions, tool calls,
  and message history for its assigned stage.

  ## Parameters

  - `stage` - A tuple containing `{stage_name, session_id, agent_module}`

  ## Returns

  - `{:ok, pid}` - The started GenStateMachine process
  - `{:error, reason}` - If the process fails to start

  ## Examples

      BeamMePrompty.Agent.Stage.start_link({
        :user_input_stage,
        session_ref,
        MyAgent
      })

  """
  @spec start_link({atom() | String.t(), reference(), module()}) :: GenStateMachine.on_start()
  def start_link(stage) do
    GenStateMachine.start_link(__MODULE__, stage, [])
  end

  @doc """
  Initializes the stage GenStateMachine.

  This callback is invoked when the stage process starts. It sets up the initial
  state with the stage name, session ID, agent module, and empty message history.

  ## Parameters

  - `{stage_name, session_id, agent_module}` - Initialization tuple containing:
    - `stage_name` - The name of the stage (atom or string)
    - `session_id` - Unique session identifier
    - `agent_module` - The agent module this stage belongs to

  ## Returns

  - `{:ok, :idle, initial_data}` - Initial state with stage data

  ## State Machine Flow

  The stage starts in the `:idle` state and transitions to `:executing_llm` when
  processing execution requests.

  """
  @impl true
  def init({stage_name, session_id, agent_module}) do
    actual_stage_name =
      case stage_name do
        {s_name} when is_atom(s_name) or is_binary(s_name) -> s_name
        s_name -> s_name
      end

    initial_data = %__MODULE__{
      stage_name: actual_stage_name,
      messages: [],
      tool_responses: [],
      session_id: session_id,
      agent_module: agent_module,
      current_agent_state: %{}
    }

    {:ok, :idle, initial_data}
  end

  @doc """
  Handles stage execution requests in the idle state.

  This state function processes incoming execution requests by setting up the
  execution context, calling stage start callbacks, and transitioning to the
  executing state.

  ## Parameters

  - `:cast` - Event type for asynchronous messages
  - `{:execute, node_name, node_def, node_ctx, caller_pid}` - Execution request with:
    - `node_name` - The DAG node name being executed
    - `node_def` - The stage definition containing LLM configuration
    - `node_ctx` - Execution context including global input and dependencies
    - `caller_pid` - Process ID to send results back to
  - `data` - Current stage state data

  ## Returns

  - `{:next_state, :executing_llm, updated_data, next_event}` - Transitions to executing state

  ## Side Effects

  - Emits stage execution start telemetry
  - Calls stage start callbacks
  - Updates agent state with memory manager

  """
  def idle(:cast, {:execute, node_name, node_def, node_ctx, caller_pid}, data) do
    Telemetry.stage_execution_start(
      data.agent_module,
      data.session_id,
      data.stage_name,
      node_name
    )

    agent_module_from_ctx = node_ctx[:agent_module]
    agent_state_from_ctx = node_ctx[:current_agent_state]
    agent_spec = node_ctx[:agent_spec]

    Logger.debug(
      "[BeamMePrompty] Agent [#{agent_spec.agent_config.name}](v: #{agent_spec.agent_config.version})(sid: #{inspect(data.session_id)}) running node [#{inspect(node_name)}]"
    )

    # Ensure memory_manager is in the agent state
    agent_state_with_memory =
      Map.put(
        agent_state_from_ctx || %{},
        :memory_manager,
        node_ctx[:memory_manager]
      )

    data_with_agent_context = %{
      data
      | agent_module: agent_module_from_ctx,
        current_agent_state: agent_state_with_memory
    }

    AgentCallbacks.call_stage_start(
      agent_module_from_ctx,
      node_def,
      data_with_agent_context.current_agent_state
    )

    execution_params = {node_name, node_def, node_ctx, caller_pid}

    {:next_state, :executing_llm, data_with_agent_context,
     {:next_event, :internal, {:execute, execution_params}}}
  end

  def idle(:cast, {:update_messages, new_message, reset_history}, data) do
    updated_messages =
      MessageManager.update_message_history(data.messages, new_message, reset_history)

    updated_data = %{data | messages: updated_messages}
    {:keep_state, updated_data}
  end

  # --- :executing_llm State ---

  @doc """
  Handles LLM execution in the executing state.

  This state function processes the actual stage execution by calling the LLM,
  handling the results, and sending responses back to the caller.

  ## Parameters

  - `:internal` - Internal event type for state machine transitions
  - `{:execute, {node_name, node_def, node_ctx, caller_pid}}` - Execution parameters
  - `data` - Current stage state data

  ## Returns

  - `{:next_state, :idle, final_stage_data}` - Returns to idle state after execution

  ## Execution Flow

  1. Executes the stage using `do_execute_stage/3`
  2. Formats the result as `{:ok, result}` or `{:error, error}`
  3. Emits stage execution stop telemetry
  4. Sends the result to the caller process
  5. Transitions back to idle state
  """
  def executing_llm(
        :internal,
        {:execute, {node_name, node_def, node_ctx, caller_pid}},
        data
      ) do
    {stage_execution_result, result_payload, final_stage_data} =
      do_execute_stage(node_def, node_ctx, data)

    response_payload =
      case stage_execution_result do
        :ok -> {:ok, result_payload}
        :error -> {:error, result_payload}
      end

    Telemetry.stage_execution_stop(
      final_stage_data.agent_module,
      final_stage_data.session_id,
      final_stage_data.stage_name,
      node_name,
      stage_execution_result,
      result_payload
    )

    send(
      caller_pid,
      {:stage_response, node_name, response_payload, final_stage_data.current_agent_state}
    )

    {:next_state, :idle, final_stage_data}
  end

  def executing_llm(_event_type, _event_content, _data) do
    {:keep_state_and_data, :postpone}
  end

  @doc """
  Handles stage process termination.

  This callback is invoked when the stage process terminates. It provides a place
  for cleanup operations, though currently no special cleanup is needed.

  ## Parameters

  - `_reason` - The termination reason (ignored)
  - `_state` - The current state when terminating (ignored)
  - `_data` - The current stage data when terminating (ignored)

  ## Returns

  - `:ok` - Successful termination
  """
  @impl true
  def terminate(_reason, _state, _data) do
    :ok
  end

  # Executes the actual stage processing including LLM calls and result handling.
  #
  # This function coordinates the stage execution by:
  # 1. Preparing input data by merging global input with dependency results
  # 2. Calling the LLM processor to handle the LLM interaction
  # 3. Processing the results and updating stage state
  #
  # ## Parameters
  #
  # - `stage_node_def` - The stage definition containing LLM configuration
  # - `exec_context` - Execution context with global input and dependency results
  # - `stage_data` - Current stage state data
  #
  # ## Returns
  #
  # - `{:ok, result, updated_stage_data}` - Successful execution
  # - `{:error, error_class, updated_stage_data}` - Failed execution
  #
  # ## Data Flow
  #
  # The function merges global input with dependency results to provide complete
  # context to the LLM, then processes the response and updates the stage state.
  defp do_execute_stage(stage_node_def, exec_context, stage_data) do
    # Get agent_spec from execution context for better logging
    agent_spec = exec_context[:agent_spec]

    Logger.debug("""
    [BeamMePrompty] Agent [#{agent_spec.agent_config.name}](v: #{agent_spec.agent_config.version})(sid: #{inspect(stage_data.session_id)}) Stage [#{inspect(stage_data.stage_name)}] executing.
    """)

    global_input = exec_context[:global_input] || %{}
    dependency_results = exec_context[:dependency_results] || %{}
    inputs_for_llm = Map.merge(global_input, dependency_results)

    case LLMProcessor.maybe_call_llm(
           stage_node_def.llm,
           inputs_for_llm,
           stage_data.messages,
           stage_data.agent_module,
           stage_data.current_agent_state,
           stage_data.session_id,
           stage_data.stage_name
         ) do
      {:ok, llm_result, updated_messages_history, final_agent_state_after_llm} ->
        Logger.debug("""
        [BeamMePrompty] Agent [#{agent_spec.agent_config.name}](v: #{agent_spec.agent_config.version})(sid: #{inspect(stage_data.session_id)}) Stage [#{inspect(stage_data.stage_name)}] finished.
        """)

        updated_stage_data = %{
          stage_data
          | messages: updated_messages_history,
            current_agent_state: final_agent_state_after_llm
        }

        {:ok, llm_result, updated_stage_data}

      {:error, error_reason, updated_messages_history, final_agent_state_after_llm_error} ->
        updated_stage_data_on_error = %{
          stage_data
          | messages: updated_messages_history,
            current_agent_state: final_agent_state_after_llm_error
        }

        {:error, Errors.to_class(error_reason), updated_stage_data_on_error}
    end
  end
end
