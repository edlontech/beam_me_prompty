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

  @doc """
  Handles code injection before compilation.

  This function is called by the `use BeamMePrompty.Agent` macro to inject
  the necessary functions and modules into the agent module. It sets up
  the agent's lifecycle functions, executor integration, and DSL access.

  ## Parameters

  - `_keyword` - Compilation options (unused)

  ## Returns

  A quoted expression containing the injected code.

  ## Injected Functions

  This function injects the following functions into agent modules:
  - `child_spec/1` - Supervisor child specification
  - `start_link/1` - Process startup function
  - `run_sync/4` - Synchronous execution function
  - `stages/0` - Stage configuration accessor
  - `memory_sources/0` - Memory source configuration accessor
  - `agent_config/0` - Agent configuration accessor
  - `to_spec/0` - Agent specification converter

  """
  @spec handle_before_compile(keyword()) :: Macro.t()
  def handle_before_compile(_keyword) do
    quote do
      use BeamMePrompty.Agent.Executor

      alias BeamMePrompty.Agent.AgentSpec
      alias BeamMePrompty.Agent.Dsl
      alias BeamMePrompty.Agent.Executor

      @doc """
      Returns a child specification for supervision trees.

      Generates a child specification that can be used by supervisors to
      start and manage agent processes. Each agent instance is identified
      by a unique session ID.

      ## Parameters

      - `start_opts` - Keyword list of startup options (see `agent_opts/0` type)

      ## Returns

      A child specification map compatible with Supervisor.

      ## Examples

          # Used automatically by supervisors
          children = [
            {MyAgent, [input: %{name: "Alice"}, session_id: make_ref()]}
          ]

      """
      def child_spec(start_opts \\ []) do
        start_opts = Keyword.put_new(start_opts, :session_id, make_ref())

        %{
          id: start_opts[:session_id],
          start: {__MODULE__, :start_link, [start_opts]},
          restart: :transient
        }
      end

      @doc """
      Starts an agent process linked to the current process.

      Creates a new agent process that executes the defined stages asynchronously.
      The agent process will be linked to the calling process and can be supervised.

      ## Parameters

      - `start_opts` - Keyword list of startup options (see `agent_opts/0` type)

      ## Returns

      - `{:ok, pid()}` - The agent process PID on successful start
      - `{:error, term()}` - Error details if the agent fails to start

      ## Examples

          # Start an agent with input data
          {:ok, pid} = MyAgent.start_link([
            input: %{name: "Alice", topic: "AI"},
            initial_state: %{},
            session_id: make_ref()
          ])

          # Monitor the agent process
          Process.monitor(pid)

      """
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

      @doc """
      Returns the list of stages defined in this agent.

      Retrieves all stages configured in the agent DSL, including their
      dependencies, LLM configurations, and tool definitions.

      ## Returns

      A list of stage configurations from the agent DSL.

      ## Examples

          MyAgent.stages()
          #=> [%{name: :greet, depends_on: [], llm: ...}, ...]

      """
      @spec stages() :: list(map())
      def stages do
        Dsl.Info.agent(__MODULE__)
      end

      @doc """
      Returns the memory sources configured for this agent.

      Retrieves all memory sources defined in the agent DSL, including their
      configurations, descriptions, and options.

      ## Returns

      A list of memory source configurations from the agent DSL.

      ## Examples

          MyAgent.memory_sources()
          #=> [%{name: :short_term_cache, module: BeamMePrompty.Agent.Memory.ETS, ...}]

      """
      @spec memory_sources() :: list(map())
      def memory_sources do
        Dsl.Info.memory(__MODULE__)
      end

      @doc """
      Returns the agent configuration options.

      Retrieves global agent configuration such as state management mode,
      version, and other agent-level settings from the DSL.

      ## Returns

      A map containing agent configuration options.

      ## Examples

          MyAgent.agent_config()
          #=> %{agent_state: :stateful, version: "1.0.0"}

      """
      @spec agent_config() :: map()
      def agent_config do
        Dsl.Info.agent_options(__MODULE__)
      end

      @doc """
      Converts the agent DSL configuration to an AgentSpec struct.

      Transforms the agent's DSL configuration into a structured AgentSpec
      that can be used by the Executor for agent execution. This includes
      all stages, memory sources, and configuration options.

      ## Returns

      - `{:ok, AgentSpec.t()}` - The agent specification struct on success
      - `{:error, term()}` - Error details if conversion fails

      ## Examples

          {:ok, spec} = MyAgent.to_spec()
          #=> {:ok, %BeamMePrompty.Agent.AgentSpec{...}}

      """
      @spec to_spec() :: {:ok, BeamMePrompty.Agent.AgentSpec.t()} | {:error, term()}
      def to_spec do
        AgentSpec.from_map(
          %{
            stages: stages(),
            memory_sources: memory_sources(),
            agent_config: agent_config()
          },
          __MODULE__
        )
      end
    end
  end
end
