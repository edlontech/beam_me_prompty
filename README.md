<p align="center">
  <img width="300" height="300" src="https://iili.io/31BBn9I.th.png">
</p>

# BeamMePrompty

**BeamMePrompty** is an Elixir library for building and executing multi-stage agents against Large Language Models (LLMs). It provides a DSL to define agent stages, manage dependencies, validate inputs/outputs, and plug in custom LLM clients.

## Installation

Add `:beam_me_prompty` to your `mix.exs` dependencies:

```elixir
defp deps do
  [
    {:beam_me_prompty, "~> 0.1.0"}
  ]
end
```

Fetch and compile:

```bash
mix deps.get
mix compile
```

## Quick Start

Define a Agent module:

```elixir
defmodule BeamMePrompty.TestAgent do
  use BeamMePrompty.Agent

  agent do
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
        message :user, [text_part("Wat dis {{text}}")]
      end
    end

    stage :second_stage do
      depends_on [:first_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [text_part("Call the TestTool")]

        tool :test_tool do
          description "Test tool description"
          module BeamMePrompty.TestTool

          parameters %{
            type: :object,
            properties: %{
              val1: %{
                type: :string,
                description: "First value"
              },
              val2: %{
                type: :string,
                description: "Second value"
              }
            }
          }
        end
      end
    end

    stage :third_stage do
      depends_on [:second_stage]

      llm "test-model", BeamMePrompty.FakeLlmClient do
        message :system, [text_part("You are a helpful assistant.")]
        message :user, [data_part(%{this: "that"})]
        message :user, [text_part("Result: {{ second_stage }}")]
      end
    end
  end
end
```

Supervise the agent

```elixir
BeamMePrompty.AgentManager.start_agent(BeamMePrompty.TestAgent)
```

## Contributing

Contributions and suggestions are welcome! Please open issues or submit pull requests.
