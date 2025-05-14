defmodule BeamMePrompty.Agent.StagesSupervisor do
  use DynamicSupervisor

  alias BeamMePrompty.Agent.Stage

  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_stage_worker(supervisor_pid_or_name, stage_name) do
    spec = %{
      id: {Stage, stage_name},
      start: {Stage, :start_link, [{stage_name}]},
      restart: :transient
    }

    DynamicSupervisor.start_child(supervisor_pid_or_name, spec)
  end
end
