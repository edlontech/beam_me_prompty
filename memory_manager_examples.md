# Memory Manager Usage Examples

## Basic Setup
```elixir
# Start with multiple memory sources
{:ok, memory_manager} = MemoryManager.start_link([
  {:cache, {MyApp.ETSMemory, [table: :agent_cache]}},
  {:embeddings, {MyApp.VectorMemory, [dimension: 1536, index: "agent-memories"]}},
  {:persistent, {MyApp.PostgresMemory, [repo: MyApp.Repo, table: "agent_memories"]}}
])

# Set default source
MemoryManager.set_default_source(memory_manager, :cache)
```

## Single Operations
```elixir
# Store in default source (cache)
{:ok, result} = MemoryManager.store(memory_manager, "user_context", %{
  user_id: "123",
  conversation_state: "greeting",
  timestamp: DateTime.utc_now()
})

# Store in specific source with TTL
MemoryManager.store(memory_manager, "temp_data", "some value", 
  source: :cache, 
  ttl: 300_000  # 5 minutes
)

# Retrieve with metadata
{:ok, {value, metadata}} = MemoryManager.retrieve(memory_manager, "user_context", 
  include_metadata: true
)
```

## Batch Operations
```elixir
# Store multiple items
items = [
  {"key1", "value1"},
  {"key2", "value2", [ttl: 600_000]},  # with custom options
  {"key3", "value3"}
]

{:ok, results} = MemoryManager.store_many(memory_manager, items, source: :persistent)

# Retrieve multiple
{:ok, values} = MemoryManager.retrieve_many(memory_manager, ["key1", "key2", "key3"])
# Returns: %{"key1" => "value1", "key2" => "value2", "key3" => "value3"}
```

## Search Operations
```elixir
# Semantic search in vector memory
{:ok, results} = MemoryManager.search(memory_manager, 
  "user preferences", 
  source: :embeddings,
  limit: 10,
  similarity_threshold: 0.8
)

# Pattern search in cache
{:ok, results} = MemoryManager.search(memory_manager, 
  "user_*", 
  source: :cache,
  pattern_type: :glob
)

# Count matching items
{:ok, count} = MemoryManager.count(memory_manager, "user_*", source: :cache)
```

## Advanced Operations
```elixir
# Update with function
{:ok, new_value} = MemoryManager.update(memory_manager, "counter", 
  fn current -> (current || 0) + 1 end
)

# Check existence
{:ok, exists?} = MemoryManager.exists?(memory_manager, "some_key")

# List keys with pagination
{:ok, {keys, cursor}} = MemoryManager.list_keys(memory_manager, 
  source: :persistent,
  limit: 100,
  pattern: "user_*"
)

# Get memory info
info = MemoryManager.info(memory_manager)
# Returns: %{
#   cache: %{type: :ets, size: 150, memory_usage: 2048},
#   embeddings: %{type: :vector, dimension: 1536, index_size: 10000},
#   persistent: %{type: :postgres, table: "agent_memories", row_count: 5000}
# }
```

## Dynamic Source Management
```elixir
# Add new source at runtime
:ok = MemoryManager.add_source(memory_manager, :redis_cache, 
  MyApp.RedisMemory, [host: "localhost", port: 6379]
)

# Remove source (with proper cleanup)
:ok = MemoryManager.remove_source(memory_manager, :redis_cache)

# List available sources
sources = MemoryManager.list_sources(memory_manager)
# Returns: [{:cache, MyApp.ETSMemory}, {:embeddings, MyApp.VectorMemory}, ...]
```

## Error Handling
```elixir
# Handle missing sources
case MemoryManager.store(memory_manager, "key", "value", source: :nonexistent) do
  {:ok, result} -> 
    IO.puts("Stored successfully")
  {:error, {:unknown_memory_source, :nonexistent}} -> 
    IO.puts("Source not found")
  {:error, reason} -> 
    IO.puts("Storage failed: #{inspect(reason)}")
end

# Handle unsupported operations
case MemoryManager.clear(memory_manager, source: :embeddings) do
  :ok -> 
    IO.puts("Cleared successfully")
  {:error, :clear_not_supported} -> 
    IO.puts("Clear operation not supported by this memory backend")
end
```