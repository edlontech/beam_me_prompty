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
    * `handle_cleanup/2` - Called during termination to ensure resource cleanup
    * `handle_timeout/2` - Called when execution times out
    * `handle_pause/2` - Called when execution is paused
    * `handle_resume/2` - Called when execution is resumed
  """

  alias BeamMePrompty.DAG
  alias BeamMePrompty.Agent.ExecutorOptions
  alias BeamMePrompty.Errors

  @type state :: map()

  @type handle_error_response ::
          {:retry, state()}
          | {:stop, cause :: term()}
          | {:restart, reason :: term()}

  @callback handle_init(dag :: DAG.dag(), inner_state :: map()) :: {:ok, map()} | {:error, term()}

  @callback handle_error(Errors.class_module(), inner_state :: map()) :: handle_error_response

  @callback handle_plan(ready_nodes :: [atom()], inner_state :: map()) ::
              {:ok, [atom()], map()} | {:error, term()}

  @callback handle_batch_start(nodes_to_execute :: [{atom(), map(), map()}], inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback handle_stage_start(stage :: map(), inner_state :: map()) :: :ok

  @callback handle_stage_finish(stage :: map(), result :: map(), inner_state :: map()) :: :ok

  @callback handle_batch_complete(
              batch_results :: map(),
              pending_nodes :: [atom()],
              inner_state :: map()
            ) ::
              {:ok, map()} | {:error, term()}

  @callback handle_tool_call(tool_name :: atom(), tool_args :: map(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback handle_tool_result(tool_name :: atom(), result :: term(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback handle_progress(
              progress :: %{completed: integer(), total: integer(), elapsed_ms: integer()},
              inner_state :: map()
            ) ::
              {:ok, map()}

  @callback handle_complete(results :: map(), inner_state :: map()) :: :ok

  @callback handle_cleanup(execution_status :: :completed | :error, inner_state :: map()) :: :ok

  @callback handle_timeout(timeout_type :: :execution | :stage | :tool, inner_state :: map()) ::
              handle_error_response()

  @callback handle_pause(reason :: term(), inner_state :: map()) ::
              {:ok, map()} | {:error, term()}

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
          do: {:retry, reason, state}

      def handle_error(error, _state), do: {:stop, error}

      @doc false
      def handle_plan(ready_nodes, state), do: {:ok, ready_nodes, state}

      @doc false
      def handle_batch_start(_nodes_to_execute, state), do: {:ok, state}

      @doc false
      def handle_stage_start(_stage, _state), do: :ok

      @doc false
      def handle_stage_finish(_stage, _result, _state), do: :ok

      @doc false
      def handle_batch_complete(_batch_results, _pending_nodes, state), do: {:ok, state}

      @doc false
      def handle_tool_call(_tool_name, _tool_args, state), do: {:ok, state}

      @doc false
      def handle_tool_result(_tool_name, _result, state), do: {:ok, state}

      @doc false
      def handle_progress(_progress, state), do: {:ok, state}

      @doc false
      def handle_complete(_results, _state), do: :ok

      @doc false
      def handle_cleanup(_execution_status, _state), do: :ok

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
                     handle_cleanup: 2,
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
  def get_results(pid_or_name, timeout \\ 5000) do
    GenStateMachine.call(pid_or_name, :get_results, timeout)
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
  def execute(module, input, state, opts, timeout) do
    case start_link(module, input, state, opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        # Poll for completion with timeout
        result = poll_for_completion(pid, timeout)

        # Clean up the monitor
        Process.demonitor(ref, [:flush])

        # Ensure the process is terminated if it's still alive
        if Process.alive?(pid), do: Process.exit(pid, :normal)

        result

      {:error, _} = error ->
        # Failed to start the agent
        error
    end
  end

  def start_link(module, input, state, opts) do
    dag = DAG.build(module.stages())
    session_id = Keyword.get(opts, :session_id, make_ref())

    with :ok <- DAG.validate(dag),
         {:ok, opts} <- ExecutorOptions.validate(opts) do
      init = {dag, input, state, opts, module}

      GenStateMachine.start_link(BeamMePrompty.Agent.Internals, init,
        name: executor_id(session_id)
      )
    end
  end

  defp poll_for_completion(pid, timeout, interval \\ 100) do
    end_time = System.monotonic_time(:millisecond) + timeout

    poll_loop(pid, end_time, interval)
  end

  defp poll_loop(pid, end_time, interval) do
    case check_completion(pid) do
      :continue ->
        current_time = System.monotonic_time(:millisecond)

        if current_time < end_time do
          Process.sleep(interval)
          poll_loop(pid, end_time, interval)
        else
          {:error, :timeout}
        end

      result ->
        result
    end
  end

  defp check_completion(pid) do
    case get_results(pid) do
      {:ok, :completed, results} ->
        Process.exit(pid, :normal)
        {:ok, results}

      {:ok, _} ->
        :continue

      error ->
        error
    end
  end

  defp executor_id(session_id),
    do: {:via, Registry, {:agents, session_id}}
end
