defmodule BeamMePrompty.Agents.Executor do
  alias BeamMePrompty.DAG
  alias BeamMePrompty.Agents.ExecutorOptions
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

  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour BeamMePrompty.Agents.Executor

      alias BeamMePrompty.Errors.External, as: ExternalError

      @doc false
      def child_spec(start_opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [start_opts]},
          restart: :transient
        }
        |> Supervisor.child_spec(unquote(Macro.escape(opts)))
      end

      @doc false
      def start_link(start_opts) do
        stages = Keyword.fetch!(start_opts, :stages)
        state = Keyword.fetch!(start_opts, :state)
        opts = Keyword.get(start_opts, :opts, [])

        BeamMePrompty.Agents.Executor.start_link(stages, __MODULE__, state, opts)
      end

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

      defoverridable child_spec: 1,
                     start_link: 1,
                     handle_error: 2,
                     handle_stage_start: 2,
                     handle_stage_finish: 3,
                     handle_complete: 2
    end
  end

  def start_link(stages, module, state, opts) do
    dag = DAG.build(stages)

    with {:ok, dag} <- DAG.validate(dag),
         {:ok, opts} <- ExecutorOptions.validate(opts) do
      init = {dag, state, opts, module}
      apply(GenStateMachine, :start_link, args(init, opts[:name]))
    end
  end

  defp args(init, nil) do
    [BeamMePrompty.Agents.Internals, init, []]
  end

  defp args(init, name) do
    [name, BeamMePrompty.Agents.Internals, init, []]
  end
end
