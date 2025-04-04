defmodule BeamMePrompty.Agent.Memory.ETSTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Memory.ETS

  setup do
    # Use a unique table name for each test to avoid conflicts

    # {:erlang.unique_integer([:positive])}
    table_name = :test_memory_
    {:ok, context} = ETS.init(table: table_name)

    on_exit(fn ->
      # Clean up the table after each test
      if :ets.whereis(table_name) != :undefined do
        :ets.delete(table_name)
      end
    end)

    %{context: context, table_name: table_name}
  end

  describe "init/1" do
    test "creates a new ETS table with default name" do
      # {:erlang.unique_integer([:positive])}

      table_name = :test_default_

      on_exit(fn ->
        if :ets.whereis(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, context} = ETS.init(table: table_name)

      assert context.table == table_name
      assert :ets.whereis(table_name) != :undefined
    end

    test "reuses existing ETS table" do
      # {:erlang.unique_integer([:positive])}
      table_name = :test_existing_
      _existing_table = :ets.new(table_name, [:set, :public, :named_table])

      on_exit(fn ->
        if :ets.whereis(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      {:ok, context} = ETS.init(table: table_name)

      assert is_reference(context.table)
    end

    test "uses default table name when not specified" do
      {:ok, context} = ETS.init([])

      on_exit(fn ->
        if :ets.whereis(:beam_me_prompty_memory) != :undefined do
          :ets.delete(:beam_me_prompty_memory)
        end
      end)

      assert context.table == :beam_me_prompty_memory
    end
  end

  describe "store/4" do
    test "stores a key-value pair", %{context: context} do
      key = "test_key"
      value = "test_value"

      {:ok, result} = ETS.store(context, key, value, [])

      assert result.key == key
      assert result.metadata.stored_at
      assert result.metadata.ttl == nil
      assert result.metadata.tags == []
    end

    test "stores with TTL option", %{context: context} do
      key = "ttl_key"
      value = "ttl_value"

      # 5 seconds

      ttl = 5000

      {:ok, result} = ETS.store(context, key, value, ttl: ttl)

      assert result.metadata.ttl == ttl
    end

    test "stores with tags", %{context: context} do
      key = "tagged_key"
      value = "tagged_value"
      tags = ["user", "session"]

      {:ok, result} = ETS.store(context, key, value, tags: tags)

      assert result.metadata.tags == tags
    end

    test "overwrites existing key", %{context: context} do
      key = "overwrite_key"

      {:ok, _} = ETS.store(context, key, "old_value", [])
      {:ok, _result} = ETS.store(context, key, "new_value", [])

      {:ok, retrieved} = ETS.retrieve(context, key, [])

      assert retrieved == "new_value"
    end
  end

  describe "retrieve/3" do
    test "retrieves existing value", %{context: context} do
      key = "retrieve_key"
      value = "retrieve_value"

      {:ok, _} = ETS.store(context, key, value, [])
      {:ok, retrieved} = ETS.retrieve(context, key, [])

      assert retrieved == value
    end

    test "retrieves with metadata", %{context: context} do
      key = "metadata_key"
      value = "metadata_value"
      tags = ["test"]

      {:ok, _} = ETS.store(context, key, value, tags: tags)
      {:ok, {retrieved_value, metadata}} = ETS.retrieve(context, key, include_metadata: true)

      assert retrieved_value == value
      assert metadata.tags == tags
      assert metadata.stored_at
    end

    test "returns error for non-existent key", %{context: context} do
      result = ETS.retrieve(context, "non_existent", [])

      assert result == {:error, :not_found}
    end

    test "handles TTL expiration", %{context: context} do
      key = "expired_key"
      value = "expired_value"

      # 1 millisecond

      ttl = 1

      {:ok, _} = ETS.store(context, key, value, ttl: ttl)

      # Wait for expiration
      Process.sleep(10)

      result = ETS.retrieve(context, key, [])
      assert result == {:error, :not_found}

      # Verify the key was actually deleted
      lookup_result = :ets.lookup(context.table, key)
      assert lookup_result == []
    end
  end

  describe "search/3" do
    setup %{context: context} do
      # Set up test data
      {:ok, _} = ETS.store(context, "user:123", %{name: "Alice"}, [])
      {:ok, _} = ETS.store(context, "user:456", %{name: "Bob"}, [])
      {:ok, _} = ETS.store(context, "session:abc", %{user_id: 123}, [])
      {:ok, _} = ETS.store(context, "config:theme", "dark", [])

      :ok
    end

    test "searches with string pattern", %{context: context} do
      {:ok, results} = ETS.search(context, "user:", [])

      assert length(results) == 2
      keys = Enum.map(results, & &1.key)
      assert "user:123" in keys
      assert "user:456" in keys
    end

    test "searches with map pattern", %{context: context} do
      {:ok, results} = ETS.search(context, %{"pattern" => "session"}, [])

      assert length(results) == 1
      assert hd(results).key == "session:abc"
    end

    test "searches with wildcard pattern", %{context: context} do
      {:ok, results} = ETS.search(context, "*", [])

      assert length(results) == 4
    end

    test "searches with limit", %{context: context} do
      {:ok, results} = ETS.search(context, "*", limit: 2)

      assert length(results) == 2
    end

    test "excludes expired entries", %{context: context} do
      # Store an entry that will expire
      {:ok, _} = ETS.store(context, "temp:data", "value", ttl: 1)

      # Wait for expiration
      Process.sleep(10)

      {:ok, results} = ETS.search(context, "temp:", [])

      assert results == []
    end

    test "returns complete result structure", %{context: context} do
      {:ok, results} = ETS.search(context, "config:", [])

      result = hd(results)
      assert result.key == "config:theme"
      assert result.value == "dark"
      assert result.metadata.stored_at
      assert result.metadata.ttl == nil
      assert result.metadata.tags == []
    end
  end

  describe "delete/3" do
    test "deletes existing key", %{context: context} do
      key = "delete_key"

      {:ok, _} = ETS.store(context, key, "value", [])
      result = ETS.delete(context, key, [])

      assert result == :ok
      assert ETS.retrieve(context, key, []) == {:error, :not_found}
    end

    test "succeeds for non-existent key", %{context: context} do
      result = ETS.delete(context, "non_existent", [])

      assert result == :ok
    end
  end

  describe "list_keys/2" do
    setup %{context: context} do
      {:ok, _} = ETS.store(context, "user:1", "Alice", [])
      {:ok, _} = ETS.store(context, "user:2", "Bob", [])
      {:ok, _} = ETS.store(context, "admin:1", "Charlie", [])
      {:ok, _} = ETS.store(context, "config:theme", "dark", [])

      :ok
    end

    test "lists all keys", %{context: context} do
      {:ok, keys} = ETS.list_keys(context, [])

      assert length(keys) == 4
      assert "user:1" in keys
      assert "user:2" in keys
      assert "admin:1" in keys
      assert "config:theme" in keys
    end

    test "lists keys with pattern filter", %{context: context} do
      {:ok, keys} = ETS.list_keys(context, pattern: "user:")

      assert length(keys) == 2
      assert "user:1" in keys
      assert "user:2" in keys
    end

    test "lists keys with limit", %{context: context} do
      {:ok, keys} = ETS.list_keys(context, limit: 2)

      assert length(keys) == 2
    end

    test "excludes expired keys", %{context: context} do
      {:ok, _} = ETS.store(context, "temp:key", "value", ttl: 1)

      # Wait for expiration
      Process.sleep(10)

      {:ok, keys} = ETS.list_keys(context, pattern: "temp:")

      assert keys == []
    end
  end

  describe "clear/2" do
    test "clears all entries", %{context: context} do
      {:ok, _} = ETS.store(context, "key1", "value1", [])
      {:ok, _} = ETS.store(context, "key2", "value2", [])

      result = ETS.clear(context, [])

      assert result == :ok

      {:ok, keys} = ETS.list_keys(context, [])
      assert keys == []
    end
  end

  describe "info/1" do
    test "returns table information", %{context: context} do
      {:ok, _} = ETS.store(context, "test_key", "test_value", [])

      info = ETS.info(context)

      assert info.type == :ets
    end
  end

  describe "pattern matching edge cases" do
    test "handles different key types", %{context: context} do
      {:ok, _} = ETS.store(context, :atom_key, "atom_value", [])
      {:ok, _} = ETS.store(context, 123, "number_value", [])
      {:ok, _} = ETS.store(context, "string_key", "string_value", [])

      {:ok, results} = ETS.search(context, "atom", [])
      assert length(results) == 1

      {:ok, results} = ETS.search(context, "123", [])
      assert length(results) == 1

      {:ok, results} = ETS.search(context, "string", [])
      assert length(results) == 1
    end

    test "handles complex values", %{context: context} do
      complex_value = %{
        user: %{id: 1, name: "Alice"},
        permissions: ["read", "write"],
        metadata: %{created_at: DateTime.utc_now()}
      }

      {:ok, _} = ETS.store(context, "complex_key", complex_value, [])
      {:ok, retrieved} = ETS.retrieve(context, "complex_key", [])

      assert retrieved == complex_value
    end
  end

  describe "TTL edge cases" do
    test "handles nil TTL", %{context: context} do
      {:ok, _} = ETS.store(context, "no_ttl", "value", ttl: nil)

      # Should not expire
      Process.sleep(10)

      {:ok, value} = ETS.retrieve(context, "no_ttl", [])
      assert value == "value"
    end

    test "handles zero TTL", %{context: context} do
      {:ok, _} = ETS.store(context, "zero_ttl", "value", ttl: 0)

      # Should expire immediately
      result = ETS.retrieve(context, "zero_ttl", [])
      assert result == {:error, :not_found}
    end

    test "TTL precision", %{context: context} do
      {:ok, _} = ETS.store(context, "precise_ttl", "value", ttl: 50)

      # Should still be available before expiration
      Process.sleep(25)
      {:ok, value} = ETS.retrieve(context, "precise_ttl", [])
      assert value == "value"

      # Should be expired after TTL
      Process.sleep(50)
      result = ETS.retrieve(context, "precise_ttl", [])
      assert result == {:error, :not_found}
    end
  end
end
