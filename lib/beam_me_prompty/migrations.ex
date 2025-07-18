defmodule BeamMePrompty.Migrations do
  @moduledoc false

  defdelegate up(opts \\ []), to: BeamMePrompty.Migration
  defdelegate down(opts \\ []), to: BeamMePrompty.Migration
end

defmodule BeamMePrompty.Migration do
  @moduledoc """
  Database migration utilities for BeamMePrompty.

  This module provides functions to manage database schema migrations
  for BeamMePrompty's persistent storage requirements.
  """

  use Ecto.Migration

  @doc """
  Migrates storage up to the latest version.
  """
  @callback up(Keyword.t()) :: :ok

  @doc """
  Migrates storage down to the previous version.
  """
  @callback down(Keyword.t()) :: :ok

  @doc """
  Identifies the last migrated version.
  """
  @callback migrated_version(Keyword.t()) :: non_neg_integer()

  @doc """
  Runs database migrations up to the latest version.

  Applies all pending migrations to bring the database schema up to date.
  The specific migration strategy depends on the database adapter being used.

  ## Parameters

  - `opts` - Migration options (defaults to empty list)

  ## Returns

  - `:ok` - Migrations completed successfully

  ## Examples

      BeamMePrompty.Migration.up()
      #=> :ok

      BeamMePrompty.Migration.up([verbose: true])
      #=> :ok

  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) when is_list(opts) do
    migrator().up(opts)
  end

  @doc """
  Reverts database migrations to the previous version.

  Rolls back the most recent migration, reverting the database schema changes.
  The specific migration strategy depends on the database adapter being used.

  ## Parameters

  - `opts` - Migration options (defaults to empty list)

  ## Returns

  - `:ok` - Migration rollback completed successfully

  ## Examples

      BeamMePrompty.Migration.down()
      #=> :ok

      BeamMePrompty.Migration.down([verbose: true])
      #=> :ok

  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) when is_list(opts) do
    migrator().down(opts)
  end

  @doc """
  Returns the current migration version.

  Identifies the last successfully applied migration version number.
  This is useful for determining the current state of the database schema.

  ## Parameters

  - `opts` - Migration options (defaults to empty list)

  ## Returns

  - `non_neg_integer()` - The version number of the last applied migration

  ## Examples

      BeamMePrompty.Migration.migrated_version()
      #=> 1

      BeamMePrompty.Migration.migrated_version([verbose: true])
      #=> 2

  """
  @spec migrated_version(keyword()) :: non_neg_integer()
  def migrated_version(opts \\ []) when is_list(opts) do
    migrator().migrated_version(opts)
  end

  defp migrator do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres -> BeamMePrompty.Migrations.Postgres
      _ -> Keyword.fetch!(repo().config(), :migrator)
    end
  end
end
