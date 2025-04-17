defmodule BeamMePrompty.Pipeline do
  @moduledoc """
  A DSL for building LLM orchestration pipelines.

  This module provides macros for defining pipelines with multiple stages,
  each configured with specific LLM models, parameters, and prompt templates.

  ## Example

      defmodule PromptFlow do
        use BeamMePrompty.Pipeline

        pipeline "topic_extraction" do
          stage :extraction do
            using model: "gpt-4o-mini-2024-07-18"
            with_params max_tokens: 2000, temperature: 0.05
            # ...
          end
          
          # Additional stages...
        end
      end

  ## Execution

  Pipelines are executed as a Directed Acyclic Graph (DAG), where each stage
  can depend on the results of previous stages. The execution order is determined
  by the dependencies between stages, allowing for parallel execution when possible.

  ```elixir
  # Execute a pipeline with input data
  PromptFlow.execute("topic_extraction", %{text: "Some text to analyze"})
  ```
  """

  @doc """
  When used, defines the necessary macros for the pipeline DSL.
  """
  defmacro __using__(_opts) do
    quote do
      import BeamMePrompty.Pipeline

      alias BeamMePrompty.DAG
      alias BeamMePrompty.DAG.Executor
      alias BeamMePrompty.Validator

      Module.register_attribute(__MODULE__, :pipeline_name, accumulate: false)
      Module.register_attribute(__MODULE__, :pipeline_stages, accumulate: true)
      Module.register_attribute(__MODULE__, :pipeline_input_schema, accumulate: false)

      @before_compile BeamMePrompty.Pipeline

      defdelegate build_dag(stages), to: BeamMePrompty.DAG, as: :build
      defdelegate validate_dag(dag), to: BeamMePrompty.DAG, as: :validate

      defdelegate execute_dag(dag, input, execute_fn, executor),
        to: BeamMePrompty.DAG,
        as: :execute
    end
  end

  @doc """
  Defines a pipeline with the given name and block of stages.

  Only one pipeline is allowed per module, and at least one stage is required.
  """
  defmacro pipeline(name, opts \\ [], do: block) do
    quote do
      if Module.get_attribute(__MODULE__, :pipeline_name) != nil do
        raise "Only one pipeline is allowed per module. Found multiple pipeline definitions."
      end

      @pipeline_name unquote(name)
      @pipeline_input_schema unquote(Macro.escape(Keyword.get(opts, :input_schema)))

      unquote(block)
    end
  end

  @doc """
  Defines an input schema for a pipeline.
  """

  defmacro input_schema(schema) do
    quote do
      @current_stage_config %{input_schema: unquote(Macro.escape(schema))}
    end
  end

  defmacro expect_output(schema) do
    expanded_schema = Macro.expand(schema, __ENV__)

    quote do
      @current_stage_config %{output_schema: unquote(expanded_schema)}
    end
  end

  @doc """
  Defines a stage within a pipeline with a name and configuration block.

  ## Options
    * `:depends_on` - List of stage names this stage depends on
  """
  defmacro stage(name, opts \\ [], do: block) do
    quote do
      Module.register_attribute(__MODULE__, :current_stage_config, accumulate: true)

      unquote(block)

      # Combine all the collected config items into a single map
      config =
        @current_stage_config
        |> Enum.reduce(%{}, fn item, acc ->
          Map.merge(acc, item, fn k, v1, v2 ->
            # Special handling for messages to accumulate them in a list
            if k == :messages do
              v1_messages = List.wrap(v1)
              v2_messages = List.wrap(v2)
              v1_messages ++ v2_messages
            else
              # For other keys, newer value overwrites
              v2
            end
          end)
        end)

      Module.delete_attribute(__MODULE__, :current_stage_config)

      @pipeline_stages %{
        name: unquote(name),
        depends_on: unquote(Keyword.get(opts, :depends_on, [])),
        config: config
      }
    end
  end

  @doc """
  Specifies which LLM model to use for a stage.
  """
  defmacro using(opts) do
    quote bind_quoted: [opts: opts] do
      @current_stage_config %{
        model: opts[:model],
        llm_client: Macro.expand(opts[:llm_client], __ENV__),
        settings: opts[:settings]
      }
    end
  end

  @doc """
  Sets parameters for the LLM call.
  """
  defmacro with_params(opts) do
    quote bind_quoted: [opts: opts] do
      @current_stage_config %{params: opts}
    end
  end

  @doc """
  Defines input from previous stages.

  ## Options
    * `:from` - The name of the stage to get input from
    * `:select` - The key or path to select from the stage's result
  """
  defmacro with_input(opts) do
    from = opts[:from]
    select = opts[:select]

    quote bind_quoted: [from: from, select: select] do
      @current_stage_config %{
        input: %{
          from: from,
          select: select
        }
      }
    end
  end

  @doc """
  Adds a message to the prompt sequence.
  """
  defmacro message(role, content) do
    quote bind_quoted: [role: role, content: content] do
      message = %{role: role, content: content}
      @current_stage_config %{messages: message}
    end
  end

  defmacro call(opts) when is_list(opts) do
    module_ast = Keyword.get(opts, :module)
    expanded_module = Macro.expand(module_ast, __ENV__)

    quote bind_quoted: [module: expanded_module, opts: opts] do
      @current_stage_config %{
        call: %{
          module: module,
          function: opts[:function],
          args: opts[:args] || [],
          as: opts[:as]
        }
      }
    end
  end

  defmacro call(fun) do
    fun_name = :"call_function_#{:erlang.unique_integer([:positive])}"

    quote do
      def unquote(fun_name)(arg1, arg2) do
        unquote(fun).(arg1, arg2)
      end

      @current_stage_config %{
        call: %{
          function: &(__MODULE__.unquote(fun_name) / 2)
        }
      }
    end
  end

  @doc """
  Generates helper functions for accessing the defined pipeline.
  """
  defmacro __before_compile__(env) do
    pipeline_name = Module.get_attribute(env.module, :pipeline_name)
    pipeline_stages = Module.get_attribute(env.module, :pipeline_stages)
    pipeline_input_schema = Module.get_attribute(env.module, :pipeline_input_schema)

    if pipeline_name == nil do
      raise "No pipeline defined. Each module using BeamMePrompty.Pipeline must define exactly one pipeline."
    end

    if pipeline_stages == nil || Enum.empty?(pipeline_stages) do
      raise "Pipeline '#{pipeline_name}' must contain at least one stage."
    end

    quote do
      def pipeline_name do
        unquote(pipeline_name)
      end

      def pipeline do
        %{
          name: unquote(pipeline_name),
          stages: unquote(Macro.escape(pipeline_stages)),
          input_schema: unquote(Macro.escape(pipeline_input_schema))
        }
      end
    end
  end
end
