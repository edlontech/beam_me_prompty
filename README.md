<p align="center">
  <img width="300" height="300" src="https://iili.io/31BBn9I.th.png">
</p>

# BeamMePrompty

A powerful Elixir library for building and orchestrating intelligent, prompt-driven agents. BeamMePrompty simplifies the creation of complex AI workflows through a declarative DSL, enabling seamless integration with Large Language Models (LLMs) and external tools.

## ✨ Key Features

- **🔗 Multi-stage Orchestration**: Define complex workflows using a simple, intuitive DSL with automatic dependency resolution via DAG (Directed Acyclic Graph)
- **🤖 LLM Integration**: Built-in support for multiple LLM providers (Google Gemini, Anthropic) with extensible architecture
- **🛠️ Tool Invocation**: Seamless external tool integration with function calling capabilities
- **⚡ Flexible Execution**: Support for both synchronous and asynchronous execution patterns
- **🎛️ Customizable Handlers**: Extensible callback system for custom execution logic
- **📝 Template System**: Dynamic message templating with variable interpolation
- **🔧 Type Safety**: Leverages Elixir's pattern matching and behaviours for robust agent definitions

## 🚀 Quick Start

### Installation

Add `beam_me_prompty` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:beam_me_prompty, "~> 0.1.0"}
  ]
