defmodule BeamMePrompty.Tool do
  @callback run(input :: map()) :: {:ok, map() | String.t()} | {:error, any()}
end
