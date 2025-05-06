defmodule BeamMePrompty.Agents.InternalState do
  defstruct [
    :dag,
    :module,
    :results,
    :retry,
    :restart,
    :nodes_to_execute,
    :initial_state,
    :inner_state,
    :started_at,
    :last_transition_at,
    :response_queue,
    :opts
  ]

  @behaviour :gen_statem

  alias BeamMePrompty.DAG
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.MessageParser

  @impl true
  def callback_mode do
    :state_functions
  end

  @impl true
  def init({dag, state, opts, module}) do
    data = %__MODULE__{
      dag: dag,
      opts: opts,
      module: module,
      initial_state: state,
      inner_state: state,
      response_queue: []
    }

    actions = [{:next_event, :internal, :plan}]
    {:ok, :waiting_for_plan, data, actions}
  end

  def waiting_for_plan(:internal, :plan, data) do
    ready_nodes = DAG.find_ready_nodes(data.dag, data.inner_state)

    cond do
      map_size(data.inner_state.results) == map_size(data.dag.nodes) ->
        {:next_state, :completed, data}

      Enum.empty?(ready_nodes) ->
        {:error,
         Errors.ExecutionError.exception(
           step: :waiting_for_plan,
           cause: "No nodes are ready to execute"
         )}
        |> handle_error(data)

      true ->
        nodes_to_execute =
          Enum.map(ready_nodes, fn node_name ->
            node = Map.get(data.dag.nodes, node_name)
            node_context = Map.merge(data.initial_state, %{dependency_results: data.results})
            {node_name, node, node_context}
          end)

        {:next_state, :execute_nodes, %__MODULE__{data | nodes_to_execute: nodes_to_execute},
         [{:next_event, :internal, :execute}]}
    end
  end

  def execute_nodes(:internal, :execute, data) do
    results =
      Enum.reduce_while(data.nodes_to_execute, {:ok, data.results || %{}}, fn {node_name, node,
                                                                               context},
                                                                              {:ok, acc_results} ->
        data.module.handle_stage_start(node, data.inner_state)

        case execute_stage(node, context) do
          {:ok, result} ->
            data.module.handle_stage_finish(node, result, data.inner_state)
            {:cont, {:ok, Map.put(acc_results, node_name, result)}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:ok, updated_results} ->
        updated_data = %__MODULE__{
          data
          | results: updated_results,
            inner_state: %{data.inner_state | results: updated_results},
            nodes_to_execute: nil
        }

        {:next_state, :waiting_for_plan, updated_data, [{:next_event, :internal, :plan}]}

      err ->
        handle_error(err, data)
    end
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
      {:error, reason} -> {:error, Errors.to_class(reason)}
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
                {:error,
                 Errors.ExecutionError.exception(
                   step: :prepare_stage_input,
                   cause: "Dependency result for stage '#{from_stage}' not found."
                 )}

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
            {:error,
             Errors.ExecutionError.exception(
               step: :prepare_stage_input,
               cause: "Invalid input source configuration."
             )}
        end
      else
        {:ok, global_input}
      end

    case merged_input do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:error, _} = error ->
        error

      _ ->
        {:error,
         Errors.ExecutionError.exception(
           step: :prepare_stage_input,
           cause: "Invalid input data format."
         )}
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
        {:ok, result} ->
          {:ok, result}

        {:error, err} ->
          {:error, err}
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
        case BeamMePrompty.Validator.validate(schema, llm_result) do
          {:ok, validated_data} -> {:ok, validated_data}
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
          {:ok, call_result}
        rescue
          e ->
            {:error,
             Errors.ExecutionError.exception(
               step: :call_function,
               cause: "Failed to call anonymous function #{Exception.message(e)}",
               stacktrace: __STACKTRACE__
             )}
        end

      %{module: mod, function: fun_name, args: args, as: result_key} ->
        try do
          selected_value = stage_input[:selected_input]
          call_result = apply(mod, fun_name, [selected_value | args])

          if result_key do
            {:ok, Map.put(%{}, result_key, call_result)}
          else
            {:ok, call_result}
          end
        rescue
          e ->
            {:error,
             Errors.ExecutionError.exception(
               step: :call_function,
               cause:
                 "Failed to call function #{mod}.#{fun_name}/#{length(args) + 1}: #{Exception.message(e)}",
               stacktrace: __STACKTRACE__
             )}
        end

      _ ->
        {:error,
         Errors.ExecutionError.exception(
           step: :call_function,
           cause: "Invalid function call configuration."
         )}
    end
  end

  defp handle_error({:error, error}, data) do
    error
    |> Errors.to_class()
    |> data.module.handle_error(data.inner_state)
    |> handle_error_callback(data)
  end

  defp handle_error_callback({:retry, reason, state}, data) do
    %__MODULE__{data | inner_state: state.inner_state, retry: reason}
  end

  defp handle_error_callback({:restart, reason}, data) do
    %__MODULE__{data | inner_state: data.initial_state, restart: reason}
  end

  defp handle_error_callback({:stop, reason}, data) do
    {:stop, reason, data}
  end
end
