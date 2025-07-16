defmodule BeamMePrompty.Models.PersistedAgent do
  @moduledoc """
  Ecto schema for persisted agents in the BeamMePrompty system.

  This module defines the database schema for storing agent configurations,
  including their name, version, type, specification, and metadata.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: binary(),
          agent_name: String.t(),
          agent_version: String.t(),
          agent_type: String.t(),
          agent_spec: map(),
          metadata: map()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bmp_agents" do
    field :agent_name, :string
    field :agent_version, :string
    field :agent_type, :string
    field :agent_spec, :map
    field :metadata, :map

    timestamps()
  end

  @doc false
  def changeset(virtual_agent, attrs) do
    virtual_agent
    |> cast(attrs, [:agent_name, :agent_version, :agent_type, :agent_spec, :metadata])
    |> validate_required([:agent_name, :agent_version, :agent_type, :agent_spec])
    |> validate_format(:agent_name, ~r/^[A-Z][a-zA-Z0-9._]*$/)
    |> validate_format(:agent_type, ~r/^[a-z][a-z0-9_]*$/)
    |> unique_constraint([:agent_type, :agent_version])
  end
end
