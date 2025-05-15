defmodule BeamMePrompty.AgentManager do
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @spec start_link(any()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(_) do
    children = [
      {PartitionSupervisor, child_spec: DynamicSupervisor, name: __MODULE__}
    ]

    dbg(:here)

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def register_agent(agent, opts \\ []) do
    DynamicSupervisor.start_child(
      {:via, PartitionSupervisor, {__MODULE__, agent}},
      {agent, opts}
    )
  end
end
