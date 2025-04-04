defmodule BeamMePrompty.Agent.MemoryManagerTest do
  use ExUnit.Case, async: false

  import Hammox

  alias BeamMePrompty.Agent.MemoryManager

  setup :set_mox_from_context
  setup :verify_on_exit!

  # Test fixtures
  defp mock_context, do: %{table: :test_table}
  defp mock_result, do: %{key: "test_key", metadata: %{stored_at: DateTime.utc_now()}}

  describe "start_link/2" do
    test "starts with empty sources" do
      {:ok, pid} = MemoryManager.start_link([])
      assert [] = MemoryManager.list_sources(pid)
    end

    test "starts with configured sources" do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)

      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      assert [mock: BeamMePrompty.MockMemory] = MemoryManager.list_sources(pid)
    end
  end

  describe "source management" do
    setup do
      {:ok, pid} = MemoryManager.start_link([])
      %{pid: pid}
    end

    test "add_source/4 adds a new memory source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)

      assert :ok = MemoryManager.add_source(pid, :mock, BeamMePrompty.MockMemory)
      assert [mock: BeamMePrompty.MockMemory] = MemoryManager.list_sources(pid)
    end

    test "add_source/4 sets first source as default", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      expect(BeamMePrompty.MockMemory, :store, fn _, _, _, _ -> {:ok, mock_result()} end)

      MemoryManager.add_source(pid, :first, BeamMePrompty.MockMemory)

      # Test that default source is used when no source is specified
      assert {:ok, _} = MemoryManager.store(pid, "key", "value")
    end

    test "add_source/4 fails when source init fails", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:error, :connection_failed} end)

      assert {:error, {:test, :connection_failed}} =
               MemoryManager.add_source(pid, :test, BeamMePrompty.MockMemory)
    end

    test "remove_source/2 removes a memory source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      expect(BeamMePrompty.MockMemory, :terminate, fn _, _ -> :ok end)

      MemoryManager.add_source(pid, :mock, BeamMePrompty.MockMemory)
      assert [mock: BeamMePrompty.MockMemory] = MemoryManager.list_sources(pid)

      assert :ok = MemoryManager.remove_source(pid, :mock)
      assert [] = MemoryManager.list_sources(pid)
    end

    test "remove_source/2 calls terminate if supported", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      expect(BeamMePrompty.MockMemory, :terminate, fn _, :shutdown -> :ok end)

      MemoryManager.add_source(pid, :mock, BeamMePrompty.MockMemory)
      MemoryManager.remove_source(pid, :mock)
    end

    test "remove_source/2 updates default source when removed", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, 2, fn _ -> {:ok, mock_context()} end)
      expect(BeamMePrompty.MockMemory, :terminate, fn _, _ -> :ok end)
      expect(BeamMePrompty.MockMemory, :store, fn _, _, _, _ -> {:ok, mock_result()} end)

      MemoryManager.add_source(pid, :first, BeamMePrompty.MockMemory)
      MemoryManager.add_source(pid, :second, BeamMePrompty.MockMemory)

      # Remove default source
      MemoryManager.remove_source(pid, :first)

      # Should still work with new default
      assert {:ok, _} = MemoryManager.store(pid, "key", "value")
    end

    test "remove_source/2 fails for unknown source", %{pid: pid} do
      assert {:error, :unknown_source} = MemoryManager.remove_source(pid, :unknown)
    end

    test "set_default_source/2 changes the default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, 2, fn _ -> {:ok, mock_context()} end)
      expect(BeamMePrompty.MockMemory, :store, fn _, _, _, _ -> {:ok, mock_result()} end)

      MemoryManager.add_source(pid, :first, BeamMePrompty.MockMemory)
      MemoryManager.add_source(pid, :second, BeamMePrompty.MockMemory)

      assert :ok = MemoryManager.set_default_source(pid, :second)

      # Verify the second source is now used by default
      assert {:ok, _} = MemoryManager.store(pid, "key", "value")
    end

    test "set_default_source/2 fails for unknown source", %{pid: pid} do
      assert {:error, :unknown_source} = MemoryManager.set_default_source(pid, :unknown)
    end

    test "info/1 returns information about all sources", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      expect(BeamMePrompty.MockMemory, :info, fn _ -> %{type: :mock, size: 0} end)

      MemoryManager.add_source(pid, :mock, BeamMePrompty.MockMemory)

      info = MemoryManager.info(pid)
      assert %{mock: %{type: :mock, size: 0}} = info
    end
  end

  describe "memory operations" do
    setup do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      %{pid: pid}
    end

    test "store/4 stores a value in default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :store, fn context, key, value, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert value == "test_value"
        assert opts == []
        {:ok, mock_result()}
      end)

      assert {:ok, _result} = MemoryManager.store(pid, "test_key", "test_value")
    end

    test "store/4 stores a value in specified source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :store, fn context, key, value, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert value == "test_value"
        assert opts == []
        {:ok, mock_result()}
      end)

      assert {:ok, _result} = MemoryManager.store(pid, "test_key", "test_value", source: :mock)
    end

    test "store/4 fails for unknown source", %{pid: pid} do
      assert {:error, {:unknown_memory_source, :unknown}} =
               MemoryManager.store(pid, "key", "value", source: :unknown)
    end

    test "retrieve/3 retrieves a value from default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :retrieve, fn context, key, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert opts == []
        {:ok, "test_value"}
      end)

      assert {:ok, "test_value"} = MemoryManager.retrieve(pid, "test_key")
    end

    test "retrieve/3 retrieves a value from specified source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :retrieve, fn context, key, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert opts == []
        {:ok, "test_value"}
      end)

      assert {:ok, "test_value"} = MemoryManager.retrieve(pid, "test_key", source: :mock)
    end

    test "delete/3 deletes a value from default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :delete, fn context, key, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert opts == []
        :ok
      end)

      assert :ok = MemoryManager.delete(pid, "test_key")
    end

    test "exists?/3 checks if key exists in default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :exists?, fn context, key, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert opts == []
        {:ok, true}
      end)

      assert {:ok, true} = MemoryManager.exists?(pid, "test_key")
    end

    test "update/4 updates a value in default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :update, fn context, key, update_fn, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert update_fn.("old_value") == "new_value"
        assert opts == []
        {:ok, "new_value"}
      end)

      update_fn = fn "old_value" -> "new_value" end
      assert {:ok, "new_value"} = MemoryManager.update(pid, "test_key", update_fn)
    end
  end

  describe "batch operations" do
    setup do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      %{pid: pid}
    end

    test "store_many/3 stores multiple values", %{pid: pid} do
      items = [{"key1", "value1"}, {"key2", "value2"}]
      expected_results = [mock_result(), mock_result()]

      expect(BeamMePrompty.MockMemory, :store_many, fn context, ^items, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, expected_results}
      end)

      assert {:ok, ^expected_results} = MemoryManager.store_many(pid, items)
    end

    test "retrieve_many/3 retrieves multiple values", %{pid: pid} do
      keys = ["key1", "key2"]
      expected_values = %{"key1" => "value1", "key2" => "value2"}

      expect(BeamMePrompty.MockMemory, :retrieve_many, fn context, ^keys, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, expected_values}
      end)

      assert {:ok, ^expected_values} = MemoryManager.retrieve_many(pid, keys)
    end

    test "delete_many/3 deletes multiple values", %{pid: pid} do
      keys = ["key1", "key2"]

      expect(BeamMePrompty.MockMemory, :delete_many, fn context, ^keys, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, 2}
      end)

      assert {:ok, 2} = MemoryManager.delete_many(pid, keys)
    end
  end

  describe "search and query operations" do
    setup do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      %{pid: pid}
    end

    test "search/3 searches for values", %{pid: pid} do
      query = "search query"
      expected_results = [mock_result(), mock_result()]

      expect(BeamMePrompty.MockMemory, :search, fn context, ^query, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, expected_results}
      end)

      assert {:ok, ^expected_results} = MemoryManager.search(pid, query)
    end

    test "count/3 counts matching items", %{pid: pid} do
      query = "count query"

      expect(BeamMePrompty.MockMemory, :count, fn context, ^query, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, 5}
      end)

      assert {:ok, 5} = MemoryManager.count(pid, query)
    end

    test "list_keys/2 lists available keys", %{pid: pid} do
      expected_keys = ["key1", "key2", "key3"]

      expect(BeamMePrompty.MockMemory, :list_keys, fn context, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, expected_keys}
      end)

      assert {:ok, ^expected_keys} = MemoryManager.list_keys(pid)
    end

    test "list_keys/2 handles paginated results", %{pid: pid} do
      expected_keys = ["key1", "key2"]
      cursor = "next_cursor"

      expect(BeamMePrompty.MockMemory, :list_keys, fn context, opts ->
        assert context == mock_context()
        assert opts == []
        {:ok, {expected_keys, cursor}}
      end)

      assert {:ok, {^expected_keys, ^cursor}} = MemoryManager.list_keys(pid)
    end
  end

  describe "clear operation" do
    setup do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      %{pid: pid}
    end

    test "clear/2 clears memory from default source", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :clear, fn context, opts ->
        assert context == mock_context()
        assert opts == []
        :ok
      end)

      assert :ok = MemoryManager.clear(pid)
    end
  end

  describe "option handling" do
    setup do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      %{pid: pid}
    end

    test "extracts source option and passes remaining options", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :store, fn context, key, value, opts ->
        assert context == mock_context()
        assert key == "test_key"
        assert value == "test_value"
        # Source option should be removed, custom option should remain
        assert opts == [custom: :option]
        {:ok, mock_result()}
      end)

      MemoryManager.store(pid, "test_key", "test_value", source: :mock, custom: :option)
    end
  end

  describe "error handling" do
    setup do
      expect(BeamMePrompty.MockMemory, :init, fn _ -> {:ok, mock_context()} end)
      {:ok, pid} = MemoryManager.start_link([{:mock, {BeamMePrompty.MockMemory, []}}])
      %{pid: pid}
    end

    test "propagates memory operation errors", %{pid: pid} do
      expect(BeamMePrompty.MockMemory, :retrieve, fn _, _, _ ->
        {:error, :not_found}
      end)

      assert {:error, :not_found} = MemoryManager.retrieve(pid, "missing_key")
    end

    test "handles unknown source errors consistently", %{pid: pid} do
      operations = [
        {:store, ["key", "value"]},
        {:retrieve, ["key"]},
        {:delete, ["key"]},
        {:exists?, ["key"]},
        {:search, ["query"]},
        {:count, ["query"]},
        {:list_keys, []},
        {:clear, []}
      ]

      for {operation, args} <- operations do
        error = apply(MemoryManager, operation, [pid | args] ++ [[source: :unknown]])
        assert {:error, {:unknown_memory_source, :unknown}} = error
      end
    end
  end
end
