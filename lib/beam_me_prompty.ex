defmodule BeamMePrompty do
  @doc """
  Executes a pipeline with the given input.

  Options:
    - :executor - The DAG executor to use (defaults to BeamMePrompty.DAG.Executor.InMemory)

  Returns {:ok, results} or {:error, reason}
  """
  def execute(pipeline, input, opts \\ []) do
    executor = Keyword.get(opts, :executor, BeamMePrompty.DAG.Executor.InMemory)
    # Extract llm_client from opts
    llm_client = Keyword.get(opts, :llm_client)
    dag = BeamMePrompty.DAG.build(pipeline.stages)

    # Create initial execution context
    initial_context = %{
      global_input: input,
      llm_client: llm_client
      # Add other execution-wide options here if needed
    }

    BeamMePrompty.DAG.execute(dag, initial_context, &execute_stage(&1, &2), executor)
  end

  # execute_stage now receives the full execution context
  defp execute_stage(stage, exec_context) do
    config = stage.config |> dbg()
    global_input = exec_context.global_input
    dependency_results = exec_context.dependency_results || %{}
    llm_client = exec_context.llm_client

    with {:ok, prepared_input} <-
           prepare_stage_input(config, global_input, dependency_results) |> dbg(),
         {:ok, validated_input} <- validate_input(config, prepared_input),
         {:ok, llm_result} <- maybe_call_llm(config, validated_input, llm_client),
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
    base_input = global_input

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

                # Decide how to merge: If selected_data is a map, merge it. Otherwise, maybe put it under a key?
                # Let's assume for now it replaces the base_input if select is used.
                # A more robust strategy might be needed.
                if is_map(selected_data) do
                  {:ok, Map.merge(base_input, selected_data)}
                else
                  # If selected data is not a map, put it under a default key or require an :as option?
                  # For now, let's put it under :selected_input key.
                  {:ok, Map.put(base_input, :selected_input, selected_data)}
                end
            end

          _ ->
            {:error, "Invalid :input configuration in stage config."}
        end
      else
        # No specific input source, use global input directly
        {:ok, base_input}
      end

    # Ensure the result is always {:ok, map} or {:error, reason}
    case merged_input do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, _} = error -> error
      _ -> {:error, "Internal error: Input preparation resulted in unexpected format."}
    end
  end

  defp validate_input(config, input) do
    case Map.get(config, :input_schema) |> dbg() do
      nil -> {:ok, input}
      schema -> BeamMePrompty.Validator.validate(schema, input)
    end
  end

  # Add llm_client parameter
  defp maybe_call_llm(config, _input, llm_client) do
    # Use the passed llm_client instead of config.llm_client
    if config.model && llm_client do
      # TODO: Implement templating for message content using input data
      messages = config.messages || []
      params = config.params || []

      case BeamMePrompty.LLM.completion(llm_client, messages, params) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, %{type: :llm_error, details: reason}}
      end
    else
      # No LLM call needed for this stage, return input as is for potential 'call' step
      # Return empty map if no LLM call, adjust if input should pass through
      {:ok, %{}}
    end
  end

  defp validate_output(config, llm_result) do
    schema = Map.get(config, :output_schema)

    case schema do
      nil ->
        {:ok, llm_result}

      schema when is_map(schema) and is_map(llm_result) ->
        # Filter the result map to only include keys defined in the schema
        schema_keys = Map.keys(schema)
        filtered_result = Map.take(llm_result, schema_keys)

        # Validate the filtered data
        case BeamMePrompty.Validator.validate(schema, filtered_result) do
          {:ok, _validated_data} -> {:ok, llm_result}
          {:error, _reason} = error -> error
        end

      # If we still have AST, convert it (this should be rare now)
      {:%{}, _meta, pairs} when is_list(pairs) ->
        actual_schema = Map.new(pairs)
        validate_output(%{config | output_schema: actual_schema}, llm_result)

      _ ->
        BeamMePrompty.Validator.validate(schema, llm_result)
    end
  end

  defp maybe_call_function(config, stage_input, llm_result) do
    case Map.get(config, :call) do
      nil ->
        # No function call, return the LLM result (or empty map if no LLM)
        {:ok, llm_result}

      %{function: fun, as: result_key} when is_function(fun) ->
        try do
          # Pass both stage input and llm result to the function
          call_result = fun.(stage_input, llm_result)
          # Merge the function result into the llm_result map under the specified key
          {:ok, Map.put(llm_result, result_key, call_result)}
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
        full_args = [stage_input, llm_result | args]

        try do
          # Prepend stage_input and llm_result to the static args
          call_result = apply(mod, fun_name, full_args)
          # Merge the function result into the llm_result map under the specified key
          {:ok, Map.put(llm_result, result_key, call_result)}
        rescue
          e ->
            {:error,
             %{
               type: :call_error,
               mfa: {mod, fun_name, length(full_args)},
               details: Exception.format(:error, e, __STACKTRACE__)
             }}
        end

      _ ->
        {:error, %{type: :invalid_config, details: "Invalid :call configuration"}}
    end
  end
end
