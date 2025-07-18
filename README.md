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

Note: This library is not production ready yet! Method signatures and functionalities are subject to big changes!

### Installation

Add `beam_me_prompty` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:beam_me_prompty, github: "edlontech/beam_me_prompty", branch: "main"}
  ]
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

---

**Happy Prompting! 🎉**
