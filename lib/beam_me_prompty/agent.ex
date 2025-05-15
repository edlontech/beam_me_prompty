defmodule BeamMePrompty.Agent do
  @moduledoc """
    ## Usage Example

    ```elixir
    defmodule MyAgent do
      use BeamMePrompty.Agent

      agent do
        stage :planning do
          llm "gpt-4", BeamMePrompty.LLM.OpenAI do
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
        
        stage :execution, depends_on: [:planning] do
          # Configuration for execution stage
        end
      end
    end
    ```
  """

  use Spark.Dsl,
    default_extensions: [
      extensions: [BeamMePrompty.Agent.Dsl]
    ]

  def handle_before_compile(_keyword) do
    quote do
      use BeamMePrompty.Agent.Executor

      @doc false
      def child_spec(start_opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [start_opts]},
          restart: :transient
        }
        |> Supervisor.child_spec([])
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
