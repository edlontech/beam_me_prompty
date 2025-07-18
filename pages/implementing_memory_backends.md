# Implementing Memory Backends

This comprehensive guide covers how to create custom memory backends for BeamMePrompty agents. Memory backends provide persistent storage and retrieval capabilities that can be shared across agent executions and stages.

## Table of Contents

1. [Memory System Overview](#memory-system-overview)
2. [Memory Behaviour Interface](#memory-behaviour-interface)
3. [Basic Memory Implementations](#basic-memory-implementations)
4. [Advanced Memory Backends](#advanced-memory-backends)
5. [Vector Memory Backends](#vector-memory-backends)
6. [Database Memory Backends](#database-memory-backends)
7. [Distributed Memory Backends](#distributed-memory-backends)
8. [Best Practices](#best-practices)
9. [Testing Memory Backends](#testing-memory-backends)

## Memory System Overview

### Architecture

BeamMePrompty's memory system consists of:

1. **Memory Behaviour**: Interface defining required callbacks
2. **Memory Manager**: Coordinates multiple memory sources
3. **Memory Sources**: Individual backend implementations
4. **Memory Tools**: Automatically injected tools for agent access

### Supported Storage Types

The memory system supports various storage backends:

- **Key-Value Stores**: Redis, ETS, Mnesia
- **Document Stores**: MongoDB, CouchDB
- **Vector Databases**: Pinecone, Weaviate, Qdrant
- **SQL Databases**: PostgreSQL, MySQL, SQLite
- **Graph Databases**: Neo4j, ArangoDB
- **Time-Series**: InfluxDB, TimescaleDB
- **File-Based**: JSON, YAML, Binary files

### Memory Operations

Core operations supported by all memory backends:

- **store/retrieve**: Basic key-value operations
- **search**: Query-based retrieval
- **list_keys**: Key enumeration
- **delete**: Value removal
- **clear**: Bulk operations
- **count**: Query result counting
- **update**: Value modification

## Memory Behaviour Interface

### Required Callbacks

```elixir
@callback init(opts()) :: {:ok, context()} | {:error, term()}
@callback store(context(), key(), value(), opts()) :: {:ok, memory_result()} | {:error, term()}
@callback retrieve(context(), key(), opts()) :: {:ok, value()} | {:error, term()}
@callback search(context(), query(), opts()) :: {:ok, [memory_result()]} | {:error, term()}
@callback delete(context(), key(), opts()) :: :ok | {:error, term()}
@callback list_keys(context(), opts()) :: {:ok, [key()]} | {:error, term()}
```

### Optional Callbacks

```elixir
@callback terminate(context(), reason :: term()) :: :ok
@callback store_many(context(), [items], opts()) :: {:ok, [memory_result()]} | {:error, term()}
@callback retrieve_many(context(), [key()], opts()) :: {:ok, %{key() => value()}} | {:error, term()}
@callback count(context(), query(), opts()) :: {:ok, non_neg_integer()} | {:error, term()}
@callback update(context(), key(), (value() -> value()), opts()) :: {:ok, value()} | {:error, term()}
@callback delete_many(context(), [key()], opts()) :: {:ok, non_neg_integer()} | {:error, term()}
@callback exists?(context(), key(), opts()) :: {:ok, boolean()} | {:error, term()}
@callback clear(context(), opts()) :: :ok | {:error, term()}
@callback info(context()) :: map()
```

## Usage Examples

### Setting Up Memory Sources in Agents

```elixir
defmodule MyApp.SmartAgent do
  use BeamMePrompty.Agent
  
  # Configure multiple memory sources
  memory do
    # Fast cache for temporary data
    memory_source :cache, MyApp.Memory.ETS,
      description: "Fast temporary cache for session data",
      opts: [table: :agent_cache, cleanup_interval: 30_000],
      default: true
    
    # Persistent storage for long-term memory
    memory_source :persistent, MyApp.Memory.PostgreSQL,
      description: "Long-term persistent storage",
      opts: [
        repo: MyApp.Repo,
        table_name: "agent_memory",
        schema_name: "public"
      ]
    
    # Vector storage for semantic search
    memory_source :vectors, MyApp.Memory.Vector,
      description: "Vector storage for semantic search",
      opts: [
        dimension: 1536,
        embedding_model: MyApp.Embeddings.OpenAI,
        similarity_threshold: 0.8
      ]
  end
  
  agent do
    name "Smart Agent with Multiple Memory Sources"
    
    stage :process_with_memory do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        message :system, [
          text_part("You have access to multiple memory sources: cache, persistent, and vectors.")
        ]
        message :user, [text_part("Process: <%= input %>")]
      end
    end
  end
end
```
