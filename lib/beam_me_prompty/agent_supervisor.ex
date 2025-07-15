defmodule BeamMePrompty.AgentSupervisor do
  @moduledoc """
  Manages the lifecycle of agent instances and their stages.
  """
  @moduledoc section: :agent_core_and_lifecycle

  import BeamMePrompty.Agent.Dsl.Part

  alias BeamMePrompty.Agent.Dsl.Part
  alias BeamMePrompty.Agent.Executor
  alias BeamMePrompty.Errors.InvalidMessageFormatError

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc false
  @spec start_link(any()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_) do
    children = [
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: __MODULE__}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  @doc """
  Starts a new agent instance under the supervisor

  ## Parameters

    - `agent`: The agent module to be started.
    - `opts`: Options to be passed to the agent.
  """
  @spec start_agent(module, opts :: keyword()) ::
          {:ok, pid} | {:error, term}
  def start_agent(agent, opts \\ []) do
    DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {__MODULE__, agent}},
      {agent, opts}
    )
  end

  @doc """
  Sends a message to a running agent instance.

  The `pid_or_session_id` can be either the process ID (PID) of the agent
  or a session ID. If a session ID is provided, it is resolved to a
  registered agent process name via `BeamMePrompty.Agent.Executor`.

  The message must be a valid `BeamMePrompty.Agent.Dsl.Part` struct.
  If the message format is invalid, an `InvalidMessageFormatError` is returned.
  """
  @spec send_message(pid() | reference(), Part.parts()) ::
          :ok | {:error, term()}
  def send_message(pid_or_session_id, message) when is_part(message),
    do: Executor.message_agent(pid_or_session_id, message)

  def send_message(_, message) do
    {:error,
     %InvalidMessageFormatError{reason: "Invalid message format", offending_value: message}}
  end
end
