defmodule BeamMePrompty.PersistedAgents do
  @moduledoc """
  Context module for managing persisted agents.

  Provides functions for creating, updating, deleting, and querying persisted agents
  with support for filtering and pagination.
  """

  import Ecto.Query

  alias BeamMePrompty.Commons.KeysetPagination
  alias BeamMePrompty.Commons.QueryFilter
  alias BeamMePrompty.Models.PersistedAgent

  @doc """
  Lists persisted agents with optional filtering and pagination.

  ## Parameters

    * `repo` - which ecto repo to use
    * `filters` - A map of filter criteria (optional)
    * `opts` - Options for pagination and field restrictions
      * `:page_size` - Number of items per page (default: 20)
      * `:next_after` - Cursor for pagination (map with :inserted_at and :id)
      * `:allowed_fields` - List of allowed filter fields (default: all)

  ## Examples

      iex> list_agents(YourApp.Repo)
      %{agents: [%PersistedAgent{}, ...], next_after: nil}
      
      iex> list_agents(YourApp.Repo, %{agent_name: {:like, "test"}}, page_size: 10)
      %{agents: [...], next_after: %{inserted_at: ~N[...], id: "..."}}
      
      iex> list_agents(YourApp.Repo, %{agent_name: "TestAgent"}, allowed_fields: [:agent_name])
      %{agents: [...], next_after: nil}
  """
  @spec list_agents(module(), map(), keyword()) :: %{
          agents: [PersistedAgent.t()],
          next_after: map() | nil
        }
  def list_agents(repo, filters \\ %{}, opts \\ []) when is_map(filters) and is_list(opts) do
    page_size = Keyword.get(opts, :page_size, 20)
    next_after = Keyword.get(opts, :next_after, nil)
    allowed_fields = Keyword.get(opts, :allowed_fields, nil)

    agents =
      PersistedAgent
      |> Ecto.Query.from()
      |> QueryFilter.apply_filters(filters, allowed_fields)
      |> KeysetPagination.apply_pagination(next_after, page_size)
      |> repo.all()

    next_after_cursor = KeysetPagination.calculate_next_after(agents, page_size)

    %{agents: agents, next_after: next_after_cursor}
  end

  @doc """
  Gets a persisted agent by ID.

  ## Parameters

    * `repo` - which ecto repo to use
    * `id` - The binary ID of the agent

  ## Returns

    * `{:ok, %PersistedAgent{}}` - If the agent is found
    * `{:error, :not_found}` - If the agent is not found

  ## Examples

      iex> get_agent("550e8400-e29b-41d4-a716-446655440000")
      {:ok, %PersistedAgent{id: "550e8400-e29b-41d4-a716-446655440000", ...}}
      
      iex> get_agent("nonexistent-id")
      {:error, :not_found}
  """
  @spec get_agent(module(), binary()) :: {:ok, PersistedAgent.t()} | {:error, :not_found}
  def get_agent(repo, id) do
    case repo.get(PersistedAgent, id) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end

  @doc """
  Gets a persisted agent by name.

  ## Parameters

    * `repo` - which ecto repo to use
    * `name` - The name of the agent

  ## Returns

    * `{:ok, %PersistedAgent{}}` - If the agent is found
    * `{:error, :not_found}` - If the agent is not found

  ## Examples

      iex> get_agent_by_name("TestAgent")
      {:ok, %PersistedAgent{agent_name: "TestAgent", ...}}
      
      iex> get_agent_by_name("NonExistentAgent")
      {:error, :not_found}
  """
  @spec get_agent_by_name(module, String.t()) :: {:ok, PersistedAgent.t()} | {:error, :not_found}
  def get_agent_by_name(repo, name) do
    case repo.get_by(PersistedAgent, agent_name: name) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end

  @doc """
  Creates a new persisted agent.

  ## Parameters

    * `repo` - which ecto repo to use
    * `attrs` - A map of attributes for the new agent

  ## Returns

    * `{:ok, %PersistedAgent{}}` - If the agent is created successfully
    * `{:error, %Ecto.Changeset{}}` - If there are validation errors

  ## Examples

      iex> create_agent(%{agent_name: "TestAgent", agent_spec: %{type: "test"}})
      {:ok, %PersistedAgent{agent_name: "TestAgent", ...}}
      
      iex> create_agent(%{agent_name: "invalid name"})
      {:error, %Ecto.Changeset{...}}
  """
  @spec create_agent(module(), map()) :: {:ok, PersistedAgent.t()} | {:error, Ecto.Changeset.t()}
  def create_agent(repo, attrs) do
    %PersistedAgent{}
    |> PersistedAgent.changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Updates an existing persisted agent.

  ## Parameters

    * `repo` - which ecto repo to use
    * `agent` - The agent struct to update
    * `attrs` - A map of attributes to update

  ## Returns

    * `{:ok, %PersistedAgent{}}` - If the agent is updated successfully
    * `{:error, %Ecto.Changeset{}}` - If there are validation errors

  ## Examples

      iex> update_agent(agent, %{agent_name: "UpdatedAgent"})
      {:ok, %PersistedAgent{agent_name: "UpdatedAgent", ...}}
      
      iex> update_agent(agent, %{agent_name: "invalid name"})
      {:error, %Ecto.Changeset{...}}
  """
  @spec update_agent(module(), PersistedAgent.t(), map()) ::
          {:ok, PersistedAgent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(repo, agent, attrs) do
    agent
    |> PersistedAgent.changeset(attrs)
    |> repo.update()
  end

  @doc """
  Deletes a persisted agent.

  ## Parameters

    * `repo` - which ecto repo to use
    * `agent` - The agent struct to delete

  ## Returns

    * `{:ok, %PersistedAgent{}}` - If the agent is deleted successfully
    * `{:error, %Ecto.Changeset{}}` - If there are constraints preventing deletion

  ## Examples

      iex> delete_agent(agent)
      {:ok, %PersistedAgent{...}}
  """
  @spec delete_agent(module, PersistedAgent.t()) ::
          {:ok, PersistedAgent.t()} | {:error, Ecto.Changeset.t()}
  def delete_agent(repo, agent) do
    repo.delete(agent)
  end

  @doc """
  Gets agents by their metadata fields.

  ## Parameters

    * `repo` - which ecto repo to use
    * `metadata_filters` - A map of metadata field filters
    * `opts` - Options for pagination

  ## Returns

    * `%{agents: [PersistedAgent.t()], next_after: map() | nil}`

  ## Examples

      iex> get_agents_by_metadata(%{"category" => "ai"})
      %{agents: [...], next_after: nil}
  """
  @spec get_agents_by_metadata(module(), map(), keyword()) :: %{
          agents: [PersistedAgent.t()],
          next_after: map() | nil
        }
  def get_agents_by_metadata(repo, metadata_filters, opts \\ []) do
    page_size = Keyword.get(opts, :page_size, 20)
    next_after = Keyword.get(opts, :next_after, nil)

    base_query = from(a in PersistedAgent)

    query =
      Enum.reduce(metadata_filters, base_query, fn {key, value}, acc_query ->
        where(acc_query, [a], fragment("?->? = ?", a.metadata, ^key, ^value))
      end)

    agents =
      query
      |> KeysetPagination.apply_pagination(next_after, page_size)
      |> repo.all()

    next_after_cursor = KeysetPagination.calculate_next_after(agents, page_size)

    %{agents: agents, next_after: next_after_cursor}
  end
end
