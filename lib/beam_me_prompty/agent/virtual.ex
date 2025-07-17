defmodule BeamMePrompty.Agent.Virtual do
  @moduledoc """
  Virtual agent implementation that executes persisted agent configurations.

  Virtual agents take a pre-loaded agent configuration and provide the same
  interface as regular agents without requiring compilation. 

  ## Usage

  ```elixir
  # Consumer queries and selects the agent they want
  {:ok, persisted_agent} = PersistedAgents.get_agent_by_name(repo, "research_agent")

  # Or with custom filtering
  {:ok, %{agents: [agent | _]}} = PersistedAgents.list_agents(repo, %{category: "research"})

  # Then execute the virtual agent with the configuration
  {:ok, result} = BeamMePrompty.Agent.Virtual.run_sync(
    agent.agent_spec,
    %{topic: "machine learning"}
  )

  # Or start as a supervised process
  {:ok, pid} = BeamMePrompty.Agent.Virtual.start_link(
    agent_spec: agent.agent_spec,
    input: %{topic: "machine learning"},
    session_id: make_ref()
  )
  ```

  ## Architecture

  Virtual agents work by:
  1. Taking a pre-loaded agent configuration (already queried by consumer)
  2. Deserializing the configuration into agent DSL structures
  3. Providing the same interface as regular agents (`stages/0`, `memory_sources/0`, `agent_config/0`)
  4. Using the standard executor infrastructure without modification
  """
  @moduledoc section: :agent_core_and_lifecycle

  use BeamMePrompty.Agent.Executor

  alias BeamMePrompty.Agent.AgentSpec
  alias BeamMePrompty.Agent.Executor

  @typedoc """
  Virtual agent startup options

  ## Parameters
    * `agent_spec` - The agent specification (map or JSON string)
    * `input` - Global input data for the agent (optional, defaults to empty map)
    * `initial_state` - The initial state of the agent (optional, defaults to empty map)
    * `opts` - Additional options (see `start_link/4`)
    * `session_id` - Unique identifier for the agent session (optional, defaults to a new reference)
  """
  @type virtual_agent_opts ::
          keyword(
            agent_spec: AgentSpec.t(),
            input: map(),
            initial_state: map(),
            opts: keyword(),
            session_id: reference()
          )

  @doc """
  Runs a virtual agent synchronously and waits for completion.

  ## Parameters
    * `agent_spec` - The agent specification
    * `input` - Global input data for the agent (optional, defaults to empty map)
    * `initial_state` - The initial state of the agent (optional, defaults to empty map)
    * `opts` - Additional options (see `start_link/4`) (optional, defaults to empty list)
    * `timeout` - Timeout in milliseconds (optional, defaults to 30_000 ms)

  ## Returns
    * `{:ok, results}` - The agent executed successfully
    * `{:error, reason}` - The agent failed to load or execute

  ## Examples

      # Execute a virtual agent synchronously
      {:ok, results} = BeamMePrompty.Agent.Virtual.run_sync(
        agent_spec,
        %{topic: "machine learning"}
      )
  """
  @spec run_sync(
          agent_spec :: AgentSpec.t(),
          input :: map(),
          initial_state :: map(),
          opts :: keyword(),
          timeout :: integer()
        ) :: {:ok, any()} | {:error, any()}
  def run_sync(agent_spec, input \\ %{}, initial_state \\ %{}, opts \\ [], timeout \\ 30_000) do
    Executor.execute(agent_spec, input, initial_state, opts, timeout)
  end

  @doc """
  Starts a virtual agent as a supervised process.

  ## Parameters
    * `start_opts` - Keyword list of startup options (see `virtual_agent_opts`)

  ## Returns
    * `{:ok, pid}` - The agent started successfully
    * `{:error, reason}` - The agent failed to start

  ## Examples

      # Start a virtual agent
      {:ok, pid} = BeamMePrompty.Agent.Virtual.start_link(
        agent_spec: agent_spec,
        input: %{topic: "machine learning"},
        session_id: make_ref()
      )
  """
  @spec start_link(virtual_agent_opts()) :: {:ok, pid()} | {:error, any()}
  def start_link(start_opts \\ []) do
    agent_spec = Keyword.fetch!(start_opts, :agent_spec)
    input = Keyword.get(start_opts, :input, %{})
    initial_state = Keyword.get(start_opts, :initial_state, %{})
    opts = Keyword.get(start_opts, :opts, [])

    Executor.start_link(agent_spec, input, initial_state, opts)
  end

  @doc """
  Creates a child specification for a virtual agent.

  ## Parameters
    * `start_opts` - Keyword list of startup options (see `virtual_agent_opts`)

  ## Returns
    * Child specification map suitable for supervision trees

  ## Examples

      # Add to a supervision tree
      children = [
        BeamMePrompty.Agent.Virtual.child_spec(
          agent_spec: agent_spec,
          input: %{topic: "machine learning"},
          session_id: make_ref()
        )
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  @spec child_spec(virtual_agent_opts()) :: Supervisor.child_spec()
  def child_spec(start_opts \\ []) do
    session_id = Keyword.get(start_opts, :session_id, make_ref())

    %{
      id: session_id,
      start: {__MODULE__, :start_link, [start_opts]},
      restart: :transient
    }
  end
end
