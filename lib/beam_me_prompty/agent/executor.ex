defmodule BeamMePrompty.Agent.Executor do
  @moduledoc """
  Agent execution engine for BeamMePrompty.

  This module provides a behavior and execution infrastructure for BeamMePrompty agents.
  It handles the lifecycle of agent execution including starting, monitoring, and error handling
  of agents as they process through their defined stages using a directed acyclic graph (DAG).

  ## Behavior

  When using this module, you can implement the required callbacks:

    * `handle_init/2` - Called when the agent is initialized with its DAG
    * `handle_error/2` - Called when errors occur during execution
    * `handle_plan/2` - Called during planning phase when determining ready nodes
    * `handle_batch_start/2` - Called when a batch of nodes is about to be executed
    * `handle_stage_start/2` - Called when a stage begins execution
    * `handle_stage_finish/3` - Called when a stage completes execution
    * `handle_batch_complete/3` - Called when a batch of nodes completes execution
    * `handle_tool_call/3` - Called when an LLM invokes a tool
    * `handle_tool_result/3` - Called after a tool execution completes
    * `handle_progress/2` - Periodically called to report execution progress
    * `handle_complete/2` - Called when all stages complete
    * `handle_timeout/2` - Called when execution times out
    * `handle_pause/2` - Called when execution is paused
    * `handle_resume/2` - Called when execution is resumed
  """
  @moduledoc section: :agent_core_and_lifecycle

  alias BeamMePrompty.Agent.ExecutorOptions
  alias BeamMePrompty.DAG
  alias BeamMePrompty.Errors

  @type state :: map()

  @type handle_error_response ::
          {:retry, state()}
          | {:stop, cause :: term()}
          | {:restart, reason :: term()}

  @doc """
  Called when the agent is initialized.

  This callback is invoked during agent startup to allow custom initialization
  logic and state setup based on the agent's DAG configuration.

  ## Parameters

  - `dag` - The directed acyclic graph defining the agent's stages
  - `inner_state` - The initial inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Initialization successful with updated state
  - `{:error, reason}` - Initialization failed

  ## Use Cases

  - Setup initial state based on DAG configuration
  - Validate agent configuration
  - Initialize external resources
  - Setup monitoring or logging

  ## Default Implementation

  The default implementation returns `{:ok, state}` unchanged.

  """
  @callback handle_init(dag :: DAG.dag(), inner_state :: map()) :: {:ok, map()} | {:error, term()}

  @doc """
  Called when an error occurs during agent execution.

  This callback allows custom error handling logic to determine how the agent
  should respond to different types of errors.

  ## Parameters

  - `error` - The error class module that occurred
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:retry, updated_state}` - Retry the operation with updated state
  - `{:stop, cause}` - Stop the agent with the given cause
  - `{:restart, reason}` - Restart the agent with the given reason

  ## Error Handling Strategies

  - **Retry**: For transient errors that might succeed on retry
  - **Stop**: For permanent errors that cannot be recovered
  - **Restart**: For errors that require a fresh start

  ## Default Implementation

  - Retries for `ExternalError` types
  - Stops for all other error types

  """
  @callback handle_error(Errors.class_module(), inner_state :: map()) :: handle_error_response

  @doc """
  Called during the planning phase to determine which nodes to execute.

  This callback allows custom logic to filter or prioritize ready nodes
  before they are executed.

  ## Parameters

  - `ready_nodes` - List of nodes that are ready for execution based on dependencies
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, selected_nodes, updated_state}` - Selected nodes and updated state
  - `{:error, reason}` - Planning failed

  ## Planning Strategies

  - **All Ready**: Execute all ready nodes (default behavior)
  - **Priority Based**: Execute nodes based on priority
  - **Resource Based**: Execute nodes based on resource availability
  - **Conditional**: Execute nodes based on state conditions

  ## Default Implementation

  Returns all ready nodes unchanged.

  """
  @callback handle_plan(ready_nodes :: [atom()], inner_state :: map()) ::
              {:ok, [atom()], map()} | {:error, term()}

  @doc """
  Called when a batch of nodes is about to be executed.

  This callback is invoked before dispatching nodes to stage workers,
  allowing preparation and state updates.

  ## Parameters

  - `nodes_to_execute` - List of tuples containing node details:
    - `atom()` - Node name
    - `map()` - Node definition
    - `map()` - Node execution context
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Batch start successful with updated state
  - `{:error, reason}` - Batch start failed

  ## Use Cases

  - Prepare resources for batch execution
  - Log batch start information
  - Update state based on batch composition
  - Setup batch-specific configuration

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_batch_start(nodes_to_execute :: [{atom(), map(), map()}], inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called when a stage begins execution.

  This callback is invoked when a stage worker starts processing a node,
  allowing for stage-specific setup and monitoring.

  ## Parameters

  - `stage` - The stage definition containing configuration and metadata
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `:ok` - Stage start acknowledged

  ## Use Cases

  - Log stage start information
  - Setup stage-specific resources
  - Update monitoring or metrics
  - Initialize stage-specific state

  ## Default Implementation

  Returns `:ok` without any action.

  """
  @callback handle_stage_start(stage :: map(), inner_state :: map()) :: :ok

  @doc """
  Called when a stage completes execution.

  This callback is invoked after a stage worker finishes processing a node,
  allowing for result processing and state updates.

  ## Parameters

  - `stage` - The stage definition that completed
  - `result` - The result returned by the stage
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Stage finish successful with updated state
  - `{:error, reason}` - Stage finish processing failed

  ## Use Cases

  - Process and validate stage results
  - Update state based on stage outcomes
  - Log stage completion information
  - Prepare data for dependent stages

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_stage_finish(stage :: map(), result :: map(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called when a batch of nodes completes execution.

  This callback is invoked after all nodes in a batch have finished processing,
  allowing for batch-level result processing and state updates.

  ## Parameters

  - `batch_results` - Map of node names to their execution results
  - `pending_nodes` - List of nodes still pending execution
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Batch completion successful with updated state
  - `{:error, reason}` - Batch completion processing failed

  ## Use Cases

  - Aggregate results from multiple nodes
  - Update state based on batch outcomes
  - Log batch completion information
  - Prepare for next batch execution

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_batch_complete(
              batch_results :: map(),
              pending_nodes :: [atom()],
              inner_state :: map()
            ) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called when an LLM invokes a tool during stage execution.

  This callback is invoked before a tool is executed, allowing for
  tool call validation, logging, and state updates.

  ## Parameters

  - `tool_name` - The name of the tool being called
  - `tool_args` - The arguments passed to the tool
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Tool call acknowledged with updated state
  - `{:error, reason}` - Tool call rejected or failed

  ## Use Cases

  - Validate tool arguments
  - Log tool usage for monitoring
  - Update state based on tool interactions
  - Implement tool access control

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_tool_call(tool_name :: atom(), tool_args :: map(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called after a tool execution completes.

  This callback is invoked after a tool has finished execution, allowing for
  result processing, validation, and state updates.

  ## Parameters

  - `tool_name` - The name of the tool that was executed
  - `result` - The result returned by the tool execution
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Tool result processed with updated state
  - `{:error, reason}` - Tool result processing failed

  ## Use Cases

  - Validate tool execution results
  - Log tool outcomes for monitoring
  - Update state based on tool results
  - Transform results for downstream stages

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_tool_result(tool_name :: atom(), result :: term(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called periodically to report execution progress.

  This callback is invoked during agent execution to provide progress updates
  and allow for monitoring and state adjustments.

  ## Parameters

  - `progress` - Progress information map containing:
    - `completed` - Number of completed nodes
    - `total` - Total number of nodes in the DAG
    - `elapsed_ms` - Elapsed time in milliseconds
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Progress acknowledged with updated state

  ## Use Cases

  - Update progress monitoring systems
  - Log execution progress
  - Adjust execution parameters based on progress
  - Implement progress-based timeouts

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_progress(
              progress :: %{completed: integer(), total: integer(), elapsed_ms: integer()},
              inner_state :: map()
            ) ::
              {:ok, map()}

  @doc """
  Called when all stages complete execution.

  This callback is invoked after all nodes in the DAG have finished processing,
  allowing for final result processing and cleanup.

  ## Parameters

  - `results` - Map of all execution results indexed by node name
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Completion processed with updated state
  - `{:error, reason}` - Completion processing failed

  ## Use Cases

  - Aggregate final results
  - Perform cleanup operations
  - Log completion information
  - Prepare final output

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_complete(results :: map(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called when execution times out.

  This callback is invoked when various timeout conditions occur during
  agent execution, allowing for custom timeout handling.

  ## Parameters

  - `timeout_type` - The type of timeout that occurred:
    - `:execution` - Overall execution timeout
    - `:stage` - Individual stage timeout
    - `:tool` - Tool execution timeout
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:retry, updated_state}` - Retry the operation with updated state
  - `{:stop, cause}` - Stop the agent with the given cause
  - `{:restart, reason}` - Restart the agent with the given reason

  ## Timeout Handling Strategies

  - **Retry**: For transient timeouts that might succeed on retry
  - **Stop**: For permanent timeouts that indicate system issues
  - **Restart**: For timeouts that require a fresh start

  ## Default Implementation

  Stops the agent with `:timeout` reason.

  """
  @callback handle_timeout(timeout_type :: :execution | :stage | :tool, inner_state :: map()) ::
              handle_error_response()

  @doc """
  Called when execution is paused.

  This callback is invoked when the agent execution is paused, allowing for
  pause-specific handling and state preservation.

  ## Parameters

  - `reason` - The reason for pausing execution
  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Pause handled with updated state
  - `{:error, reason}` - Pause handling failed

  ## Use Cases

  - Save execution state for later resumption
  - Release resources during pause
  - Log pause information
  - Notify external systems of pause

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_pause(reason :: term(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called when execution is resumed.

  This callback is invoked when the agent execution is resumed after being
  paused, allowing for resume-specific handling and state restoration.

  ## Parameters

  - `inner_state` - The current inner state of the agent

  ## Returns

  - `{:ok, updated_state}` - Resume handled with updated state
  - `{:error, reason}` - Resume handling failed

  ## Use Cases

  - Restore execution state from pause
  - Reinitialize resources after pause
  - Log resume information
  - Notify external systems of resume

  ## Default Implementation

  Returns the state unchanged.

  """
  @callback handle_resume(inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour BeamMePrompty.Agent.Executor

      alias BeamMePrompty.Errors.External, as: ExternalError

      @doc false
      def handle_init(_dag, state), do: {:ok, state}

      @doc false
      def handle_error({error, reason}, state)
          when is_exception(error, ExternalError),
          do: {:retry, state}

      def handle_error(error, _state), do: {:stop, error}

      @doc false
      def handle_plan(ready_nodes, state), do: {:ok, ready_nodes, state}

      @doc false
      def handle_batch_start(_nodes_to_execute, state), do: {:ok, state}

      @doc false
      def handle_stage_start(_stage, _state), do: :ok

      @doc false
      def handle_stage_finish(_stage, _result, state), do: {:ok, state}

      @doc false
      def handle_batch_complete(_batch_results, _pending_nodes, state), do: {:ok, state}

      @doc false
      def handle_tool_call(_tool_name, _tool_args, state), do: {:ok, state}

      @doc false
      def handle_tool_result(_tool_name, _result, state), do: {:ok, state}

      @doc false
      def handle_progress(_progress, state), do: {:ok, state}

      @doc false
      def handle_complete(_results, state), do: {:ok, state}

      @doc false
      def handle_timeout(_timeout_type, state), do: {:stop, :timeout}

      @doc false
      def handle_pause(_reason, state), do: {:ok, state}

      @doc false
      def handle_resume(state), do: {:ok, state}

      defoverridable handle_init: 2,
                     handle_error: 2,
                     handle_plan: 2,
                     handle_batch_start: 2,
                     handle_stage_start: 2,
                     handle_stage_finish: 3,
                     handle_batch_complete: 3,
                     handle_tool_call: 3,
                     handle_tool_result: 3,
                     handle_progress: 2,
                     handle_complete: 2,
                     handle_timeout: 2,
                     handle_pause: 2,
                     handle_resume: 1
    end
  end

  @doc """
  Fetches the current state of a running agent.

  ## Options
    * `pid_or_name` - The PID or registered name of the agent process
    * `timeout` - Optional timeout value in milliseconds (default: 5000)

  ## Examples
      
      # Fetch state by PID
      {:ok, pid} = BeamMePrompty.Agents.Executor.start_link(MyAgent, %{input: "data"}, %{}, [])
      {:ok, state} = BeamMePrompty.Agents.Executor.get_state(pid)
      
      # Fetch state by name
      BeamMePrompty.Agents.Executor.start_link(MyAgent, %{input: "data"}, %{}, [name: MyAgent])
      {:ok, state} = BeamMePrompty.Agents.Executor.get_state(MyAgent)
  """
  def get_results(pid_or_name, timeout \\ 5000),
    do: GenStateMachine.call(pid_or_name, :get_results, timeout)

  @doc """
  Sends a message to the agent's underlying `GenStateMachine`.

  This function handles two cases for the `pid_or_session_id` argument:
  - If a PID is provided, the message is sent directly to that process.
  - If a session ID (any other term) is provided, it's resolved to a
    process name using `{:via, Registry, {:agents, session_id}}`
    before sending the message.

  The message is wrapped in a `{:user, [message]}` tuple before being cast.
  """
  @spec message_agent(pid() | reference(), BeamMePrompty.Agent.Dsl.Part.parts()) ::
          :ok | {:error, term()}
  def message_agent(pid, message) when is_pid(pid) do
    do_send_message(pid, message)
  end

  def message_agent(session_id, message) do
    session_id
    |> executor_id()
    |> do_send_message(message)
  end

  defp do_send_message(pid_or_session, message) do
    message = {:user, [message]}

    GenStateMachine.call(pid_or_session, {:message, message})
  end

  @doc """
  Executes an agent synchronously and returns the results.

  ## Options
    * `module` - The agent module to execute
    * `input` - The input data for the agent
    * `state` - The initial state (optional, defaults to empty map)
    * `opts` - Additional options (see `start_link/4`)
    * `timeout` - Optional timeout value in milliseconds (default: 30000)

  ## Returns
    * `{:ok, results}` - The agent executed successfully
    * `{:error, reason}` - The agent failed to execute

  ## Examples
      
      # Execute an agent synchronously
      {:ok, results} = BeamMePrompty.Agents.Executor.execute(MyAgent, %{input: "data"})
  """
  def execute(agent_spec, input, state, opts, timeout) do
    # Store original trap_exit setting to restore it later
    previous_trap_exit = Process.flag(:trap_exit, true)

    try do
      case start_link(agent_spec, input, state, opts) do
        {:ok, pid} ->
          # Monitor is still useful for normal termination and error handling
          ref = Process.monitor(pid)

          # Wait for completion, handle EXIT signals and monitor messages
          result = wait_for_completion(pid, ref, timeout)

          # Clean up the monitor if still needed
          Process.demonitor(ref, [:flush])

          # Ensure the process is terminated if it's still alive
          if Process.alive?(pid), do: Process.exit(pid, :normal)

          result

        {:error, _} = error ->
          # Failed to start the agent
          error
      end
    after
      # Restore original trap_exit setting
      Process.flag(:trap_exit, previous_trap_exit)
    end
  end

  @doc """
  Starts an agent process and links it to the calling process.

  This function initializes and starts an agent execution process using the provided
  agent specification, input data, and configuration options.

  ## Parameters

  - `agent_spec` - The agent specification containing stages and configuration
  - `input` - Global input data available to all stages
  - `state` - Initial agent state (typically an empty map)
  - `opts` - Execution options (see ExecutorOptions for available options)

  ## Returns

  - `{:ok, pid}` - Successfully started agent process
  - `{:error, reason}` - If startup fails

  ## Process Registration

  The agent process is registered with the Registry using the session_id from opts
  (or a generated reference if not provided). This allows the agent to be accessed
  by session_id using `message_agent/2` and other functions.

  ## Startup Flow

  1. Builds DAG from agent specification stages
  2. Validates the DAG structure
  3. Validates execution options
  4. Starts GenStateMachine with BeamMePrompty.Agent.Internals
  5. Registers the process for later access

  ## Examples

      {:ok, pid} = BeamMePrompty.Agent.Executor.start_link(
        agent_spec,
        %{user_input: "Hello"},
        %{},
        [session_id: make_ref()]
      )
  """
  def start_link(agent_spec, input, state, opts) do
    dag = DAG.build(agent_spec.stages)
    session_id = Keyword.get(opts, :session_id, make_ref())

    with :ok <- DAG.validate(dag),
         {:ok, validated_opts} <- ExecutorOptions.validate(opts) do
      init = {session_id, dag, input, state, opts, agent_spec}

      genserver_opts = [name: executor_id(session_id)]

      genserver_opts =
        case Keyword.get(validated_opts, :hibernate_after) do
          nil -> genserver_opts
          hibernate_after -> Keyword.put(genserver_opts, :hibernate_after, hibernate_after)
        end

      GenStateMachine.start_link(BeamMePrompty.Agent.Internals, init, genserver_opts)
    end
  end

  defp executor_id(session_id),
    do: {:via, Registry, {:agents, session_id}}

  defp wait_for_completion(pid, ref, timeout) do
    end_time = System.monotonic_time(:millisecond) + timeout

    wait_loop(pid, ref, end_time)
  end

  defp wait_loop(pid, ref, end_time) do
    time_left = end_time - System.monotonic_time(:millisecond)

    if time_left <= 0 do
      {:error, BeamMePrompty.Errors.ExecutionError.exception(cause: :timeout)}
    else
      receive do
        # Process terminated normally
        {:DOWN, ^ref, :process, ^pid, :normal} ->
          case get_results(pid) do
            {:ok, :completed, results} ->
              {:ok, results}

            _other ->
              {:error,
               BeamMePrompty.Errors.ExecutionError.exception(cause: :abnormal_termination)}
          end

        # Process crashed with an error
        {:DOWN, ^ref, :process, ^pid, reason} when reason != :normal ->
          {:error, reason}

        # EXIT signal from the linked process - normal termination
        {:EXIT, ^pid, :normal} ->
          case get_results(pid) do
            {:ok, :completed, results} ->
              {:ok, results}

            _other ->
              {:error,
               BeamMePrompty.Errors.ExecutionError.exception(cause: :incomplete_execution)}
          end

        # EXIT signal with error reason
        {:EXIT, ^pid, reason} ->
          {:error, reason}
      after
        # Check periodically if we have results but haven't received a message yet
        min(100, max(0, time_left)) ->
          case check_completion(pid) do
            :continue -> wait_loop(pid, ref, end_time)
            result -> result
          end
      end
    end
  end

  defp check_completion(pid) do
    case get_results(pid) do
      {:ok, :completed, results} ->
        Process.exit(pid, :normal)
        {:ok, results}

      {:ok, :idle, _results} ->
        :continue

      {:ok, _} ->
        :continue

      error ->
        error
    end
  end
end
