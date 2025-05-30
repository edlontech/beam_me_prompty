defmodule BeamMePrompty.Tools.MemoryTools do
  @moduledoc """
  Standard memory tools that can be used by LLMs to interact with agent memory.

  These tools provide a bridge between LLM tool calls and the agent's memory system,
  allowing stages to store and retrieve information across executions.
  """

  defmodule Store do
    @moduledoc """
    Tool for storing information in agent memory.
    """
    use BeamMePrompty.Tool,
      name: :memory_store,
      description: """
      Store information in the agent's memory for later retrieval. Useful for remembering facts, context, or intermediate results.
      """,
      parameters_schema: %{
        type: "object",
        properties: %{
          key: %{
            type: "string",
            description: "Unique identifier for the memory item"
          },
          value: %{
            type: ["string", "object", "array", "number", "boolean"],
            description: "The information to store"
          },
          metadata: %{
            type: "object",
            description: "Optional metadata about the stored item",
            properties: %{
              tags: %{
                type: "array",
                items: %{type: "string"},
                description: "Tags for categorizing the memory"
              },
              ttl: %{
                type: "integer",
                description: "Time to live in seconds (optional)"
              },
              source: %{
                type: "string",
                description: "Source of the information"
              }
            }
          },
          memory_source: %{
            type: "string",
            description:
              "Name of the memory source to use (optional, uses default if not specified)"
          }
        },
        required: ["key", "value"]
      }

    @impl true
    def run(%{"key" => key, "value" => value} = params, context) do
      memory_manager = get_memory_manager(context)
      metadata = Map.get(params, "metadata", %{})
      source = Map.get(params, "memory_source")

      opts = build_opts(metadata, source)

      case BeamMePrompty.Agent.MemoryManager.store(memory_manager, key, value, opts) do
        {:ok, result} ->
          {:ok,
           %{
             status: "stored",
             key: key,
             metadata: result[:metadata] || metadata
           }}

        {:error, reason} ->
          {:error, "Failed to store memory: #{inspect(reason)}"}
      end
    end

    defp get_memory_manager(context) do
      # Memory manager should be passed in the tool context
      context[:memory_manager] || raise "Memory manager not available in context"
    end

    defp build_opts(metadata, source) do
      opts = []
      opts = if source, do: [{:source, String.to_existing_atom(source)} | opts], else: opts
      opts = if metadata[:ttl], do: [{:ttl, metadata[:ttl] * 1000} | opts], else: opts
      opts = if metadata[:tags], do: [{:metadata, %{tags: metadata[:tags]}} | opts], else: opts
      opts
    end
  end

  defmodule Retrieve do
    @moduledoc """
    Tool for retrieving information from agent memory.
    """
    use BeamMePrompty.Tool,
      name: :memory_retrieve,
      description: """
      Retrieve previously stored information from the agent's memory. Useful for accessing context or facts that were stored during previous stages.
      """,
      parameters_schema: %{
        type: "object",
        properties: %{
          key: %{
            type: "string",
            description: "The key of the memory item to retrieve"
          },
          memory_source: %{
            type: "string",
            description: "Name of the memory source to use (optional)"
          }
        },
        required: ["key"]
      }

    @impl true
    def run(%{"key" => key} = params, context) do
      memory_manager = get_memory_manager(context)
      source = Map.get(params, "memory_source")

      opts = if source, do: [source: String.to_existing_atom(source)], else: []

      case BeamMePrompty.Agent.MemoryManager.retrieve(memory_manager, key, opts) do
        {:ok, value} ->
          {:ok, %{found: true, key: key, value: value}}

        {:error, :not_found} ->
          {:ok, %{found: false, key: key, message: "No memory found for key: #{key}"}}

        {:error, reason} ->
          {:error, "Failed to retrieve memory: #{inspect(reason)}"}
      end
    end

    defp get_memory_manager(context) do
      context[:memory_manager] || raise "Memory manager not available in context"
    end
  end

  defmodule Search do
    @moduledoc """
    Tool for searching through agent memory.
    """
    use BeamMePrompty.Tool,
      name: :memory_search,
      description: """
      Search through the agent's memory using queries. The query format depends on the memory backend.
      """,
      parameters_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: ["string", "object"],
            description: "Search query (format depends on memory backend)"
          },
          limit: %{
            type: "integer",
            description: "Maximum number of results to return",
            default: 10
          },
          memory_source: %{
            type: "string",
            description: "Name of the memory source to search (optional)"
          }
        },
        required: ["query"]
      }

    @impl true
    def run(%{"query" => query} = params, context) do
      memory_manager = get_memory_manager(context)
      limit = Map.get(params, "limit", 10)
      source = Map.get(params, "memory_source")

      opts = [limit: limit]
      opts = if source, do: [{:source, String.to_existing_atom(source)} | opts], else: opts

      case BeamMePrompty.Agent.MemoryManager.search(memory_manager, query, opts) do
        {:ok, results} ->
          {:ok,
           %{
             found: length(results),
             results: results
           }}

        {:error, reason} ->
          {:error, "Failed to search memory: #{inspect(reason)}"}
      end
    end

    defp get_memory_manager(context) do
      context[:memory_manager] || raise "Memory manager not available in context"
    end
  end

  defmodule Delete do
    @moduledoc """
    Tool for deleting information from agent memory.
    """
    use BeamMePrompty.Tool,
      name: :memory_delete,
      description: """
      Delete information from the agent's memory. Useful for removing outdated or incorrect facts.
      """,
      parameters_schema: %{
        type: "object",
        properties: %{
          key: %{
            type: "string",
            description: "The key of the memory item to delete"
          },
          memory_source: %{
            type: "string",
            description: "Name of the memory source to use (optional)"
          }
        },
        required: ["key"]
      }

    @impl true
    def run(%{"key" => key} = params, context) do
      memory_manager = get_memory_manager(context)
      source = Map.get(params, "memory_source")

      opts = if source, do: [source: String.to_existing_atom(source)], else: []

      case BeamMePrompty.Agent.MemoryManager.delete(memory_manager, key, opts) do
        :ok ->
          {:ok, %{status: "deleted", key: key}}

        {:error, reason} ->
          {:error, "Failed to delete memory: #{inspect(reason)}"}
      end
    end

    defp get_memory_manager(context) do
      context[:memory_manager] || raise "Memory manager not available in context"
    end
  end

  defmodule ListSources do
    @moduledoc """
    Tool for listing available memory sources and their capabilities.
    """
    use BeamMePrompty.Tool,
      name: :memory_list_sources,
      description: """
      List all available memory sources and their capabilities. Useful for understanding what memory backends are available and how to query them.
      """,
      parameters_schema: %{
        type: "object",
        properties: %{
          include_capabilities: %{
            type: "boolean",
            description: "Include detailed capability information for each source",
            default: true
          }
        }
      }

    @impl true
    def run(params, context) do
      memory_manager = get_memory_manager(context)
      include_capabilities = Map.get(params, "include_capabilities", true)

      with {:ok, sources} <- get_sources_list(memory_manager),
           {:ok, info} <- get_sources_info(memory_manager, include_capabilities) do
        {:ok, format_sources_response(sources, info, include_capabilities)}
      else
        {:error, reason} ->
          {:error, "Failed to list memory sources: #{inspect(reason)}"}
      end
    end

    defp get_memory_manager(context) do
      context[:memory_manager] || raise "Memory manager not available in context"
    end

    defp get_sources_list(memory_manager) do
      try do
        sources = BeamMePrompty.Agent.MemoryManager.list_sources(memory_manager)
        {:ok, sources}
      catch
        :exit, reason -> {:error, reason}
        error -> {:error, error}
      end
    end

    defp get_sources_info(memory_manager, true) do
      try do
        info = BeamMePrompty.Agent.MemoryManager.info(memory_manager)
        {:ok, info}
      catch
        :exit, reason -> {:error, reason}
        error -> {:error, error}
      end
    end

    defp get_sources_info(_memory_manager, false), do: {:ok, %{}}

    defp format_sources_response(sources, info, include_capabilities) do
      sources_data =
        Enum.map(sources, fn {name, module} ->
          base_info = %{
            name: name,
            module: module,
            is_default: name == get_default_source_name(sources)
          }

          if include_capabilities do
            source_info = Map.get(info, name, %{})

            Map.merge(base_info, %{
              type: Map.get(source_info, :type, :unknown),
              capabilities: get_capabilities(module, source_info),
              query_formats: get_query_formats(source_info),
              size: Map.get(source_info, :size),
              memory_usage: Map.get(source_info, :memory_usage)
            })
          else
            base_info
          end
        end)

      %{
        total_sources: length(sources),
        sources: sources_data,
        usage_notes: get_usage_notes()
      }
    end

    defp get_default_source_name(sources) do
      case sources do
        [{first_name, _} | _] -> first_name
        [] -> :default
      end
    end

    defp get_capabilities(module, source_info) do
      optional_callbacks = [
        :store_many,
        :retrieve_many,
        :count,
        :update,
        :delete_many,
        :exists?,
        :info,
        :clear
      ]

      capabilities =
        Enum.filter(optional_callbacks, fn callback ->
          function_exported?(module, callback, get_arity(callback))
        end)

      # Add any capabilities reported by the source itself
      source_capabilities = Map.get(source_info, :capabilities, [])

      Enum.uniq(capabilities ++ source_capabilities)
    end

    defp get_arity(:store_many), do: 3
    defp get_arity(:retrieve_many), do: 3
    defp get_arity(:count), do: 3
    defp get_arity(:update), do: 4
    defp get_arity(:delete_many), do: 3
    defp get_arity(:exists?), do: 3
    defp get_arity(:info), do: 1
    defp get_arity(:clear), do: 2
    defp get_arity(_), do: 3

    defp get_query_formats(source_info) do
      type = Map.get(source_info, :type, :unknown)

      case type do
        :ets ->
          [
            "Pattern matching: {:pattern, pattern}",
            "Key prefix: string prefix",
            "Simple string queries"
          ]

        :redis ->
          [
            "Redis patterns: key* or key?",
            "String queries for values"
          ]

        :vector ->
          [
            "Semantic queries: natural language strings",
            "Vector similarity searches",
            "Embedding-based queries"
          ]

        :sql ->
          [
            "SQL-like queries",
            "Structured query maps"
          ]

        :graph ->
          [
            "Graph traversal queries",
            "Cypher-like queries",
            "Node/edge relationship queries"
          ]

        :file ->
          [
            "File path patterns",
            "Content search strings"
          ]

        _ ->
          [
            "Implementation-specific query format",
            "Check source documentation for details"
          ]
      end
    end

    defp get_usage_notes do
      [
        "Use 'memory_source' parameter in other memory tools to specify which source to use",
        "If no source is specified, the default source will be used",
        "Query formats depend on the memory backend type",
        "Check capabilities to see which operations are supported by each source"
      ]
    end
  end

  defmodule ListKeys do
    @moduledoc """
    Tool for listing available memory keys.
    """
    use BeamMePrompty.Tool,
      name: :memory_list_keys,
      description: """
      List all available keys in the agent's memory. Useful for understanding what information is stored.
      """,
      parameters_schema: %{
        type: "object",
        properties: %{
          pattern: %{
            type: "string",
            description: "Optional pattern to filter keys"
          },
          limit: %{
            type: "integer",
            description: "Maximum number of keys to return",
            default: 100
          },
          memory_source: %{
            type: "string",
            description: "Name of the memory source to list from (optional)"
          }
        }
      }

    @impl true
    def run(params, context) do
      memory_manager = get_memory_manager(context)
      pattern = Map.get(params, "pattern")
      limit = Map.get(params, "limit", 100)
      source = Map.get(params, "memory_source")

      opts = [limit: limit]
      opts = if pattern, do: [{:pattern, pattern} | opts], else: opts
      opts = if source, do: [{:source, String.to_existing_atom(source)} | opts], else: opts

      case BeamMePrompty.Agent.MemoryManager.list_keys(memory_manager, opts) do
        {:ok, keys} ->
          {:ok,
           %{
             count: length(keys),
             keys: keys
           }}

        {:error, reason} ->
          {:error, "Failed to list memory keys: #{inspect(reason)}"}
      end
    end

    defp get_memory_manager(context) do
      context[:memory_manager] || raise "Memory manager not available in context"
    end
  end

  @doc """
  Returns all memory tools for use in agent stages.
  """
  def all do
    [
      Store,
      Retrieve,
      Search,
      Delete,
      ListSources,
      ListKeys
    ]
  end
end
