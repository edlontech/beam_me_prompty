import Config

config :beam_me_prompty, BeamMePrompty.TestRepo,
  migration_lock: false,
  username: "postgres",
  password: "postgres",
  hostname: System.get_env("POSTGRES_HOST") || "localhost",
  priv: "test/support/postgres",
  port: 5432,
  pool_size: System.schedulers_online() * 2,
  database: "beam_me_prompty_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox

config :beam_me_prompty,
  ecto_repos: [BeamMePrompty.TestRepo]
