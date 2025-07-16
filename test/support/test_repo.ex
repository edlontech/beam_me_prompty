defmodule BeamMePrompty.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :beam_me_prompty,
    adapter: Ecto.Adapters.Postgres
end
