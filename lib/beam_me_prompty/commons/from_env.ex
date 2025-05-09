defmodule BeamMePrompty.Commons.FromEnv do
  def string(env_variable) do
    env_variable
    |> System.get_env()
  end
end
