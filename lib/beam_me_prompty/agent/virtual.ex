defmodule BeamMePrompty.Agent.Virtual do
  @moduledoc """
  Virtual agent implementation that executes persisted agent configurations.

  Virtual agents take a pre-loaded agent configuration and provide the same
  interface as regular agents without requiring compilation. The consumer is
  responsible for querying and filtering persisted agents as needed.

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

  This approach separates concerns:
  - **Consumer**: Handles querying, filtering, and selecting agents
  - **Virtual agent**: Handles execution of the selected configuration
  """
  @moduledoc section: :agent_core_and_lifecycle

  use BeamMePrompty.Agent.Executor
  use GenServer

  alias BeamMePrompty.Agent.Executor
  alias BeamMePrompty.Agent.Serialization
  alias BeamMePrompty.Errors.ValidationError

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
            agent_spec: map() | String.t(),
            input: map(),
            initial_state: map(),
            opts: keyword(),
            session_id: reference()
          )

  @doc """
  Runs a virtual agent synchronously and waits for completion.

  ## Parameters
    * `agent_spec` - The agent specification (map or JSON string)
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
          agent_spec :: map() | String.t(),
          input :: map(),
          initial_state :: map(),
          opts :: keyword(),
          timeout :: integer()
        ) :: {:ok, any()} | {:error, any()}
  def run_sync(agent_spec, input \\ %{}, initial_state \\ %{}, opts \\ [], timeout \\ 30_000) do
    with {:ok, agent_config} <- deserialize_agent_spec(agent_spec),
         :ok <- Serialization.validate(agent_config) do
      Process.put(:virtual_agent_config, agent_config)

      Executor.execute(__MODULE__, input, initial_state, opts, timeout)
    end
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
    session_id = Keyword.get(start_opts, :session_id, make_ref())

    with {:ok, agent_config} <- deserialize_agent_spec(agent_spec),
         :ok <- Serialization.validate(agent_config) do
      case GenServer.start_link(__MODULE__, agent_config,
             name: {:via, Registry, {:agents, virtual_agent_name(session_id)}}
           ) do
        {:ok, _pid} ->
          Executor.start_link(__MODULE__, input, initial_state, opts)

        {:error, reason} ->
          {:error, reason}
      end
    end
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

  # Standard agent interface - these functions are called by the executor

  @doc """
  Returns the stages configuration for the virtual agent.

  This is called by the executor to get the agent's stages.
  """
  def stages do
    case get_agent_config() do
      {:ok, config} -> config.agent
      {:error, _} -> []
    end
  end

  @doc """
  Returns the memory sources configuration for the virtual agent.

  This is called by the executor to get the agent's memory sources.
  """
  def memory_sources do
    case get_agent_config() do
      {:ok, config} -> config.memory
      {:error, _} -> []
    end
  end

  @doc """
  Returns the agent configuration options for the virtual agent.

  This is called by the executor to get the agent's configuration.
  """
  def agent_config do
    case get_agent_config() do
      {:ok, config} -> config.opts
      {:error, _} -> []
    end
  end

  @impl GenServer
  def init(agent_config) do
    {:ok, %{agent_config: agent_config}}
  end

  @impl GenServer
  def handle_call(:get_config, _from, %{agent_config: config} = state) do
    {:reply, {:ok, config}, state}
  end

  @impl GenServer
  def handle_call(:get_stages, _from, %{agent_config: config} = state) do
    {:reply, config.agent, state}
  end

  @impl GenServer
  def handle_call(:get_memory_sources, _from, %{agent_config: config} = state) do
    {:reply, config.memory, state}
  end

  @impl GenServer
  def handle_call(:get_agent_config, _from, %{agent_config: config} = state) do
    {:reply, config.opts, state}
  end

  # Private functions

  defp deserialize_agent_spec(agent_spec) when is_map(agent_spec) do
    case Jason.encode(agent_spec) do
      {:ok, json_string} ->
        Serialization.deserialize(json_string)

      {:error, reason} ->
        {:error,
         ValidationError.exception(message: "Failed to encode agent spec: #{inspect(reason)}")}
    end
  end

  defp deserialize_agent_spec(agent_spec) when is_binary(agent_spec) do
    Serialization.deserialize(agent_spec)
  end

  defp deserialize_agent_spec(agent_spec) do
    {:error,
     ValidationError.exception(message: "Invalid agent spec format: #{inspect(agent_spec)}")}
  end

  defp get_agent_config do
    case Process.get(:virtual_agent_config) do
      nil ->
        # Try to get config from GenServer (for start_link)
        # For now, we'll use a simple approach and store it in process dictionary
        # In a real implementation, we'd need better session management
        {:error, :no_config}

      config ->
        {:ok, config}
    end
  end

  defp virtual_agent_name(session_id), do: "virtual_agent_#{inspect(session_id)}"
end
