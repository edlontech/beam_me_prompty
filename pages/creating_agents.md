# Creating Agents in BeamMePrompty

This guide provides comprehensive documentation on creating agents in BeamMePrompty, covering all patterns: stateful vs stateless, with and without memory, persistent vs non-persistent.

## Table of Contents

1. [Agent Fundamentals](#agent-fundamentals)
2. [Agent Architecture](#agent-architecture)
3. [Basic Agent Creation](#basic-agent-creation)
4. [Agent State Management](#agent-state-management)
5. [Memory Systems](#memory-systems)
6. [Agent Persistence](#agent-persistence)
7. [Complete Examples](#complete-examples)
8. [Best Practices](#best-practices)

## Agent Fundamentals

### Core Concepts

**Agent**: A workflow composed of multiple stages that can be executed synchronously or asynchronously.

**Stage**: Individual steps in the agent workflow that can make LLM calls, use tools, depend on other stages, and access memory.

**Memory Sources**: Persistent storage for agent data, enabling stateful behavior across interactions.

**Tools**: Extensions that provide access to external APIs, databases, file systems, etc.

### Agent Types

BeamMePrompty supports four primary agent patterns:

1. **Stateless without Memory**: Simple agents that start fresh each time
2. **Stateless with Memory**: Agents that can access persistent storage but don't maintain session state
3. **Stateful without Memory**: Agents that maintain session state but don't persist data
4. **Stateful with Memory**: Full-featured agents with both session state and persistent storage

## Agent Architecture

### DSL Structure

Agents are defined using a declarative DSL with these key components:

```elixir
defmodule MyAgent do
  use BeamMePrompty.Agent

  # Optional: Memory configuration
  memory do
    memory_source :name, Module, options
  end

  # Agent definition
  agent do
    name "Agent Name"
    agent_state :stateless | :stateful  # Default: :stateless
    version "1.0.0"                     # Default: "0.0.1"

    stage :stage_name do
      depends_on [:previous_stage]      # Optional dependencies
      entrypoint true                   # Optional: can be entry point
      
      llm "model-name", ProviderModule do
        with_params do
          # LLM configuration
        end
        
        message :system, [text_part("System prompt")]
        message :user, [text_part("User message with <%= variable %>")]
        
        tools [ToolModule]              # Optional tools
      end
    end
  end
end
```

### Message Parts

BeamMePrompty supports various message part types:

- **TextPart**: Plain text content with EEx templating support
- **DataPart**: Structured data (maps) serialized as JSON
- **FilePart**: File-based content (typically images)
- **FunctionCallPart**: LLM requests to invoke tools
- **FunctionResultPart**: Tool execution results
- **ThoughtPart**: LLM reasoning steps (model-dependent)

## Basic Agent Creation

### 1. Stateless Agent without Memory

The simplest agent type - starts fresh each execution:

```elixir
defmodule MyApp.SimpleAgent do
  use BeamMePrompty.Agent

  agent do
    name "Simple Agent"
    # agent_state :stateless  # Default, can be omitted
    
    stage :greet do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
          temperature 0.7
        end

        message :system, [text_part("You are a friendly assistant.")]
        message :user, [text_part("Say hello to <%= name %>!")]
      end
    end
  end
end

# Usage
{:ok, result} = MyApp.SimpleAgent.run_sync(%{name: "Alice"})
```

### 2. Multi-Stage Agent

Agents can have multiple interdependent stages:

```elixir
defmodule MyApp.MultiStageAgent do
  use BeamMePrompty.Agent

  agent do
    name "Multi-Stage Agent"
    
    stage :analyze do
      llm "claude-3-haiku-20240307", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("ANTHROPIC_API_KEY") end
        end

        message :system, [text_part("You are an analyst.")]
        message :user, [text_part("Analyze: <%= input %>")]
      end
    end

    stage :summarize do
      depends_on [:analyze]  # Runs after analyze completes
      
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
        end

        message :system, [text_part("You are a summarizer.")]
        message :user, [
          text_part("Summarize this analysis:"),
          data_part(%{analysis: <%= analyze.result %>})
        ]
      end
    end
  end
end
```

## Agent State Management

### Stateless vs Stateful Agents

**Stateless Agents (Default)**:
- No session state maintained between calls
- Each execution starts fresh
- Suitable for simple, independent tasks
- Lower memory overhead

**Stateful Agents**:
- Maintain session state between calls
- Can accumulate context over time
- Suitable for conversational or iterative tasks
- Higher memory overhead

```elixir
defmodule MyApp.StatefulAgent do
  use BeamMePrompty.Agent

  agent do
    name "Stateful Agent"
    agent_state :stateful  # Enable stateful behavior
    version "1.0.0"
    
    stage :converse do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        message :system, [text_part("You are a conversational assistant.")]
        message :user, [text_part("User says: <%= message %>")]
      end
    end
  end
end

# Usage - state persists across calls
{:ok, pid} = MyApp.StatefulAgent.start_link([
  input: %{message: "Hello"},
  session_id: make_ref()
])
```

### Agent Lifecycle

**Synchronous Execution**:
```elixir
{:ok, result} = MyAgent.run_sync(
  %{input: "data"},      # Input data
  %{state: "initial"},   # Initial state
  [],                    # Options
  30_000                 # Timeout (ms)
)
```

**Asynchronous Execution**:
```elixir
{:ok, pid} = MyAgent.start_link([
  input: %{data: "value"},
  initial_state: %{},
  session_id: make_ref()
])
```

## Memory Systems

### Memory Architecture

BeamMePrompty provides a flexible memory system that supports:

- **Multiple memory sources** per agent
- **Scoped memory** (global, agent-specific, stage-specific)
- **Automatic tool injection** for memory operations
- **Pluggable backends** (ETS, external databases, etc.)

### Built-in Memory: ETS

The ETS (Erlang Term Storage) backend provides fast, in-memory storage:

```elixir
defmodule MyApp.AgentWithMemory do
  use BeamMePrompty.Agent

  memory do
    memory_source :short_term_cache, BeamMePrompty.Agent.Memory.ETS,
      description: "Fast, temporary storage for intermediate results",
      opts: [table: :my_agent_cache],
      default: true
  end

  agent do
    name "Agent with Memory"
    
    stage :process do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        message :system, [
          text_part("You have access to memory tools for storing and retrieving data.")
        ]
        message :user, [text_part("Process: <%= data %>")]
        
        # Memory tools automatically injected:
        # - :memory_store
        # - :memory_retrieve
        # - :memory_search
        # - :memory_delete
        # - :memory_list_keys
        # - :memory_clear
      end
    end
  end
end
```

### Memory Operations

When memory sources are configured, the following tools are automatically available:

- **memory_store**: Store data with optional TTL and tags
- **memory_retrieve**: Retrieve data by key
- **memory_search**: Search data using patterns
- **memory_delete**: Remove data by key
- **memory_list_keys**: List all stored keys
- **memory_clear**: Clear all stored data

### ETS Memory Characteristics

**Advantages**:
- Very fast read/write operations
- Atomic operations
- TTL support with automatic cleanup
- Metadata storage (tags, timestamps)
- Pattern matching capabilities

**Limitations**:
- Data lost when process terminates
- Single-node only (no clustering)
- Memory usage grows with data
- Limited to simple pattern matching

**Best Used For**:
- Development and testing
- Session storage
- Temporary calculations
- Agent working memory
- Small to medium datasets (< 10MB)

## Agent Persistence

### Persistent Agent Storage

BeamMePrompty provides a persistence layer for storing agent configurations and metadata:

```elixir
# Store agent configuration
{:ok, persisted_agent} = BeamMePrompty.PersistedAgents.create_agent(
  MyRepo,
  %{
    agent_name: "MyAgent",
    agent_version: "1.0.0",
    agent_type: "conversational",
    agent_spec: %{
      # Agent configuration
    },
    metadata: %{
      category: "customer_service",
      status: "active"
    }
  }
)

# Retrieve agent
{:ok, agent} = BeamMePrompty.PersistedAgents.get_agent(MyRepo, agent_id)

# Query by metadata
{:ok, agents} = BeamMePrompty.PersistedAgents.get_agents_by_metadata(
  MyRepo,
  %{"category" => "customer_service"}
)
```

## Complete Examples

### 1. Simple Stateless Agent

```elixir
defmodule MyApp.SimpleGreeter do
  use BeamMePrompty.Agent

  agent do
    name "Simple Greeter"
    
    stage :greet do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
          temperature 0.7
        end

        message :system, [text_part("You are a friendly greeter.")]
        message :user, [text_part("Greet <%= name %> in <%= language %>.")]
      end
    end
  end
end

# Usage
{:ok, result} = MyApp.SimpleGreeter.run_sync(%{
  name: "Alice",
  language: "Spanish"
})
```

### 2. Stateless Agent with Memory

```elixir
defmodule MyApp.DataProcessor do
  use BeamMePrompty.Agent

  memory do
    memory_source :data_cache, BeamMePrompty.Agent.Memory.ETS,
      description: "Cache for processed data to avoid recomputation",
      opts: [table: :data_processor_cache],
      default: true
  end

  agent do
    name "Data Processor"
    
    stage :process do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
        end

        message :system, [
          text_part("Process data efficiently. Check cache first, store results after processing.")
        ]
        message :user, [text_part("Process this data: <%= data %>")]
      end
    end
  end
end

# Each call is independent but can use shared cache
{:ok, result1} = MyApp.DataProcessor.run_sync(%{data: "dataset1"})
{:ok, result2} = MyApp.DataProcessor.run_sync(%{data: "dataset2"})
```

### 3. Stateful Agent without Memory

```elixir
defmodule MyApp.Conversation do
  use BeamMePrompty.Agent

  agent do
    name "Conversation Agent"
    agent_state :stateful  # Maintains session state
    
    stage :chat do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
        end

        message :system, [
          text_part("You are having a conversation. Remember context from previous messages.")
        ]
        message :user, [text_part("User: <%= message %>")]
      end
    end
  end
end

# Start conversation session
{:ok, pid} = MyApp.Conversation.start_link([
  input: %{message: "Hello, I'm Alice"},
  session_id: make_ref()
])

# Continue conversation (state maintained)
GenServer.call(pid, {:continue, %{message: "What's my name?"}})
```

### 3b. Stateful Agent with AgentSupervisor

For production use, manage stateful agents with the AgentSupervisor for better fault tolerance:

```elixir
defmodule MyApp.ManagedConversation do
  use BeamMePrompty.Agent

  import BeamMePrompty.Agent.Dsl.Part

  agent do
    name "Managed Conversation Agent"
    agent_state :stateful
    version "1.0.0"
    
    stage :chat do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
          temperature 0.7
        end

        message :system, [
          text_part("You are a helpful conversational assistant. Maintain context across messages.")
        ]
        message :user, [text_part("User: <%= message %>")]
      end
    end
  end
end

# Start the BeamMePrompty application (includes AgentSupervisor)
{:ok, _} = Application.ensure_all_started(:beam_me_prompty)

# Create a session ID for the conversation
session_id = make_ref()

# Start the agent under supervision
{:ok, agent_pid} = BeamMePrompty.AgentSupervisor.start_agent(
  MyApp.ManagedConversation,
  [
    input: %{message: "Hello, I'm Alice and I work at Acme Corp"},
    session_id: session_id
  ]
)

# Wait for initial processing
{:ok, :completed, initial_result} = BeamMePrompty.Agent.Executor.get_results(agent_pid)
IO.puts("Initial response: #{initial_result}")

# Continue the conversation using the session ID
{:ok, response1} = BeamMePrompty.AgentSupervisor.send_message(
  session_id,
  text_part("What's my name and where do I work?")
)
IO.puts("Response 1: #{response1}")

# Send another message - context is maintained
{:ok, response2} = BeamMePrompty.AgentSupervisor.send_message(
  session_id,
  text_part("What can you tell me about my company?")
)
IO.puts("Response 2: #{response2}")

# Get final results
{:ok, :completed, final_results} = BeamMePrompty.Agent.Executor.get_results(agent_pid)
```

### AgentSupervisor Features

The AgentSupervisor provides several advantages for managing stateful agents:

**Process Management**:
- Automatic process registration using session IDs
- Fault tolerance through supervision trees
- Process isolation and recovery

**Message Passing**:
- Send messages to agents using either PID or session ID
- Automatic process lookup via Registry
- Type-safe message validation

**Production Considerations**:
```elixir
# In your application supervision tree
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Start BeamMePrompty supervisor
      BeamMePrompty.AgentSupervisor,
      
      # Your other application processes
      MyApp.Repo,
      MyApp.Web.Endpoint
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# Multiple concurrent conversations
defmodule MyApp.ConversationManager do
  def start_conversation(user_id, initial_message) do
    session_id = make_ref()
    
    {:ok, agent_pid} = BeamMePrompty.AgentSupervisor.start_agent(
      MyApp.ManagedConversation,
      [
        input: %{message: initial_message},
        session_id: session_id
      ]
    )
    
    # Store session mapping for later use
    :ets.insert(:user_sessions, {user_id, session_id})
    
    {:ok, session_id, agent_pid}
  end
  
  def send_message(user_id, message) do
    case :ets.lookup(:user_sessions, user_id) do
      [{^user_id, session_id}] ->
        BeamMePrompty.AgentSupervisor.send_message(
          session_id,
          text_part(message)
        )
      
      [] ->
        {:error, :no_active_session}
    end
  end
  
  def get_conversation_state(user_id) do
    case :ets.lookup(:user_sessions, user_id) do
      [{^user_id, session_id}] ->
        agent_pid = {:via, Registry, {:agents, session_id}}
        BeamMePrompty.Agent.Executor.get_results(agent_pid)
      
      [] ->
        {:error, :no_active_session}
    end
  end
end
```

### 4. Stateful Agent with Memory

```elixir
defmodule MyApp.AdvancedAssistant do
  use BeamMePrompty.Agent

  alias MyApp.Tools.{WebSearch, Calculator, FileManager}

  memory do
    memory_source :conversation_history, BeamMePrompty.Agent.Memory.ETS,
      description: "Stores conversation history and user preferences",
      opts: [table: :assistant_memory],
      default: true
  end

  agent do
    name "Advanced Assistant"
    agent_state :stateful  # Maintains session state
    version "2.0.0"
    
    stage :understand do
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
          temperature 0.8
        end

        message :system, [
          text_part("You are an advanced assistant with access to tools and memory.")
        ]
        message :user, [text_part("User request: <%= request %>")]
        
        tools [WebSearch, Calculator, FileManager]
      end
    end

    stage :respond do
      depends_on [:understand]
      
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
          temperature 0.7
        end

        message :system, [
          text_part("Provide a helpful response based on understanding and tool results.")
        ]
        message :user, [
          text_part("Based on understanding:"),
          data_part(%{understanding: <%= understand.result %>})
        ]
      end
    end
  end
end

# Usage with full features
{:ok, pid} = MyApp.AdvancedAssistant.start_link([
  input: %{request: "Research AI trends and calculate market growth"},
  session_id: make_ref()
])
```

### 5. Multi-Stage Research Agent

```elixir
defmodule MyApp.ResearchAgent do
  use BeamMePrompty.Agent

  alias MyApp.Tools.WebSearch

  memory do
    memory_source :research_data, BeamMePrompty.Agent.Memory.ETS,
      description: "Stores research findings and analysis results",
      opts: [table: :research_memory],
      default: true
  end

  agent do
    name "Research Agent"
    version "1.0.0"
    
    stage :search do
      llm "gemini-1.5-flash", BeamMePrompty.LLM.GoogleGemini do
        with_params do
          api_key fn -> System.get_env("GOOGLE_API_KEY") end
          temperature 0.7
        end

        message :system, [
          text_part("You are a research assistant. Search for information on the given topic.")
        ]
        message :user, [text_part("Research topic: <%= topic %>")]
        
        tools [WebSearch]
      end
    end

    stage :analyze do
      depends_on [:search]
      
      llm "claude-3-sonnet-20240229", BeamMePrompty.LLM.Anthropic do
        with_params do
          api_key fn -> System.get_env("ANTHROPIC_API_KEY") end
        end

        message :system, [
          text_part("Analyze research findings and identify key insights.")
        ]
        message :user, [
          text_part("Analyze findings:"),
          data_part(%{findings: <%= search.result %>})
        ]
      end
    end

    stage :summarize do
      depends_on [:analyze]
      
      llm "gpt-4", BeamMePrompty.LLM.OpenAI do
        with_params do
          api_key fn -> System.get_env("OPENAI_API_KEY") end
          max_tokens 1000
        end

        message :system, [
          text_part("Create a comprehensive summary of the research and analysis.")
        ]
        message :user, [
          text_part("Create summary from:"),
          data_part(%{
            search_results: <%= search.result %>,
            analysis: <%= analyze.result %>
          })
        ]
      end
    end
  end
end

# Usage
{:ok, result} = MyApp.ResearchAgent.run_sync(%{
  topic: "Artificial Intelligence in Healthcare 2024"
})
```

