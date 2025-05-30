defmodule BeamMePrompty.Agent.Memory.ETS do
  @moduledoc """
  A simple ETS-based memory implementation for BeamMePrompty agents.

  This provides an in-memory storage solution that persists for the lifetime
  of the agent process. Useful for development and testing.

  ## Example

      defmodule MyAgent do
        use BeamMePrompty.Agent
        
        agent do
          memory_source :short_term, BeamMePrompty.Memory.ETS,
            table: :my_agent_memory,
            default: true
            
          stage :process do
            llm "gpt-4", BeamMePrompty.LLM.OpenAI do
              # Memory tools are automatically injected!
            end
          end
        end
      end
  """

  @behaviour BeamMePrompty.Agent.Memory

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table, :beam_me_prompty_memory)

    table =
      case :ets.whereis(table_name) do
        :undefined ->
          :ets.new(table_name, [:set, :public, :named_table])

        existing ->
          existing
      end

    {:ok, %{table: table, opts: opts}}
  end

  @impl true
  def store(context, key, value, opts) do
    metadata = %{
      stored_at: DateTime.utc_now(),
      ttl: Keyword.get(opts, :ttl),
      tags: Keyword.get(opts, :tags, [])
    }

    :ets.insert(context.table, {key, value, metadata})
    {:ok, %{key: key, metadata: metadata}}
  end

  @impl true
  def retrieve(context, key, opts) do
    case :ets.lookup(context.table, key) do
      [{^key, value, metadata}] ->
        if expired?(metadata) do
          :ets.delete(context.table, key)
          {:error, :not_found}
        else
          if Keyword.get(opts, :include_metadata, false) do
            {:ok, {value, metadata}}
          else
            {:ok, value}
          end
        end

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def search(context, query, opts) do
    limit = Keyword.get(opts, :limit, 100)

    # Simple pattern matching for ETS
    pattern =
      case query do
        %{"pattern" => pattern} -> pattern
        pattern when is_binary(pattern) -> pattern
        _ -> "*"
      end

    results =
      :ets.tab2list(context.table)
      |> Enum.filter(fn {key, _value, metadata} ->
        not expired?(metadata) and matches_pattern?(key, pattern)
      end)
      |> Enum.take(limit)
      |> Enum.map(fn {key, value, metadata} ->
        %{key: key, value: value, metadata: metadata}
      end)

    {:ok, results}
  end

  @impl true
  def delete(context, key, _opts) do
    :ets.delete(context.table, key)
    :ok
  end

  @impl true
  def list_keys(context, opts) do
    pattern = Keyword.get(opts, :pattern)
    limit = Keyword.get(opts, :limit, 1000)

    keys =
      :ets.tab2list(context.table)
      |> Enum.filter(fn {key, _value, metadata} ->
        not expired?(metadata) and
          (is_nil(pattern) or matches_pattern?(key, pattern))
      end)
      |> Enum.map(fn {key, _value, _metadata} -> key end)
      |> Enum.take(limit)

    {:ok, keys}
  end

  @impl true
  def clear(context, _opts) do
    :ets.delete_all_objects(context.table)
    :ok
  end

  @impl true
  def info(context) do
    info = :ets.info(context.table)

    %{
      type: :ets,
      size: Keyword.get(info, :size, 0),
      memory_usage: Keyword.get(info, :memory, 0),
      table_name: Keyword.get(info, :name),
      capabilities: [:search, :ttl, :pattern_matching]
    }
  end

  # Private helpers

  defp expired?(%{ttl: nil}), do: false

  defp expired?(%{ttl: ttl, stored_at: stored_at}) do
    expiry = DateTime.add(stored_at, ttl, :millisecond)
    DateTime.compare(DateTime.utc_now(), expiry) == :gt
  end

  defp matches_pattern?(_key, "*"), do: true

  defp matches_pattern?(key, pattern) when is_binary(key) and is_binary(pattern) do
    String.contains?(key, pattern)
  end

  defp matches_pattern?(key, pattern) do
    String.contains?(to_string(key), to_string(pattern))
  end
end
