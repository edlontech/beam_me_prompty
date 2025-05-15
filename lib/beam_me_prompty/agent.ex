defmodule BeamMePrompty.Agent do
  @moduledoc """
    ## Usage Example

    ```elixir
    defmodule MyAgent do
      use BeamMePrompty.Agent

      agent do
        stage :planning do
          llm "gemini-2.0-flash", BeamMePrompty.LLM.GoogleGemini do
            with_params max_tokens: 1000, temperature: 0.7
            
            message :system, [
              %BeamMePrompty.Agent.Dsl.TextPart{
                type: :text,
                text: "You are a planning assistant."
              }
            ]
            
            tool :search do
              module MyTools.Search
              description "Search for information"
              parameters %{
                "type" => "object",
                "properties" => %{
                  "query" => %{"type" => "string"}
                }
              }
            end
          end
        end
        
        stage :execution  do
          depends_on [:planning]
        end
      end
    end
    ```
  """

  use Spark.Dsl,
    default_extensions: [
      extensions: [BeamMePrompty.Agent.Dsl]
    ]

  @typedoc """
  Startup options for agents

  ## Parameters
    * `input` - Global input data for the agent (optional, defaults to empty map)
    * `initial_state` - The initial state of the agent (optional, defaults to empty map)
    * `opts` - Additional options (see `start_link/4`)
    * `session_id` - Unique identifier for the agent session (optional, defaults to a new reference)
  """
  @type agent_opts ::
          keyword(
            input: map(),
            initial_state: map(),
            opts: keyword(),
            session_id: reference()
          )

  @doc false
  def handle_before_compile(_keyword) do
    quote do
      use BeamMePrompty.Agent.Executor

      @doc false
      def child_spec(start_opts \\ []) do
        start_opts = Keyword.put_new(start_opts, :session_id, make_ref())

        %{
          id: start_opts[:session_id],
          start: {__MODULE__, :start_link, [start_opts]},
          restart: :transient
        }
      end

      @doc false
      def start_link(start_opts \\ []) do
        input = Keyword.get(start_opts, :input, %{})
        initial_state = Keyword.get(start_opts, :initial_state, %{})
        opts = Keyword.get(start_opts, :opts, [])

        BeamMePrompty.Agent.Executor.start_link(
          __MODULE__,
          input,
          initial_state,
          opts
        )
      end

      def run_sync(input, state \\ %{}, opts \\ [], timeout \\ 15_000) do
        BeamMePrompty.Agent.Executor.execute(__MODULE__, input, state, opts, timeout)
      end

      def stages() do
        BeamMePrompty.Agent.Dsl.Info.agent(__MODULE__)
      end
    end
  end
end
