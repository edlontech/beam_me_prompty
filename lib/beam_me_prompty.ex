defmodule BeamMePrompty do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Registry, [keys: :unique, name: :agents]},
      BeamMePrompty.AgentManager
    ]

    opts = [strategy: :one_for_one, name: BeamMePrompty.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
