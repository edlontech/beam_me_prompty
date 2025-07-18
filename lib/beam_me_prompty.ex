defmodule BeamMePrompty do
  @external_resource "README.md"
  @moduledoc File.read!("README.md")
  use Application

  @doc """
  Starts the BeamMePrompty application supervisor.

  This function is called by the Elixir Application framework when the application
  starts. It initializes the core supervision tree that manages agent lifecycle
  and execution.

  ## Parameters

  - `_type` - The application start type (ignored)
  - `_args` - The application start arguments (ignored)

  ## Returns

  - `{:ok, pid()}` - The supervisor process ID on successful start
  - `{:error, term()}` - Error details if the supervisor fails to start

  ## Supervision Tree

  The supervisor starts the following children:
  - `Registry` - Process registry for agent identification and lookup
  - `BeamMePrompty.AgentSupervisor` - Supervisor for all agent processes

  ## Examples

      # Called automatically by Application framework
      BeamMePrompty.start(:normal, [])
      #=> {:ok, #PID<0.123.0>}

  """
  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_type, _args) do
    children = [
      {Registry, [keys: :unique, name: :agents]},
      BeamMePrompty.AgentSupervisor
    ]

    opts = [strategy: :one_for_one, name: BeamMePrompty.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