end
```

### Basic Usage

1. **Define an Agent**: Create a module using the `BeamMePrompty.Agent` DSL
2. **Configure LLM**: Set up your preferred LLM provider with API credentials
3. **Execute**: Run the agent synchronously or asynchronously

## 📋 Defining Agents

Define agents using the `BeamMePrompty.Agent` DSL. Each agent consists of named stages, LLM calls, and optional tool definitions. Stages run in dependency order via an internal DAG (Directed Acyclic Graph), ensuring proper execution flow and data dependencies.

```elixir
defmodule BeamMePrompty.TestAgent do
  use BeamMePrompty.Agent

  agent do
    # First stage: Initial processing with LLM
    stage :first_stage do
      llm "test-model", BeamMePrompty.FakeLlmClient do
        with_params do
          temperature 0.5
          top_p 0.9
          frequency_penalty 0.1
          presence_penalty 0.2
          api_key fn -> System.get_env("TEST_API_KEY") end
        end

        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("What is this: <%= text %>")]
      end
    end

    # Second stage: Tool-enabled processing
    stage :second_stage do
      depends_on [:first_stage]  # Waits for first_stage completion

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Call the TestTool to process the data")]

        tools [BeamMePrompty.TestTool]  # Available tools for function calling
      end
    end

    # Third stage: Final processing with previous results
    stage :third_stage do
      depends_on [:second_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [data_part(%{metadata: "additional_context"})]
        message :user, [text_part("Final result: <%= second_stage.response %>")]
      end
    end
  end
end
```

## 📋 Execution Modes

### Synchronous Execution

Run an agent and wait for completion. This is the simplest way to execute an agent when you need immediate results:

```elixir
# Basic synchronous execution
input = %{"text" => "Hello, world!", "user_id" => 123}
{:ok, results} = MyAgent.run_sync(input)
IO.inspect(results)

# With custom options and timeout
opts = %{debug: true, log_level: :info}
handlers = [MyCustomHandler]
timeout_ms = 30_000  # 30 seconds

{:ok, results} = MyAgent.run_sync(input, opts, handlers, timeout_ms)
```

### Asynchronous Execution

For long-running agents or when you need non-blocking execution:

```elixir
# Start agent asynchronously
input = %{"task" => "complex_analysis", "dataset" => large_data}
{:ok, pid} = BeamMePrompty.AgentManager.start_agent(MyAgent, input: input)

# Check status
case BeamMePrompty.Agent.Executor.get_status(pid) do
  :running -> IO.puts("Agent is still processing...")
  :completed -> IO.puts("Agent completed!")
  :failed -> IO.puts("Agent failed!")
end

# Get results when ready
{:ok, :completed, results} = BeamMePrompty.Agent.Executor.get_results(pid)
```

## 🛠️ Defining Tools

Tools extend your agents' capabilities by enabling external operations, API calls, database queries, and more. Implement the `BeamMePrompty.Tool` behaviour for custom functionality:

```elixir
defmodule MyApp.Tools.Calculator do
  @behaviour BeamMePrompty.Tool
  
  @doc """
  A simple calculator tool that performs basic arithmetic operations.
  """
  
  @impl true
  def run(%{"operation" => "add", "a" => a, "b" => b}, _context) when is_number(a) and is_number(b) do
    {:ok, %{"result" => a + b, "operation" => "addition"}}
  end
  
  def run(%{"operation" => "multiply", "a" => a, "b" => b}, _context) when is_number(a) and is_number(b) do
    {:ok, %{"result" => a * b, "operation" => "multiplication"}}
  end
  
  def run(%{"operation" => "divide", "a" => a, "b" => b}, _context) when is_number(a) and is_number(b) and b != 0 do
    {:ok, %{"result" => a / b, "operation" => "division"}}
  end
  
  def run(%{"operation" => "divide", "b" => 0}, _context) do
    {:error, "Division by zero is not allowed"}
  end
  
  def run(params, _context) do
    {:error, "Invalid parameters: #{inspect(params)}"}
  end
end
```

### Registering Tools

Register tools in your agent DSL with optional JSON schema for parameter validation:

```elixir
defmodule MyWeatherAgent do
  use BeamMePrompty.Agent
  
  agent do
    stage :weather_lookup do
      llm "gpt-4", BeamMePrompty.LLM.GoogleGemini do
        message :system, [text_part("You are a weather assistant.")]
        message :user, [text_part("What's the weather in {{city}}?")]
        
        tools [MyApp.Tools.WeatherAPI]
      end
    end
  end
end
```

## 🤖 LLM Integrations

BeamMePrompty provides seamless integration with multiple LLM providers through a unified interface.

### Direct LLM Usage

Use `BeamMePrompty.LLM.completion/5` for direct LLM calls:

```elixir
alias BeamMePrompty.LLM
alias BeamMePrompty.Agent.Dsl.TextPart

# Simple text completion
messages = [user: [%TextPart{text: "Tell me a joke about programming"}]]
{:ok, response} = LLM.completion(
  BeamMePrompty.LLM.GoogleGemini,
  "gemini-pro",
  messages,
  [],  # No tools
  [
    key: "YOUR_API_KEY",
    max_output_tokens: 150,
    temperature: 0.7
  ]
)

IO.puts(response.content)
```

### Custom LLM Clients

Implement the `BeamMePrompty.LLM` behaviour for custom providers:

```elixir
defmodule MyApp.LLM.CustomProvider do
  @behaviour BeamMePrompty.LLM
  
  @impl true
  def completion(model, messages, tools, opts) do
    # Custom implementation
    with {:ok, formatted_messages} <- format_messages(messages),
         {:ok, response} <- call_api(model, formatted_messages, tools, opts),
         {:ok, parsed} <- parse_response(response) do
      {:ok, parsed}
    end
  end
  
  # Implementation details...
end
```

## 📚 Advanced Features

### Message Templates

BeamMePrompty supports dynamic message templating with EEX variable interpolation:

```elixir
# Template variables from input
message :user, [text_part("Hello {{user_name}}, today is {{date}}")]

# Reference results from previous stages
message :user, [text_part("Process this data: {{ previous_stage.result }}")]

# Nested data access
message :user, [text_part("User info: {{ user.profile.name }} ({{user.profile.email}})")]
```

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/beam_me_prompty.git
cd beam_me_prompty

# Install dependencies
mix deps.get

# Run checks
mix check
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.

## Roadmap

[] OpenAI and Hugging Faces Client
[] Streamming Spport
[] Database Persisted Agents
[] A2A Protocol
[] MCP Protocol
[] Real-time Observability

---

**Happy Prompting! 🎉**
