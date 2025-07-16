# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Primary Development Workflow
- **`mix check`** - Run all quality checks (tests, linting, formatting, type checking, security) in parallel
- **`mix check --fix`** - Run all checks and automatically fix issues where possible
- **`mix test`** - Run all tests excluding integration tests
- **`mix test.integration`** - Run integration tests only
- **`mix format`** - Format all Elixir code
- **`mix dialyzer`** - Run type checking (first run: `mix dialyzer --plt`)

### Common Development Tasks
- **`mix deps.get`** - Install/update dependencies
- **`mix compile`** - Compile the project
- **`mix credo`** - Run code quality linting
- **`mix docs`** - Generate documentation
- **`mix coveralls.html`** - Generate test coverage report

## Project Architecture

BeamMePrompty is an Elixir library for building multi-stage AI agents that orchestrate LLM interactions. The architecture follows a modular design with clear separation of concerns:

### Core Components

#### Agent System (`lib/beam_me_prompty/agent/`)
- **Agent DSL** (`dsl.ex`) - Declarative syntax for defining agent workflows with stages, dependencies, and LLM calls
- **Executor** (`executor.ex`) - Manages agent execution lifecycle and coordinates stage processing
- **Stage Management** (`stage/`) - Handles individual stage execution, message processing, and tool invocation
- **Memory System** (`memory/`, `memory_manager.ex`) - Provides persistent memory capabilities across agent executions

#### LLM Integration (`lib/beam_me_prompty/llm/`)
- **Provider Implementations** - `anthropic.ex`, `google_gemini.ex`, `open_ai.ex` for different LLM providers
- **Message Parser** (`message_parser.ex`) - Handles message format conversion between internal and provider-specific formats
- **Configuration** - Provider-specific options structures (`*_opts.ex`)

#### Tool System (`lib/beam_me_prompty/tools/`)
- **Tool Behaviour** (`tool.ex`) - Defines interface for external tool integration
- **Memory Tools** (`tools/memory/`) - Built-in tools for memory operations (store, retrieve, search, delete)

#### Error Handling (`lib/beam_me_prompty/errors/`)
- Comprehensive error hierarchy for validation, execution, parsing, and external API errors
- Structured error handling with context preservation

### Key Design Patterns

#### DAG-Based Execution
- Agents are defined as Directed Acyclic Graphs (DAGs) where stages have dependencies
- Automatic dependency resolution ensures proper execution order
- Parallel execution of independent stages when possible

#### Message-Driven Architecture
- All communication between components uses structured message passing
- Support for different message types: text, data, function calls, and thoughts
- Template system with variable interpolation using EEx

#### Behaviour-Based Extensibility
- LLM providers implement the `BeamMePrompty.LLM` behaviour
- Tools implement the `BeamMePrompty.Tool` behaviour
- Consistent interfaces enable easy extensibility

## Agent Definition Structure

Agents are defined using the DSL with this typical structure:

```elixir
defmodule MyAgent do
  use BeamMePrompty.Agent

  agent do
    stage :stage_name do
      depends_on [:previous_stage]  # Optional dependencies
      
      llm "model-name", ProviderModule do
        with_params do
          # LLM configuration
        end
        
        message :system, [text_part("System prompt")]
        message :user, [text_part("User message with <%= variable %>")]
        
        tools [MyTool]  # Optional tools
      end
    end
  end
end
```

## Testing Structure

- **Unit Tests** (`test/beam_me_prompty/`) - Test individual modules and components
- **Integration Tests** - Use `--only integration` tag, test full agent workflows
- **Test Support** (`test/support/`) - Shared test utilities, fixtures, and mock implementations
- **Fake LLM Client** (`test/support/fake_llm_client.ex`) - Mock LLM for testing without API calls

## Memory System

The memory system provides persistent storage across agent executions:
- **ETS Implementation** (`memory/ets.ex`) - In-memory storage using Erlang Term Storage
- **Memory Sources** - Different scopes for memory (global, agent-specific, stage-specific)
- **Built-in Tools** - Ready-to-use tools for memory operations in agent workflows

## Configuration

- **Mix Project** (`mix.exs`) - Defines dependencies, aliases, and project configuration
- **Development Tools** - Configured via `.check.exs`, `.credo.exs`, `.formatter.exs`, `.recode.exs`
- **Runtime Configuration** - Uses `mise.toml` for Elixir/Erlang version management

## Important Notes

- Library is **not production ready** - APIs subject to change
- Supports Elixir 1.18+ and Erlang 27+
- Heavy use of GenStateMachine for agent lifecycle management
- Comprehensive telemetry integration for monitoring and observability
- Security-focused with input validation and sanitization throughout