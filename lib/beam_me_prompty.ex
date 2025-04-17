defmodule BeamMePrompty do
  @moduledoc """
  Main entrypoint for executing defined BeamMePrompty pipelines.
  Provides the `execute/3` function to orchestrate multi-stage LLM prompts,
  handling input/output validation, dependency resolution, and customizable
  LLM clients and executors.
  """
  alias BeamMePrompty.LLM.MessageParser

  def execute(pipeline, input, opts \\ []) do
    executor = Keyword.get(opts, :executor, BeamMePrompty.DAG.Executor.InMemory)
    override_llm = Keyword.get(opts, :llm_client)
    dag = BeamMePrompty.DAG.build(pipeline.stages)

    initial_context = %{
      global_input: input,
      llm_client: override_llm
    }

    BeamMePrompty.DAG.execute(dag, initial_context, &execute_stage(&1, &2), executor)
  end

  defp execute_stage(stage, exec_context) do
    config = stage.config

    config =
      Map.replace_lazy(config, :llm_client, fn client ->
        case exec_context.llm_client do
          nil -> client
          exec_client -> exec_client
        end
      end)

    global_input = exec_context.global_input
    dependency_results = exec_context.dependency_results || %{}

    with {:ok, prepared_input} <-
           prepare_stage_input(config, global_input, dependency_results),
         {:ok, validated_input} <- validate_input(config, prepared_input),
         {:ok, llm_result} <- maybe_call_llm(config, validated_input),
         {:ok, validated_llm_result} <- validate_output(config, llm_result),
         {:ok, final_result} <-
           maybe_call_function(config, validated_input, validated_llm_result) do
      {:ok, final_result}
    else
      {:error, reason} -> {:error, %{stage: stage.name, reason: reason}}
      result when is_map(result) -> {:ok, result}
    end
  end

  defp prepare_stage_input(config, global_input, dependency_results) do
    input_source = Map.get(config, :input)

    merged_input =
      if input_source do
        case input_source do
          %{from: from_stage, select: select_path} when not is_nil(from_stage) ->
            case Map.get(dependency_results, from_stage) do
              nil ->
                {:error, "Dependency result for stage '#{from_stage}' not found."}

              from_result ->
                selected_data =
                  if select_path do
                    get_in(from_result, List.wrap(select_path))
                  else
                    from_result
                  end

                if is_map(selected_data) do
                  {:ok, Map.merge(global_input, selected_data)}
                else
                  {:ok, Map.put(global_input, "selected_input", selected_data)}
                end
            end

          _ ->
            {:error, "Invalid :input configuration in stage config."}
        end
      else
        {:ok, global_input}
      end

    case merged_input do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, _} = error -> error
      _ -> {:error, "Internal error: Input preparation resulted in unexpected format."}
    end
  end

  defp validate_input(config, input) do
    case Map.get(config, :input_schema) do
      nil -> {:ok, input}
      schema -> BeamMePrompty.Validator.validate(schema, input)
    end
  end

  defp maybe_call_llm(config, input) do
    if config.model && config.llm_client do
      messages = MessageParser.parse(config.messages, input) || []
      params = parse_params(config.params) || []

      case BeamMePrompty.LLM.completion(config.llm_client, messages, params) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, %{type: :llm_error, details: reason}}
      end
    else
      {:ok, %{}}
    end
  end

  defp parse_params(params) do
    Keyword.new(params, fn
      {key, {:env, value}} ->
        {key, System.get_env(value)}

      {key, value} ->
        {key, value}
    end)
  end

  defp validate_output(config, llm_result) do
    case Map.get(config, :output_schema) do
      nil ->
        {:ok, llm_result}

      schema when is_map(schema) and is_map(llm_result) ->
        schema_keys = Map.keys(schema)
        filtered_result = Map.take(llm_result, schema_keys)

        case BeamMePrompty.Validator.validate(schema, filtered_result) do
          {:ok, _validated_data} -> {:ok, llm_result}
          {:error, _reason} = error -> error
        end
    end
  end

  defp maybe_call_function(config, stage_input, llm_result) do
    case Map.get(config, :call) do
      nil ->
        {:ok, llm_result}

      %{function: fun} when is_function(fun) ->
        try do
          call_result = fun.(stage_input, llm_result)
          {:ok, Map.put(llm_result, :tool_result, call_result)}
        rescue
          e ->
            {:error,
             %{
               type: :call_error,
               function: "<anonymous>",
               details: Exception.format(:error, e, __STACKTRACE__)
             }}
        end

      %{module: mod, function: fun_name, args: args, as: result_key} ->
        try do
          selected_value = stage_input[:selected_input]
          call_result = apply(mod, fun_name, [selected_value | args])
          {:ok, Map.put(llm_result, result_key, call_result)}
        rescue
          e ->
            {:error,
             %{
               type: :call_error,
               mfa: {mod, fun_name, length(args) + 1},
               details: Exception.format(:error, e, __STACKTRACE__)
             }}
        end

      _ ->
        {:error, %{type: :invalid_config, details: "Invalid :call configuration"}}
    end
  end
end
