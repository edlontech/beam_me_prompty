defmodule BeamMePrompty.Migrations.Postgres.V01 do
  @moduledoc false

  use Ecto.Migration

  def up(%{create_schema: create?, prefix: prefix} = opts) do
    %{escaped_prefix: _escaped, quoted_prefix: quoted} = opts

    if create?, do: execute("CREATE SCHEMA IF NOT EXISTS #{quoted}")

    create table(:bmp_agents, prefix: prefix, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_name, :string, null: false
      add :agent_version, :string, null: false
      add :agent_type, :string, null: false
      add :agent_spec, :map, null: false
      add :metadata, :map

      timestamps()
    end

    create unique_index(:bmp_agents, [:agent_type, :agent_version], prefix: prefix)
    create index(:bmp_agents, [:agent_name], prefix: prefix)
  end

  def down(%{prefix: prefix, quoted_prefix: _quoted}) do
    drop table(:bmp_agents, prefix: prefix)
  end
end
