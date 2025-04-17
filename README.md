![31BBn9I.th.png](https://iili.io/31BBn9I.th.png)

# BeamMePrompty

**BeamMePrompty** is an Elixir library for building and executing multi-stage pipelines of prompts against Large Language Models (LLMs). It provides a DSL to define pipeline stages, manage dependencies, validate inputs/outputs, and plug in custom LLM clients.

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

Define a pipeline module:

```elixir
defmodule MyPipeline do
  use BeamMePrompty.Pipeline

  pipeline "example_pipeline" do
    # Optional: schema for the entire pipeline input
    input_schema %{"text" => :string}

    stage :extract_keywords do
      using model: "gpt-4", llm_client: MyLlmClient
      with_params max_tokens: 100, temperature: 0.2

      message :system, "You are a helpful assistant."
      message :user, "Extract keywords from: {{input.text}}"

      expect_output %{"keywords" => [:string]}
    end

    stage :summarize, depends_on: [:extract_keywords] do
      using model: "gpt-4", llm_client: MyLlmClient
      with_params max_tokens: 200

      with_input from: :extract_keywords, select: "keywords"

      message :system, "You are a helpful assistant."
      message :user, "Summarize these keywords: {{input.selected_input}}"

      expect_output %{"summary" => :string}
    end
  end
end
```

Execute the pipeline:

```elixir
pipeline = MyPipeline.pipeline()
input = %{"text" => "Elixir is a dynamic, functional language."}

{:ok, results} = BeamMePrompty.execute(pipeline, input)
IO.inspect(results)
# %{extract_keywords: %{"keywords" => [...]}, summarize: %{"summary" => "..."}}
```

### Overriding the LLM client or executor

```elixir
{:ok, results} =
  BeamMePrompty.execute(
    pipeline,
    input,
    llm_client: FakeLlmClient,
    executor: CustomExecutor
  )
```

## Pipeline Example

Below is a full example inspired by the test suite:

```elixir
defmodule BeamMePrompty.TestPipeline do
  use BeamMePrompty.Pipeline

  pipeline "simple_test" do
    stage :first_stage do
      using model: "test-model", llm_client: BeamMePrompty.FakeLlmClient
      with_params max_tokens: 100, temperature: 0.5, key: {:env, "TEST_KEY"}

      message :system, "You are a helpful assistant."
      message :user, "Process this input: {{input.text}}"

      expect_output %{"result" => :string}
    end

    stage :second_stage, depends_on: [:first_stage] do
      using model: "test-model", llm_client: BeamMePrompty.FakeLlmClient
      with_input from: :first_stage, select: "result"
      with_params max_tokens: 100, temperature: 0.5

      message :system, "You are a helpful assistant."
      message :user, "Analyze this further: {{input.selected_input}}"

      expect_output %{"analysis" => :string}
    end

    stage :third_stage, depends_on: [:first_stage, :second_stage] do
      using model: "test-model", llm_client: BeamMePrompty.FakeLlmClient
      with_input from: :second_stage, select: "analysis"
      with_params max_tokens: 100, temperature: 0.5

      message :system, "You are a helpful assistant."
      message :user, "Boink Boink"

      call fn _stage_input, llm_output ->
        {:ok, "Echoing: #{inspect(llm_output)}"}
      end

      expect_output %{"final_result" => :string}
    end
  end
end

# Execute:
pipeline = BeamMePrompty.TestPipeline.pipeline()
input = %{"text" => "what's this animal?"}
{:ok, results} = BeamMePrompty.execute(pipeline, input)
IO.inspect(results)
```

## Contributing

Contributions and suggestions are welcome! Please open issues or submit pull requests.
