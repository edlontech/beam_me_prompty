defmodule BeamMePrompty do
  @moduledoc """
  BeamMePrompty is a library for building and running prompt-driven agents with:

    * Multi-stage orchestration via a simple DSL
    * Integration with Large Language Models (LLMs)
    * External tool invocation and function calling
    * Customizable execution via handler callbacks
    * Support for both synchronous and asynchronous execution

  ## Defining Agents

  Define agents using the `BeamMePrompty.Agent` DSL. Each agent consists of named stages,
  LLM calls, and optional tool definitions. Stages run in dependency order via an internal DAG.

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

            tools [BeamMePrompty.TestTool]
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

  ## Synchronous Execution

  Run an agent and wait for completion:

      input = %{"prompt" => "Calculate 1+2"}
      {:ok, results} = MyAgent.run_sync(input)
      IO.inspect(results)

  Use a custom timeout (in ms) as the fourth argument to `run_sync/4`:

      {:ok, results} = MyAgent.run_sync(input, %{}, [], 30_000)

  ## Asynchronous Execution

      {:ok, pid} = BeamMePrompty.AgentManager.start_agent(MyAgent, input: input)
      {:ok, :completed, results} = BeamMePrompty.Agent.Executor.get_results(pid)

  ## Handler Callbacks

  Override callbacks to customize lifecycle events in your agent:

      @impl true
      def handle_plan(ready_stages, state) do
        IO.inspect(ready_stages, label: "Ready to run")
        {:ok, ready_stages, state}
      end

      @impl true
      def handle_stage_finish(stage, result, state) do
        IO.puts("Stage \#{stage.name} finished with result: \#{inspect(result)}")
        :ok
      end

  Available callbacks include:
    * handle_init/2
    * handle_error/2
    * handle_plan/2
    * handle_batch_start/2
    * handle_stage_start/2
    * handle_stage_finish/3
    * handle_batch_complete/3
    * handle_tool_call/3
    * handle_tool_result/3
    * handle_progress/2
    * handle_complete/2
    * handle_cleanup/2
    * handle_timeout/2
    * handle_pause/2
    * handle_resume/1

  ## Defining Tools

  Implement the `BeamMePrompty.Tool` behaviour for external operations:

      defmodule MyApp.Tools.Calculator do
        @behaviour BeamMePrompty.Tool

        @impl true
        def run(%{"operation" => "add", "a" => a, "b" => b}) do
          {:ok, %{"result" => a + b}}
        end

        def run(_), do: {:error, :invalid_args}
      end

  Register tools in your agent DSL with a JSON schema for parameters.

  ## LLM Integrations

  Use `BeamMePrompty.LLM.completion/5` to call LLM providers:

      alias BeamMePrompty.LLM
      alias BeamMePrompty.Agent.Dsl.TextPart

      messages = [user: [%TextPart{text: "Tell me a joke"}]]
      {:ok, response} =
        LLM.completion(
          BeamMePrompty.LLM.GoogleGemini,
          "gemini-pro",
          messages,
          [],
          [key: "YOUR_API_KEY", max_output_tokens: 150]
        )

  Built-in LLM clients:
    * BeamMePrompty.LLM.GoogleGemini
    * BeamMePrompty.LLM.Anthropic

  Define custom LLM clients by implementing the `BeamMePrompty.LLM` behaviour.
  """

  use Application

  def start(_type, _args) do
    children = [
      {Registry, [keys: :unique, name: :agents]},
      BeamMePrompty.AgentManager
    ]

    opts = [strategy: :one_for_one, name: BeamMePrompty.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
