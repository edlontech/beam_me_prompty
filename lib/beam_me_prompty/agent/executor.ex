defmodule BeamMePrompty.Agent.Executor do
  alias BeamMePrompty.DAG
  alias BeamMePrompty.Agent.ExecutorOptions
  alias BeamMePrompty.Errors

  @type state :: map()

  @type handle_error_response ::
          {:retry, state()}
          | {:stop, cause :: term()}
          | {:restart, reason :: term()}

  @callback handle_error(Errors.class_module(), inner_state :: map()) :: handle_error_response

  @callback handle_stage_start(stage :: map(), inner_state :: map()) :: :ok

  @callback handle_stage_finish(stage :: map(), result :: map(), inner_state :: map()) :: :ok

  @callback handle_complete(results :: map(), inner_state :: map()) :: :ok

  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour BeamMePrompty.Agent.Executor

      alias BeamMePrompty.Errors.External, as: ExternalError

      @doc false
      def handle_error({error, reason}, state)
          when is_exception(error, ExternalError),
          do: {:retry, reason, state}

      def handle_error(error, _state), do: {:stop, error}

      @doc false
      def handle_stage_start(_stage, _state), do: :ok

      @doc false
      def handle_stage_finish(_stage, _result, _state), do: :ok

      @doc false
      def handle_complete(_results, _state), do: :ok

      defoverridable handle_error: 2,
                     handle_stage_start: 2,
                     handle_stage_finish: 3,
                     handle_complete: 2
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
    # Start the agent process
    case start_link(module, input, state, opts) do
      {:ok, pid} ->
        # Monitor the process to detect crashes
        ref = Process.monitor(pid)

        # Create a polling function to check for completion
        check_completion = fn ->
          case get_results(pid) do
            {:ok, :completed, results} ->
              # Agent is complete, get results and terminate it
              Process.exit(pid, :normal)
              {:ok, results}

            {:ok, _} ->
              # Agent still running, continue polling
              :continue

            error ->
              # Something went wrong
              error
          end
        end

        # Poll for completion with timeout
        result = poll_for_completion(check_completion, timeout)

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

    with :ok <- DAG.validate(dag),
         {:ok, opts} <- ExecutorOptions.validate(opts) do
      init = {dag, input, state, opts, module}
      apply(GenStateMachine, :start_link, args(init, opts[:name]))
    end
  end

  defp args(init, nil) do
    [BeamMePrompty.Agent.Internals, init, []]
  end

  defp args(init, name) do
    [name, BeamMePrompty.Agent.Internals, init, []]
  end

  # Helper function to poll for completion with timeout
  defp poll_for_completion(check_fn, timeout, interval \\ 100) do
    end_time = System.monotonic_time(:millisecond) + timeout

    poll_loop(check_fn, end_time, interval)
  end

  defp poll_loop(check_fn, end_time, interval) do
    case check_fn.() do
      :continue ->
        current_time = System.monotonic_time(:millisecond)

        if current_time < end_time do
          # Sleep for a short interval before trying again
          Process.sleep(interval)
          poll_loop(check_fn, end_time, interval)
        else
          # Timeout reached
          {:error, :timeout}
        end

      result ->
        # Got a result or error
        result
    end
  end
end
