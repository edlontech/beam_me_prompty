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

  def up(opts \\ []) when is_list(opts) do
    migrator().up(opts)
  end

  def down(opts \\ []) when is_list(opts) do
    migrator().down(opts)
  end

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
