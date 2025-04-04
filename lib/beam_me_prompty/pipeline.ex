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

      # Process the block to extract stages
      unquote(block)

      # This will be checked in __before_compile__ to ensure at least one stage is defined
    end
  end

  @doc """
  Defines an input schema for a pipeline.
  """
  defmacro input_schema(schema) do
    quote do
      %{input_schema: unquote(Macro.escape(schema))}
    end
  end

  @doc """
  Defines a stage within a pipeline with a name and configuration block.

  ## Options
    * `:depends_on` - List of stage names this stage depends on
  """
  defmacro stage(name, opts \\ [], do: block) do
    quote do
      stage_def = %{
        name: unquote(name),
        depends_on: unquote(Macro.escape(Keyword.get(opts, :depends_on, []))),
        config: unquote(Macro.escape(extract_stage_config(block)))
      }

      @pipeline_stages stage_def
    end
  end

  @doc """
  Specifies which LLM model to use for a stage.
  """
  defmacro using(opts) do
    quote do
      %{model: unquote(opts[:model]), llm_client: unquote(opts[:llm_client])}
    end
  end

  @doc """
  Sets parameters for the LLM call.
  """
  defmacro with_params(opts) do
    quote do
      %{params: unquote(opts)}
    end
  end

  @doc """
  Defines the input schema for a stage, similar to Ecto schemas.
  The actual values will be injected at runtime.
  """
  defmacro inputs(schema) do
    quote do
      %{input_schema: unquote(Macro.escape(schema))}
    end
  end

  @doc """
  Defines input from previous stages.

  ## Options
    * `:from` - The name of the stage to get input from
    * `:select` - The key or path to select from the stage's result
  """
  defmacro with_input(opts) do
    quote do
      %{
        input: %{
          from: unquote(opts[:from]),
          select: unquote(opts[:select])
        }
      }
    end
  end

  @doc """
  Adds a message to the prompt sequence.
  """
  defmacro message(role, content) do
    quote do
      %{
        message: %{
          role: unquote(role),
          content: unquote(content)
        }
      }
    end
  end

  @doc """
  Defines the expected output schema.
  """
  defmacro expect_output(schema) do
    quote do
      %{output_schema: unquote(schema)}
    end
  end

  defmacro call(fun, opts) when is_function(fun) do
    quote do
      %{
        call: %{
          function: unquote(Macro.escape(fun)),
          as: unquote(opts[:as])
        }
      }
    end
  end

  defmacro call(opts) do
    quote do
      %{
        call: %{
          module: unquote(opts[:module]),
          function: unquote(opts[:function]),
          args: unquote(opts[:args] || []),
          as: unquote(opts[:as])
        }
      }
    end
  end

  @doc """
  Helper function to extract and merge stage configurations from the AST block
  generated by the stage's `do` block.
  """
  def extract_stage_config({:__block__, _, expressions}) do
    # Convert AST expressions to configuration maps
    config_maps = Enum.map(expressions, &eval_stage_config_expr/1)

    # Merge the configuration maps
    Enum.reduce(config_maps, %{messages: []}, fn config_map, acc_config ->
      if message = Map.get(config_map, :message) do
        messages = acc_config.messages ++ [message]

        Map.merge(acc_config, Map.delete(config_map, :message))
        |> Map.put(:messages, messages)
      else
        Map.merge(acc_config, config_map)
      end
    end)
  end

  # Handle single expression blocks (not wrapped in a block)
  def extract_stage_config(expr) do
    config_map = eval_stage_config_expr(expr)

    if message = Map.get(config_map, :message) do
      %{messages: [message]}
    else
      config_map
    end
  end

  # Evaluate a stage configuration expression from the AST
  defp eval_stage_config_expr({name, _, args}) do
    case {name, args} do
      {:using, [opts]} ->
        %{model: Keyword.get(opts, :model), llm_client: Keyword.get(opts, :llm_client)}

      {:with_params, [opts]} ->
        %{params: opts}

      {:inputs, [schema]} ->
        %{input_schema: schema}

      {:with_input, [opts]} ->
        %{input: %{from: Keyword.get(opts, :from), select: Keyword.get(opts, :select)}}

      {:message, [role, content]} ->
        %{message: %{role: role, content: content}}

      {:expect_output, [schema]} ->
        %{output_schema: schema}

      {:call, [fun, opts]} when is_function(fun) ->
        %{call: %{function: fun, as: Keyword.get(opts, :as)}}

      {:call, [opts]} ->
        %{
          call: %{
            module: Keyword.get(opts, :module),
            function: Keyword.get(opts, :function),
            args: Keyword.get(opts, :args, []),
            as: Keyword.get(opts, :as)
          }
        }

      _ ->
        %{}
    end
  end

  # Handle any other expressions
  defp eval_stage_config_expr(_), do: %{}

  # Helper function to evaluate schema AST into actual maps
  defp eval_schema({:%{}, _, pairs}) when is_list(pairs) do
    # Convert AST map representation to actual map
    Map.new(pairs)
  end

  defp eval_schema({:{}, _, [{:%{}, _, pairs}]}) when is_list(pairs) do
    # Handle nested AST representation
    Map.new(pairs)
  end

  defp eval_schema(schema) when is_map(schema) do
    # Already a map, return as is
    schema
  end

  defp eval_schema(other) do
    # For any other form, return as is and let validation handle it
    other
  end

  @doc """
  Helper function to extract stages from the pipeline block.
  This is no longer used with the new implementation, but kept for compatibility.
  """
  def extract_stages(block) do
    # For testing purposes, we need to handle both actual stage definitions
    # and raw AST blocks
    case block do
      %{name: _name, config: _config} = stage ->
        # If it's already a properly formatted stage, return it directly
        stage

      _ ->
        # Otherwise, return the raw block for further processing
        %{raw_stages: block}
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
