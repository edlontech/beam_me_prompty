defmodule BeamMePrompty.Agent do
  @moduledoc """
  A powerful framework for building multi-stage AI agents with memory persistence and tool integration.

  `BeamMePrompty.Agent` provides a declarative DSL for defining complex AI workflows that can:
  - Execute multiple stages in sequence or parallel
  - Maintain state and memory across interactions
  - Use different LLM providers for different tasks
  - Integrate with external tools and APIs
  - Handle errors and retries gracefully

  ## Core Concepts

  ### Agents
  An agent is a workflow composed of multiple stages that can be executed synchronously or asynchronously.
  Agents can be stateful (maintaining state between executions) or stateless (fresh state each time).

  ### Stages
  Stages are individual steps in the agent workflow. Each stage can:
  - Make LLM calls with specific prompts and parameters
  - Use tools to interact with external systems
  - Depend on results from previous stages
  - Access and modify agent memory

  ### Memory Sources
  Memory sources provide persistent storage for agent data. Built-in options include:
  - `BeamMePrompty.Agent.Memory.ETS` - Fast, in-memory storage

  ### Tools
  Tools extend agent capabilities by providing access to external APIs, databases, file systems, etc.
  Tools can be defined globally for the agent or per-stage.

  ## Simple Example

  ```elixir
  defmodule MyApp.SimpleAgent do
    use BeamMePrompty.Agent

    agent do
      stage :greet do
        llm "gpt-4", BeamMePrompty.LLM.OpenAI do
          message :system, [text_part("You are a friendly assistant.")]
          message :user, [text_part("Say hello to <%= name %>!")]
        end
      end
    end
  end

  # Usage
  {:ok, result} = MyApp.SimpleAgent.run_sync(%{name: "Alice"})
  ```

  ## Complex Multi-Stage Example

  ```elixir
  defmodule MyApp.ComplexAgent do
    use BeamMePrompty.Agent

    # Define a memory source for the agent
    memory do
      memory_source :short_term_cache, BeamMePrompty.Agent.Memory.ETS,
        description: "Fast, temporary storage for intermediate results or short-term context.",
        opts: [table: :my_agent_cache_table],
        default: true
    end

    agent do
      # Global agent options
      # agent_state :stateful # or :stateless (default)
      # version "1.0.0"

      # Stage 1: Research a topic using a search tool
      stage :research do
        llm "gemini-1.5-flash", BeamMePrompty.LLM.GoogleGemini do
          with_params do
            temperature 0.7
            api_key fn -> System.get_env("GOOGLE_API_KEY") end
          end

          message :system, [
            text_part("You are a research assistant. Your goal is to find key information about the given topic.")
          ]
          message :user, [
            text_part("Please research the topic: <%= topic_input %>. Use the web_search tool.")
          ]
          
          # Tool definition within the stage (could also be defined globally)
          tools [MyApp.Tools.WebSearchTool] 
        end
      end

      # Stage 2: Summarize the research findings
      stage :summarize do
        depends_on [:research] # This stage runs after 'research' completes

        llm "claude-3-haiku-20240307", BeamMePrompty.LLM.Anthropic do
          with_params do
            api_key fn -> System.get_env("ANTHROPIC_API_KEY") end
            max_tokens 500
          end

          message :system, [
            text_part("You are a summarization expert. Summarize the provided research findings concisely.")
          ]
          message :user, [
            text_part("Research findings to summarize:"),
            # Using the result from the 'research' stage
            data_part(%{findings: <%= research.result %>}) 
          ]
          # No tools needed for this LLM call, it will just summarize
        end
      end

      # Stage 3: Store the summary in memory
      stage :store_summary do
        depends_on [:summarize]

        llm "gemini-1.5-flash", BeamMePrompty.LLM.GoogleGemini do
          # This LLM call will use the automatically injected memory_store tool
          message :system, [text_part("You are a data management assistant.")]
          message :user, [
            text_part("Store the following summary under the key '<%= topic_input %>_summary'. Summary:"),
            data_part(%{summary_to_store: <%= summarize.result %>})
          ]
          # Memory tools are auto-injected if a memory_source is defined
        end
      end
    end
  end
  ```

  ## Execution Modes

  ### Synchronous Execution
  ```elixir
  # Run agent and wait for completion
  {:ok, result} = MyApp.Agent.run_sync(
    %{topic_input: "artificial intelligence"},  # input data
    %{},                                         # initial state
    [],                                          # options
    30_000                                       # timeout (ms)
  )
  ```

  ### Asynchronous Execution
  ```elixir
  # Start agent as a supervised process
  {:ok, pid} = MyApp.Agent.start_link(
    input: %{topic_input: "machine learning"},
    initial_state: %{},
    session_id: make_ref()
  )
  ```
  ## Configuration Options

  - `agent_state`: `:stateful` or `:stateless` (default)
  - `version`: Version string for the agent

  See `BeamMePrompty.Agent.Dsl` for complete DSL documentation.
  """
  @moduledoc section: :agent_core_and_lifecycle

  use Spark.Dsl,
    default_extensions: [
      extensions: [BeamMePrompty.Agent.Dsl]
    ]

  alias BeamMePrompty.Agent.Executor

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

      alias BeamMePrompty.Agent.AgentSpec
      alias BeamMePrompty.Agent.Dsl
      alias BeamMePrompty.Agent.Executor

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

        {:ok, agent_spec} = to_spec()

        Executor.start_link(
          agent_spec,
          input,
          initial_state,
          opts
        )
      end

      @doc """
      Runs the agent synchronously and waits for completion.

      ## Parameters
        * `input` - Global input data for the agent (optional, defaults to an empty map).
        * `initial_state` - The initial state of the agent (optional, defaults to an empty map).
        * `opts` - Additional options (see `start_link/4`) (optional, defaults to an empty list).
        * `timeout` - Timeout in milliseconds (optional, defaults to 15_000 ms).
      """
      @spec run_sync(
              input :: map(),
              initial_state :: map(),
              opts :: keyword(),
              timeout :: integer()
            ) ::
              {:ok, any()} | {:error, any()}
      def run_sync(input \\ %{}, initial_state \\ %{}, opts \\ [], timeout \\ 15_000) do
        {:ok, agent_spec} = to_spec()
        Executor.execute(agent_spec, input, initial_state, opts, timeout)
      end

      def stages do
        __MODULE__
        |> Dsl.Info.agent()
      end

      def memory_sources do
        __MODULE__
        |> Dsl.Info.memory()
      end

      def agent_config do
        __MODULE__
        |> Dsl.Info.agent_options()
      end

      def to_spec do
        AgentSpec.new(stages(), memory_sources(), agent_config(), __MODULE__)
      end
    end
  end
end
