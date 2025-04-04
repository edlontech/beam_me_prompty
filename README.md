# BeamMePrompty

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `beam_me_prompty` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:beam_me_prompty, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/beam_me_prompty>.

# BeamMePrompty

An Elixir DSL for building LLM orchestration pipelines.

## Features

- Define multi-stage LLM pipelines with a clean, declarative syntax
- Configure different models for different stages
- Pass data between pipeline stages
- Define expected output schemas
- Template-based prompt construction

## Example

```elixir
defmodule PromptFlow do
  use BeamMePrompty.Pipeline

  pipeline "topic_extraction" do
    stage :extraction do
      using model: "gpt-4o-mini-2024-07-18"
      with_params max_tokens: 2000, temperature: 0.05
      
      with_context do
        workspace_context: @workspace_context,
        transcript: @transcript
      end
      
      message :system, "You are a helpful assistant."
      message :user, "Extract topics from this transcript."
      
      expect_output schema: %{
        type: :object,
        properties: %{
          topics: %{
            type: :array,
            items: %{type: :string}
          }
        }
      }
    end
  end
end
```

## Installation

Add `beam_me_prompty` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:beam_me_prompty, "~> 0.1.0"}
  ]
end
```

## Documentation

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc).
