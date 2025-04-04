defmodule BeamMePrompty.Agent.Memory do
  @moduledoc """
  Behaviour for implementing memory systems in BeamMePrompty agents.

  Memory systems provide persistent storage and retrieval capabilities
  that persist across agent executions and can be shared between stages.

  ## Storage Types

  This behaviour is designed to support various storage backends:
  - **Key-Value Stores**: Redis, ETS, Mnesia
  - **Document Stores**: MongoDB, CouchDB
  - **Vector Databases**: Pinecone, Weaviate, Qdrant
  - **SQL Databases**: PostgreSQL, MySQL, SQLite
  - **Graph Databases**: Neo4j, ArangoDB
  - **Time-Series**: InfluxDB, TimescaleDB
  - **File-Based**: JSON, YAML, Binary files

  ## Example Implementation

      defmodule MyApp.ETSMemory do
        @behaviour BeamMePrompty.Agent.Memory
        
        @impl true
        def init(opts) do
          table = Keyword.get(opts, :table, :memory)
          :ets.new(table, [:set, :public, :named_table])
          {:ok, %{table: table}}
        end
        
        @impl true
        def store(context, key, value, opts) do
          metadata = %{
            stored_at: DateTime.utc_now(),
            ttl: Keyword.get(opts, :ttl)
          }
          
          :ets.insert(context.table, {key, value, metadata})
          {:ok, %{key: key, metadata: metadata}}
        end
        
        @impl true
        def retrieve(context, key, _opts) do
          case :ets.lookup(context.table, key) do
            [{^key, value, metadata}] -> 
              if expired?(metadata) do
                :ets.delete(context.table, key)
                {:error, :not_found}
              else
                {:ok, value}
              end
            [] -> 
              {:error, :not_found}
          end
        end
      end
  """
  @moduledoc section: :memory_management

  @type key :: term()
  @type value :: term()
  @type query :: term()
  @type context :: term()
  @type memory_result :: term()
  @type metadata :: map()
  @type opts :: keyword()
  @type error :: {:error, term()}

  # Initialization and lifecycle

  @doc """
  Initializes the memory backend.

  This is called when the memory source is first configured.
  Use this to set up connections, create tables, or perform
  any other initialization.

  ## Parameters
    * `opts` - Configuration options for the memory backend
    
  ## Returns
    * `{:ok, context}` - Success with backend-specific context
    * `{:error, reason}` - Initialization failure
  """
  @callback init(opts()) :: {:ok, context()} | error()

  @doc """
  Terminates the memory backend gracefully.

  Called when the memory source is being shut down.
  Use this to close connections, flush buffers, etc.

  ## Parameters
    * `context` - The backend context
    * `reason` - The termination reason
  """
  @callback terminate(context(), reason :: term()) :: :ok

  # Core operations

  @doc """
  Stores a value with the given key.

  ## Parameters
    * `context` - The backend context
    * `key` - The key to store the value under
    * `value` - The value to store
    * `opts` - Additional options:
      * `:ttl` - Time to live in milliseconds
      * `:metadata` - Additional metadata to store
      * `:namespace` - Logical grouping for the key
      * `:overwrite` - Whether to overwrite existing (default: true)
      
  ## Returns
    * `{:ok, result}` - Success with storage result containing metadata
    * `{:error, reason}` - Failure with reason
  """
  @callback store(context(), key(), value(), opts()) ::
              {:ok, memory_result()} | error()

  @doc """
  Stores multiple key-value pairs in a single operation.

  ## Parameters
    * `context` - The backend context
    * `items` - List of `{key, value}` tuples or `{key, value, opts}` tuples
    * `opts` - Options applied to all items
    
  ## Returns
    * `{:ok, results}` - List of results for each item
    * `{:error, reason}` - Failure with reason
  """
  @callback store_many(context(), [{key(), value()} | {key(), value(), opts()}], opts()) ::
              {:ok, [memory_result()]} | error()

  @doc """
  Retrieves a value by key.

  ## Parameters
    * `context` - The backend context
    * `key` - The key to retrieve
    * `opts` - Additional options:
      * `:include_metadata` - Include metadata in response
      * `:namespace` - Logical grouping for the key
      
  ## Returns
    * `{:ok, value}` - Success with the stored value
    * `{:ok, {value, metadata}}` - If `:include_metadata` is true
    * `{:error, :not_found}` - Key not found
    * `{:error, reason}` - Other failure
  """
  @callback retrieve(context(), key(), opts()) ::
              {:ok, value()} | {:ok, {value(), metadata()}} | error()

  @doc """
  Retrieves multiple values by keys.

  ## Parameters
    * `context` - The backend context
    * `keys` - List of keys to retrieve
    * `opts` - Additional options
    
  ## Returns
    * `{:ok, values}` - Map of key => value for found keys
    * `{:error, reason}` - Failure with reason
  """
  @callback retrieve_many(context(), [key()], opts()) ::
              {:ok, %{key() => value()}} | error()

  # Search and query operations

  @doc """
  Searches for values matching the given query.

  The query format is implementation-specific. It could be:
  - A pattern match for ETS-based memory
  - A semantic search query for vector-based memory
  - A SQL-like query for database-based memory
  - A graph traversal for graph-based memory

  ## Parameters
    * `context` - The backend context
    * `query` - The search query (format depends on implementation)
    * `opts` - Additional options:
      * `:limit` - Maximum number of results
      * `:offset` - Number of results to skip
      * `:order_by` - Ordering criteria
      * `:include_metadata` - Include metadata in results
      * `:namespace` - Limit search to namespace
      
  ## Returns
    * `{:ok, results}` - List of matching results
    * `{:error, reason}` - Search failure
  """
  @callback search(context(), query(), opts()) ::
              {:ok, [memory_result()]} | error()

  @doc """
  Counts items matching the given query.

  ## Parameters
    * `context` - The backend context
    * `query` - The count query (format depends on implementation)
    * `opts` - Additional options
    
  ## Returns
    * `{:ok, count}` - Number of matching items
    * `{:error, reason}` - Count failure
  """
  @callback count(context(), query(), opts()) ::
              {:ok, non_neg_integer()} | error()

  # Modification operations

  @doc """
  Updates a value by applying a function.

  ## Parameters
    * `context` - The backend context
    * `key` - The key to update
    * `update_fn` - Function that takes current value and returns new value
    * `opts` - Additional options
    
  ## Returns
    * `{:ok, new_value}` - Success with updated value
    * `{:error, :not_found}` - Key not found
    * `{:error, reason}` - Update failure
  """
  @callback update(context(), key(), (value() -> value()), opts()) ::
              {:ok, value()} | error()

  @doc """
  Deletes a value by key.

  ## Parameters
    * `context` - The backend context
    * `key` - The key to delete
    * `opts` - Additional options
    
  ## Returns
    * `:ok` - Success (even if key didn't exist)
    * `{:error, reason}` - Deletion failure
  """
  @callback delete(context(), key(), opts()) ::
              :ok | error()

  @doc """
  Deletes multiple values by keys.

  ## Parameters
    * `context` - The backend context
    * `keys` - List of keys to delete
    * `opts` - Additional options
    
  ## Returns
    * `{:ok, deleted_count}` - Number of items deleted
    * `{:error, reason}` - Deletion failure
  """
  @callback delete_many(context(), [key()], opts()) ::
              {:ok, non_neg_integer()} | error()

  # Utility operations

  @doc """
  Lists all available keys, optionally filtered.

  ## Parameters
    * `context` - The backend context
    * `opts` - Options that may include:
      * `:pattern` - Pattern to match keys against
      * `:namespace` - Limit to specific namespace
      * `:limit` - Maximum number of keys
      * `:cursor` - Pagination cursor
      
  ## Returns
    * `{:ok, keys}` - List of available keys
    * `{:ok, {keys, cursor}}` - If pagination is supported
    * `{:error, reason}` - Failure to list keys
  """
  @callback list_keys(context(), opts()) ::
              {:ok, [key()]} | {:ok, {[key()], cursor :: term()}} | error()

  @doc """
  Checks if a key exists.

  ## Parameters
    * `context` - The backend context
    * `key` - The key to check
    * `opts` - Additional options
    
  ## Returns
    * `{:ok, boolean}` - Whether the key exists
    * `{:error, reason}` - Check failure
  """
  @callback exists?(context(), key(), opts()) ::
              {:ok, boolean()} | error()

  @doc """
  Gets information about the memory backend.

  ## Parameters
    * `context` - The backend context
    
  ## Returns
    Map with backend-specific information such as:
    * `:type` - Backend type (e.g., :ets, :redis, :postgres)
    * `:query_format` - How to query this datasource
    * `:datasource_description` - Description of the datasource, type of storage, database type, etc.
    * `:capabilities` - List of supported features
  """
  @callback info(context()) :: map()

  @doc """
  Clears all memory (optional operation).

  Not all memory implementations may support this operation.

  ## Parameters
    * `context` - The backend context
    * `opts` - Additional options:
      * `:namespace` - Clear only specific namespace
      * `:confirm` - Safety confirmation (e.g., `confirm: true`)
      
  ## Returns
    * `:ok` - Success
    * `{:error, :not_supported}` - Operation not supported
    * `{:error, reason}` - Clear failure
  """
  @callback clear(context(), opts()) ::
              :ok | error()

  # Optional callbacks
  @optional_callbacks [
    init: 1,
    terminate: 2,
    store_many: 3,
    retrieve_many: 3,
    count: 3,
    update: 4,
    delete_many: 3,
    exists?: 3,
    info: 1,
    clear: 2
  ]
end
