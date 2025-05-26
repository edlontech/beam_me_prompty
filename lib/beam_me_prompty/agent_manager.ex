defmodule BeamMePrompty.AgentManager do
  @moduledoc """
  Manages the lifecycle of agent instances and their stages.
  """
  import BeamMePrompty.Agent.Dsl.Part

  alias BeamMePrompty.Agent.Executor

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
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

  def send_message(pid_or_session_id, message) when is_part(message),
    do: Executor.message_agent(pid_or_session_id, message)

  def send_message(_, message) do
    {:error, "Invalid message format: #{inspect(message)}"}
  end
end
