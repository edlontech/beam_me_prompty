defmodule BeamMePrompty.Agents.Executor do
  alias BeamMePrompty.Errors

  @type state :: map()

  @type handle_error_response ::
          {:retry, state()}
          | {:stop, cause :: term()}
          | {:restart, reason :: term()}

  @callback handle_error(Errors.class_module(), inner_state :: map()) :: handle_error_response

  @callback handle_stage_start(stage :: map(), inner_state :: map()) :: any()

  @callback handle_stage_finish(stage :: map(), result :: map(), inner_state :: map()) :: any()

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
        dag = Keyword.fetch!(start_opts, :dag)
        state = Keyword.fetch!(start_opts, :state)
        opts = Keyword.get(start_opts, :opts, [])

        BeamMePrompty.Agents.Executor.start_link(dag, __MODULE__, state, opts)
      end

      @doc false
      def handle_error({error, reason}, state)
          when is_exception(ExternalError),
          do: {:retry, reason, state}

      def handle_error(error, _state), do: {:stop, error}

      @doc false
      def handle_stage_start(_stage, _state), do: :ok

      @doc false
      def handle_stage_finish(_stage, _result, _state), do: :ok

      defoverridable child_spec: 1,
                     start_link: 1,
                     handle_error: 2,
                     handle_stage_start: 2,
                     handle_stage_finish: 3
    end
  end
end
