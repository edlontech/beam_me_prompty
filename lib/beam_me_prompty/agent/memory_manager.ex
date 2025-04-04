defmodule BeamMePrompty.Agent.MemoryManager do
  @moduledoc """
  Manages multiple memory sources for an agent with proper lifecycle management.

  Provides a unified interface for memory operations across multiple backends.
  Each memory source is identified by a name, properly initialized with context,
  and validated to ensure it implements the Memory behavior.

  ## Example

      {:ok, memory_manager} = MemoryManager.start_link([
        {:short_term, {MyApp.ETSMemory, [table: :cache]}},
        {:long_term, {MyApp.VectorMemory, [dimension: 1536]}}
      ])
      
      # Store in default source
      MemoryManager.store(memory_manager, "key1", "value1")
      
      # Store in specific source
      MemoryManager.store(memory_manager, "key2", "value2", source: :long_term)
      

      MemoryManager.search(memory_manager, "query")
      
      # Batch operations
      MemoryManager.store_many(memory_manager, [{"k1", "v1"}, {"k2", "v2"}])
  """
  @moduledoc section: :memory_management

  use GenServer
  use TypedStruct

  alias BeamMePrompty.Agent.Memory

  @type source_spec :: {atom(), {module(), keyword()}}
  @type source_context :: {module(), Memory.context()}

  typedstruct do
    field :sources, %{atom() => source_context()}, default: %{}
    field :default_source, atom(), default: :default
  end

  # Client API

  @doc """
  Starts a memory manager with the given sources.

  ## Parameters
    * `sources` - List of `{name, {module, opts}}` pairs
    * `opts` - GenServer options
    
  ## Examples
      {:ok, pid} = MemoryManager.start_link([
        {:cache, {MyApp.ETSMemory, [table: :cache]}},
        {:persistent, {MyApp.FileMemory, [path: "/tmp/memory"]}}
      ])
  """
  @spec start_link([source_spec()], keyword()) :: GenServer.on_start()
  def start_link(sources \\ [], opts \\ []) do
    GenServer.start_link(__MODULE__, sources, opts)
  end

  @doc """
  Adds a new memory source to the manager.
  """
  @spec add_source(GenServer.server(), atom(), module(), keyword()) ::
          :ok | {:error, term()}
  def add_source(manager, name, module, opts \\ []) do
    GenServer.call(manager, {:add_source, name, module, opts})
  end

  @doc """
  Removes a memory source from the manager.
  """
  @spec remove_source(GenServer.server(), atom()) :: :ok | {:error, term()}
  def remove_source(manager, name) do
    GenServer.call(manager, {:remove_source, name})
  end

  @doc """
  Sets the default memory source.
  """
  @spec set_default_source(GenServer.server(), atom()) ::
          :ok | {:error, :unknown_source}
  def set_default_source(manager, source_name) do
    GenServer.call(manager, {:set_default_source, source_name})
  end

  @doc """
  Lists all configured memory sources.
  """
  @spec list_sources(GenServer.server()) :: [{atom(), module()}]
  def list_sources(manager) do
    GenServer.call(manager, :list_sources)
  end

  @doc """
  Gets information about all memory sources.
  """
  @spec info(GenServer.server()) :: %{atom() => map()}
  def info(manager) do
    GenServer.call(manager, :info)
  end

  # Core Memory Operations

  @doc """
  Stores a value in the specified source (or default).
  """
  @spec store(GenServer.server(), Memory.key(), Memory.value(), keyword()) ::
          {:ok, Memory.memory_result()} | {:error, term()}
  def store(manager, key, value, opts \\ []) do
    GenServer.call(manager, {:store, key, value, opts})
  end

  @doc """
  Stores multiple key-value pairs in a single operation.
  """
  @spec store_many(
          GenServer.server(),
          [{Memory.key(), Memory.value()} | {Memory.key(), Memory.value(), keyword()}],
          keyword()
        ) ::
          {:ok, [Memory.memory_result()]} | {:error, term()}
  def store_many(manager, items, opts \\ []) do
    GenServer.call(manager, {:store_many, items, opts})
  end

  @doc """
  Retrieves a value from the specified source (or default).
  """
  @spec retrieve(GenServer.server(), Memory.key(), keyword()) ::
          {:ok, Memory.value()} | {:ok, {Memory.value(), Memory.metadata()}} | {:error, term()}
  def retrieve(manager, key, opts \\ []) do
    GenServer.call(manager, {:retrieve, key, opts})
  end

  @doc """
  Retrieves multiple values by keys.
  """
  @spec retrieve_many(GenServer.server(), [Memory.key()], keyword()) ::
          {:ok, %{Memory.key() => Memory.value()}} | {:error, term()}
  def retrieve_many(manager, keys, opts \\ []) do
    GenServer.call(manager, {:retrieve_many, keys, opts})
  end

  @doc """
  Searches for values in the specified source (or default).
  """
  @spec search(GenServer.server(), Memory.query(), keyword()) ::
          {:ok, [Memory.memory_result()]} | {:error, term()}
  def search(manager, query, opts \\ []) do
    GenServer.call(manager, {:search, query, opts})
  end

  @doc """
  Counts items matching the given query.
  """
  @spec count(GenServer.server(), Memory.query(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count(manager, query, opts \\ []) do
    GenServer.call(manager, {:count, query, opts})
  end

  @doc """
  Updates a value by applying a function.
  """
  @spec update(GenServer.server(), Memory.key(), (Memory.value() -> Memory.value()), keyword()) ::
          {:ok, Memory.value()} | {:error, term()}
  def update(manager, key, update_fn, opts \\ []) do
    GenServer.call(manager, {:update, key, update_fn, opts})
  end

  @doc """
  Deletes from the specified source (or default).
  """
  @spec delete(GenServer.server(), Memory.key(), keyword()) :: :ok | {:error, term()}
  def delete(manager, key, opts \\ []) do
    GenServer.call(manager, {:delete, key, opts})
  end

  @doc """
  Deletes multiple values by keys.
  """
  @spec delete_many(GenServer.server(), [Memory.key()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def delete_many(manager, keys, opts \\ []) do
    GenServer.call(manager, {:delete_many, keys, opts})
  end

  @doc """
  Lists keys from the specified source (or default).
  """
  @spec list_keys(GenServer.server(), keyword()) ::
          {:ok, [Memory.key()]} | {:ok, {[Memory.key()], term()}} | {:error, term()}
  def list_keys(manager, opts \\ []) do
    GenServer.call(manager, {:list_keys, opts})
  end

  @doc """
  Checks if a key exists.
  """
  @spec exists?(GenServer.server(), Memory.key(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def exists?(manager, key, opts \\ []) do
    GenServer.call(manager, {:exists?, key, opts})
  end

  @doc """
  Clears memory from the specified source (or default).
  """
  @spec clear(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def clear(manager, opts \\ []) do
    GenServer.call(manager, {:clear, opts})
  end

  @impl GenServer
  def init(sources) do
    case initialize_sources(sources) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call({:add_source, name, module, opts}, _from, state) do
    case validate_and_initialize_source(name, module, opts) do
      {:ok, {module, context}} ->
        updated_sources = Map.put(state.sources, name, {module, context})

        default_source =
          if map_size(state.sources) == 0 do
            name
          else
            state.default_source
          end

        new_state = %{state | sources: updated_sources, default_source: default_source}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:remove_source, name}, _from, state) do
    case Map.get(state.sources, name) do
      nil ->
        {:reply, {:error, :unknown_source}, state}

      {module, context} ->
        # Terminate the source if it supports termination
        if function_exported?(module, :terminate, 2) do
          module.terminate(context, :shutdown)
        end

        updated_sources = Map.delete(state.sources, name)

        new_default = determine_new_default_source(state.default_source, name, updated_sources)

        new_state = %{state | sources: updated_sources, default_source: new_default}
        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:set_default_source, source_name}, _from, state) do
    if Map.has_key?(state.sources, source_name) do
      new_state = %{state | default_source: source_name}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :unknown_source}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_sources, _from, state) do
    sources = Enum.map(state.sources, fn {name, {module, _context}} -> {name, module} end)
    {:reply, sources, state}
  end

  @impl GenServer
  def handle_call(:info, _from, state) do
    info_map =
      for {name, {module, context}} <- state.sources, into: %{} do
        source_info =
          if function_exported?(module, :info, 1) do
            module.info(context)
          else
            %{type: :unknown, module: module}
          end

        {name, source_info}
      end

    {:reply, info_map, state}
  end

  # Memory operation handlers
  @impl GenServer
  def handle_call({operation, key, opts}, _from, state)
      when operation in [:retrieve, :delete, :exists?] do
    case get_source_context(state, opts) do
      {:ok, {module, context}} ->
        source_opts = extract_source_opts(opts)
        result = apply(module, operation, [context, key, source_opts])
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({operation, key, value, opts}, _from, state)
      when operation in [:store, :update] do
    case get_source_context(state, opts) do
      {:ok, {module, context}} ->
        source_opts = extract_source_opts(opts)
        result = apply(module, operation, [context, key, value, source_opts])
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({operation, query_or_items, opts}, _from, state)
      when operation in [:search, :count, :store_many, :retrieve_many, :delete_many] do
    case get_source_context(state, opts) do
      {:ok, {module, context}} ->
        source_opts = extract_source_opts(opts)

        result =
          if function_exported?(module, operation, 3) do
            apply(module, operation, [context, query_or_items, source_opts])
          else
            {:error, {:operation_not_supported, operation}}
          end

        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_keys, opts}, _from, state) do
    case get_source_context(state, opts) do
      {:ok, {module, context}} ->
        source_opts = extract_source_opts(opts)
        result = module.list_keys(context, source_opts)
        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:clear, opts}, _from, state) do
    case get_source_context(state, opts) do
      {:ok, {module, context}} ->
        source_opts = extract_source_opts(opts)

        result =
          if function_exported?(module, :clear, 2) do
            module.clear(context, source_opts)
          else
            {:error, :clear_not_supported}
          end

        {:reply, result, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def terminate(reason, state) do
    for {_name, {module, context}} <- state.sources do
      if function_exported?(module, :terminate, 2) do
        module.terminate(context, reason)
      end
    end

    :ok
  end

  # Private Functions

  defp determine_new_default_source(current_default, removed_source, remaining_sources) do
    if current_default == removed_source do
      case Map.keys(remaining_sources) do
        [] -> :default
        [first | _] -> first
      end
    else
      current_default
    end
  end

  defp initialize_sources(sources) do
    with {:ok, source_contexts} <- validate_and_initialize_all(sources) do
      default_source =
        case Map.keys(source_contexts) do
          [] -> :default
          [first | _] -> first
        end

      state = %__MODULE__{
        sources: source_contexts,
        default_source: default_source
      }

      {:ok, state}
    end
  end

  defp validate_and_initialize_all(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn {name, {module, opts}}, {:ok, acc} ->
      case validate_and_initialize_source(name, module, opts) do
        {:ok, source_context} ->
          {:cont, {:ok, Map.put(acc, name, source_context)}}

        {:error, reason} ->
          {:halt, {:error, {name, reason}}}
      end
    end)
  end

  defp validate_and_initialize_source(name, module, opts) do
    case module.init(opts) do
      {:ok, context} ->
        {:ok, {module, context}}

      {:error, reason} ->
        {:error, {name, reason}}
    end
  end

  defp get_source_context(state, opts) do
    source_name = Keyword.get(opts, :source, state.default_source)

    case Map.get(state.sources, source_name) do
      nil -> {:error, {:unknown_memory_source, source_name}}
      source_context -> {:ok, source_context}
    end
  end

  defp extract_source_opts(opts) do
    Keyword.delete(opts, :source)
  end
end
