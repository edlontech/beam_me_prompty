# Implementing Tools

This comprehensive guide covers how to create, implement, and use tools in BeamMePrompty agents. Tools extend agent capabilities by providing access to external APIs, databases, file systems, and other external services.

## Table of Contents

1. [Tool Fundamentals](#tool-fundamentals)
2. [Basic Tool Implementation](#basic-tool-implementation)
3. [Advanced Tool Patterns](#advanced-tool-patterns)
4. [Error Handling](#error-handling)
5. [Parameter Schemas](#parameter-schemas)
6. [Tool Categories](#tool-categories)
7. [Best Practices](#best-practices)
8. [Complete Examples](#complete-examples)

## Tool Fundamentals

### What are Tools?

Tools are modules that implement the `BeamMePrompty.Tool` behaviour, allowing LLMs to invoke external functionality. They act as bridges between the AI agent and external systems, enabling agents to:

- Make API calls to external services
- Query databases
- Process files
- Perform calculations
- Access system resources
- Interact with third-party services

### Tool Architecture

Every tool consists of:

1. **Tool Definition**: Using `use BeamMePrompty.Tool` with metadata
2. **Parameter Schema**: JSON Schema defining expected inputs
3. **Implementation**: The `run/2` callback that executes the tool logic
4. **Error Handling**: Proper error management and reporting

### Tool Structure

```elixir
defmodule MyApp.Tools.ExampleTool do
  use BeamMePrompty.Tool,
    name: :example_tool,              # Unique identifier
    description: "Description here",   # What the tool does
    parameters: %{                    # JSON Schema for inputs
      # Schema definition
    }

  @impl true
  def run(args, context) do
    # Tool implementation
  end
end
```

## Basic Tool Implementation

### 1. Simple Calculation Tool

```elixir
defmodule MyApp.Tools.Calculator do
  use BeamMePrompty.Tool,
    name: :calculate,
    description: "Performs basic arithmetic operations",
    parameters: %{
      type: "object",
      properties: %{
        operation: %{
          type: "string",
          description: "The operation to perform",
          enum: ["add", "subtract", "multiply", "divide"]
        },
        a: %{
          type: "number",
          description: "First number"
        },
        b: %{
          type: "number",
          description: "Second number"
        }
      },
      required: ["operation", "a", "b"]
    }

  @impl true
  def run(%{"operation" => "add", "a" => a, "b" => b}, _context) do
    {:ok, %{result: a + b, operation: "addition"}}
  end

  def run(%{"operation" => "subtract", "a" => a, "b" => b}, _context) do
    {:ok, %{result: a - b, operation: "subtraction"}}
  end

  def run(%{"operation" => "multiply", "a" => a, "b" => b}, _context) do
    {:ok, %{result: a * b, operation: "multiplication"}}
  end

  def run(%{"operation" => "divide", "a" => a, "b" => b}, _context) when b != 0 do
    {:ok, %{result: a / b, operation: "division"}}
  end

  def run(%{"operation" => "divide", "a" => _a, "b" => 0}, _context) do
    alias BeamMePrompty.LLM.Errors.ToolError
    {:error, %ToolError{module: __MODULE__, cause: "Division by zero is not allowed"}}
  end

  def run(args, _context) do
    alias BeamMePrompty.LLM.Errors.ToolError
    {:error, %ToolError{module: __MODULE__, cause: "Invalid arguments: #{inspect(args)}"}}
  end
end
```

