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
  @moduledoc section: :memory_management

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
        handle_retrieved_value(context, key, value, metadata, opts)

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
  def info(_context) do
    %{
      type: :ets,
      query_format: %{
        description: "Simple pattern matching and key-based retrieval",
        search_patterns: %{
          "*" => "Matches all keys (wildcard)",
          "specific_string" =>
            "Matches keys containing the string (case-sensitive substring match)",
          "exact_key" => "Direct key lookup via retrieve/3"
        },
        query_examples: [
          %{operation: "search", query: "*", description: "Find all non-expired entries"},
          %{operation: "search", query: "user", description: "Find all keys containing 'user'"},
          %{
            operation: "search",
            query: %{"pattern" => "session"},
            description: "Find keys containing 'session'"
          },
          %{
            operation: "retrieve",
            query: "user:123",
            description: "Get specific value by exact key"
          }
        ]
      },
      datasource_description: %{
        name: "Erlang Term Storage (ETS)",
        storage_type: "In-memory key-value store",
        persistence: "Process lifetime only - data is lost when process terminates",
        performance: "Very fast read/write operations, single-node only",
        scalability: "Limited to single Erlang node, suitable for small to medium datasets",
        use_cases: [
          "Development and testing environments",
          "Session storage",
          "Caching frequently accessed data",
          "Temporary data that doesn't need persistence",
          "Agent short-term memory",
          "Configuration and state management within a single process"
        ],
        limitations: [
          "Data is not persisted between restarts",
          "Cannot be shared between different nodes in a cluster",
          "Memory usage grows with stored data",
          "No complex querying capabilities (no SQL, no semantic search)",
          "Pattern matching is limited to simple string containment"
        ]
      },
      capabilities: [
        :key_value_storage,
        :pattern_matching,
        :ttl_expiration,
        :metadata_storage,
        :atomic_operations,
        :fast_lookups,
        :bulk_operations,
        :memory_efficient
      ],
      when_to_use: %{
        recommended_for: [
          "Rapid prototyping and development",
          "Testing agent memory functionality",
          "Storing temporary computation results",
          "Agent working memory that doesn't need persistence",
          "Small datasets (< 10MB) that need fast access",
          "Single-node applications"
        ],
        not_recommended_for: [
          "Production systems requiring data persistence",
          "Large datasets that exceed available memory",
          "Multi-node distributed systems",
          "Complex queries requiring SQL or semantic search",
          "Long-term data storage",
          "Data that must survive system restarts"
        ]
      },
      query_optimization_tips: [
        "Use specific keys for direct lookups when possible (fastest)",
        "Prefer exact key matches over pattern searches",
        "Use TTL to automatically clean up expired data",
        "Consider key naming conventions for better pattern matching",
        "Use tags in metadata for additional filtering capabilities"
      ]
    }
  end

  # Private helpers

  defp handle_retrieved_value(context, key, value, metadata, opts) do
    if expired?(metadata) do
      :ets.delete(context.table, key)
      {:error, :not_found}
    else
      format_retrieved_value(value, metadata, opts)
    end
  end

  defp format_retrieved_value(value, metadata, opts) do
    if Keyword.get(opts, :include_metadata, false) do
      {:ok, {value, metadata}}
    else
      {:ok, value}
    end
  end

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
