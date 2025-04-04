defmodule BeamMePrompty.Agent.StagesSupervisor do
  @moduledoc """
  Supervisor for managing the lifecycle of agent stages
  """
  @moduledoc section: :agent_stage_and_execution

  use DynamicSupervisor

  alias BeamMePrompty.Agent.Stage

  @doc false
  def start_link(_init_arg) do
    DynamicSupervisor.start_link(__MODULE__, :ok)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new stage worker under the given supervisor.

  ## Parameters

    - `supervisor_pid_or_name`: The PID or name of the supervisor under which to start the stage.
    - `stage_name`: The name of the stage to be started.
  """
  @spec start_stage_worker(
          supervisor_pid_or_name :: pid | atom,
          session_id :: reference(),
          agent_module :: module,
          stage_name :: atom
        ) ::
          {:ok, pid} | {:error, term}
  def start_stage_worker(supervisor_pid_or_name, session_id, agent_module, stage_name) do
    spec = %{
      id: {Stage, stage_name},
      start: {Stage, :start_link, [{stage_name, session_id, agent_module}]},
      restart: :permanent
    }

    DynamicSupervisor.start_child(supervisor_pid_or_name, spec)
  end
end
