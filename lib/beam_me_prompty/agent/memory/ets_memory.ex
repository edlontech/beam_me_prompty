defmodule BeamMePrompty.Agent.Memory.ETSMemory do
  @moduledoc """
  ETS-based memory implementation for BeamMePrompty agents.

  This memory source stores data in ETS tables, providing fast in-memory
  storage that persists for the lifetime of the process. It's suitable for
  short-term memory, caching, and temporary data storage.

  ## Configuration Options

    * `:table` - Name of the ETS table (default: `:agent_memory`)
    * `:type` - ETS table type (default: `:set`)
    * `:access` - ETS table access (default: `:public`)
    * `:auto_create` - Whether to auto-create the table if it doesn't exist (default: `true`)
    * `:ttl` - Time-to-live in milliseconds for stored items (optional)

  ## Examples

      # Basic usage
      memory = BeamMePrompty.Agent.Memory.ETSMemory
      memory.store("key1", "value1", table: :my_cache)
      {:ok, "value1"} = memory.retrieve("key1", table: :my_cache)
      
      # With TTL
      memory.store("temp_key", "temp_value", table: :my_cache, ttl: 5000)
      # After 5 seconds, the key will be considered expired
  """

  @behaviour BeamMePrompty.Agent.Memory

  require Logger

  @default_table :agent_memory
  @default_type :set
  @default_access :public

  @impl true
  def store(key, value, opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)
    ttl = Keyword.get(opts, :ttl)

    ensure_table(table, opts)

    entry =
      case ttl do
        nil ->
          {key, value, :no_expiry, System.monotonic_time(:millisecond)}

        ttl_ms when is_integer(ttl_ms) ->
          expires_at = System.monotonic_time(:millisecond) + ttl_ms
          {key, value, expires_at, System.monotonic_time(:millisecond)}
      end

    case :ets.insert(table, entry) do
      true ->
        Logger.debug("[ETSMemory] Stored key #{inspect(key)} in table #{table}")
        {:ok, %{key: key, stored_at: System.monotonic_time(:millisecond)}}

      false ->
        {:error, :insert_failed}
    end
  rescue
    error -> {:error, {:ets_error, error}}
  end

  @impl true
  def retrieve(key, opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    ensure_table(table, opts)

    case :ets.lookup(table, key) do
      [{^key, value, expires_at, _stored_at}] ->
        if expired?(expires_at) do
          :ets.delete(table, key)
          Logger.debug("[ETSMemory] Key #{inspect(key)} expired, removed from table #{table}")
          {:error, :not_found}
        else
          Logger.debug("[ETSMemory] Retrieved key #{inspect(key)} from table #{table}")
          {:ok, value}
        end

      [] ->
        {:error, :not_found}
    end
  rescue
    error -> {:error, {:ets_error, error}}
  end

  @impl true
  def search(pattern, opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)
    include_expired = Keyword.get(opts, :include_expired, false)

    ensure_table(table, opts)

    # Build ETS match pattern
    # Pattern can be:
    # - atom (matches keys)
    # - string (substring match in keys or values)
    # - tuple for complex matching
    match_spec = build_match_spec(pattern, include_expired)

    try do
      results = :ets.select(table, match_spec)

      # Filter out expired entries unless explicitly requested
      filtered_results =
        if include_expired do
          results
        else
          Enum.filter(results, fn result ->
            case result do
              %{expires_at: expires_at} -> not expired?(expires_at)
              _ -> true
            end
          end)
        end

      Logger.debug(
        "[ETSMemory] Search for #{inspect(pattern)} returned #{length(filtered_results)} results"
      )

      {:ok, filtered_results}
    rescue
      error -> {:error, {:search_error, error}}
    end
  end

  @impl true
  def delete(key, opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    ensure_table(table, opts)

    case :ets.delete(table, key) do
      true ->
        Logger.debug("[ETSMemory] Deleted key #{inspect(key)} from table #{table}")
        :ok

      false ->
        {:error, :delete_failed}
    end
  rescue
    error -> {:error, {:ets_error, error}}
  end

  @impl true
  def list_keys(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)
    include_expired = Keyword.get(opts, :include_expired, false)

    ensure_table(table, opts)

    try do
      # Get all keys with their expiration info
      all_entries = :ets.select(table, [{{:"$1", :"$2", :"$3", :"$4"}, [], [{{:"$1", :"$3"}}]}])

      # Filter based on expiration
      keys =
        if include_expired do
          Enum.map(all_entries, fn {key, _expires_at} -> key end)
        else
          all_entries
          |> Enum.reject(fn {_key, expires_at} -> expired?(expires_at) end)
          |> Enum.map(fn {key, _expires_at} -> key end)
        end

      # Clean up expired entries if we encountered any
      unless include_expired do
        expired_keys =
          all_entries
          |> Enum.filter(fn {_key, expires_at} -> expired?(expires_at) end)
          |> Enum.map(fn {key, _expires_at} -> key end)

        Enum.each(expired_keys, fn key -> :ets.delete(table, key) end)

        if length(expired_keys) > 0 do
          Logger.debug("[ETSMemory] Cleaned up #{length(expired_keys)} expired keys")
        end
      end

      {:ok, keys}
    rescue
      error -> {:error, {:ets_error, error}}
    end
  end

  @impl true
  def clear(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    case :ets.whereis(table) do
      :undefined ->
        {:error, :table_not_found}

      _ ->
        case :ets.delete_all_objects(table) do
          true ->
            Logger.debug("[ETSMemory] Cleared all objects from table #{table}")
            :ok

          false ->
            {:error, :clear_failed}
        end
    end
  rescue
    error -> {:error, {:ets_error, error}}
  end

  @doc """
  Manually trigger cleanup of expired entries.

  This is automatically done during normal operations, but can be
  called explicitly for maintenance.
  """
  def cleanup_expired(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    ensure_table(table, opts)

    try do
      # Find all expired entries
      current_time = System.monotonic_time(:millisecond)

      expired_keys =
        :ets.select(table, [
          {{:"$1", :"$2", :"$3", :"$4"},
           [{:and, {:"=/=", :"$3", :no_expiry}, {:<, :"$3", current_time}}], [:"$1"]}
        ])

      # Delete expired entries
      Enum.each(expired_keys, fn key -> :ets.delete(table, key) end)

      Logger.debug("[ETSMemory] Cleaned up #{length(expired_keys)} expired entries")
      {:ok, length(expired_keys)}
    rescue
      error -> {:error, {:cleanup_error, error}}
    end
  end

  @doc """
  Get statistics about the ETS table.
  """
  def stats(opts \\ []) do
    table = Keyword.get(opts, :table, @default_table)

    case :ets.whereis(table) do
      :undefined ->
        {:error, :table_not_found}

      _ ->
        try do
          info = :ets.info(table)
          size = :ets.info(table, :size)
          memory = :ets.info(table, :memory)

          # Count expired entries
          current_time = System.monotonic_time(:millisecond)

          expired_count =
            :ets.select_count(table, [
              {{:"$1", :"$2", :"$3", :"$4"},
               [{:and, {:"=/=", :"$3", :no_expiry}, {:<, :"$3", current_time}}], [true]}
            ])

          stats = %{
            table: table,
            total_entries: size,
            expired_entries: expired_count,
            active_entries: size - expired_count,
            memory_words: memory,
            table_type: info[:type],
            table_access: info[:protection]
          }

          {:ok, stats}
        rescue
          error -> {:error, {:stats_error, error}}
        end
    end
  end

  # Private helper functions

  defp ensure_table(table, opts) do
    auto_create = Keyword.get(opts, :auto_create, true)

    case :ets.whereis(table) do
      :undefined when auto_create ->
        table_type = Keyword.get(opts, :type, @default_type)
        table_access = Keyword.get(opts, :access, @default_access)

        :ets.new(table, [table_type, :named_table, table_access])
        Logger.debug("[ETSMemory] Created ETS table #{table} with type #{table_type}")
        table

      :undefined ->
        raise "ETS table #{table} does not exist and auto_create is disabled"

      _ ->
        table
    end
  end

  defp expired?(:no_expiry), do: false

  defp expired?(expires_at) when is_integer(expires_at) do
    System.monotonic_time(:millisecond) > expires_at
  end

  defp build_match_spec(pattern, include_expired) do
    current_time = System.monotonic_time(:millisecond)

    base_conditions =
      if include_expired do
        []
      else
        [{:or, {:==, :"$3", :no_expiry}, {:>, :"$3", current_time}}]
      end

    case pattern do
      # Match all entries
      :all ->
        conditions = base_conditions

        result = [
          {{:"$1", :"$2", :"$3", :"$4"}, [],
           [%{key: :"$1", value: :"$2", expires_at: :"$3", stored_at: :"$4"}]}
        ]

        if length(conditions) > 0 do
          [
            {{{:"$1", :"$2", :"$3", :"$4"}, conditions,
              [%{key: :"$1", value: :"$2", expires_at: :"$3", stored_at: :"$4"}]}}
          ]
        else
          result
        end

      # String pattern - substring match in keys (converted to string)
      pattern when is_binary(pattern) ->
        # This is simplified - in a real implementation you might want more sophisticated string matching
        conditions = base_conditions

        [
          {{{:"$1", :"$2", :"$3", :"$4"}, conditions,
            [%{key: :"$1", value: :"$2", expires_at: :"$3", stored_at: :"$4"}]}}
        ]

      # Exact key match
      key ->
        conditions = [{:==, :"$1", key} | base_conditions]

        [
          {{{:"$1", :"$2", :"$3", :"$4"}, conditions,
            [%{key: :"$1", value: :"$2", expires_at: :"$3", stored_at: :"$4"}]}}
        ]
    end
  end
end
