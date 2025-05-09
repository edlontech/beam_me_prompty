defmodule BeamMePrompty.Agent.Internals do
  use GenStateMachine, callback_mode: :state_functions

  defstruct [
    :dag,
    :module,
    :retry,
    :global_input,
    :results,
    :nodes_to_execute,
    :initial_state,
    :current_state,
    :started_at,
    :last_transition_at,
    :opts,
    :retry_count,
    :retry_config,
    :retry_node,
    :retry_started_at
  ]

  alias BeamMePrompty.DAG
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.MessageParser

  @impl true
  def init({dag, input, state, opts, module}) do
    data = %__MODULE__{
      dag: dag,
      opts: opts,
      module: module,
      global_input: input,
      initial_state: state,
      current_state: state,
      results: %{},
      retry_count: 0,
      retry_config: %{
        max_retries: Keyword.get(opts, :max_retries),
        backoff_initial: Keyword.get(opts, :backoff_initial),
        backoff_factor: Keyword.get(opts, :backoff_factor),
        max_backoff: Keyword.get(opts, :max_backoff)
      },
      started_at: System.monotonic_time(:millisecond)
    }

    actions = [{:next_event, :internal, :plan}]

    {:ok, :waiting_for_plan, data, actions}
  end

  def waiting_for_plan(:internal, :plan, data) do
    ready_nodes = DAG.find_ready_nodes(data.dag, data.results)

    cond do
      map_size(data.results) == map_size(data.dag.nodes) ->
        data.module.handle_complete(data.results, data.current_state)
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

            node_context =
              Map.merge(data.initial_state, %{
                dependency_results: data.results,
                global_input: data.global_input
              })

            {node_name, node, node_context}
          end)

        {:next_state, :execute_nodes, %__MODULE__{data | nodes_to_execute: nodes_to_execute},
         [{:next_event, :internal, :execute}]}
    end
  end

  def waiting_for_plan(:call, {:get_state, from}, data) do
    {:keep_state, data, [{:reply, from, {:ok, data.current_state}}]}
  end

  def execute_nodes(:internal, :execute, data) do
    results =
      Enum.reduce_while(data.nodes_to_execute, {:ok, data.results || %{}}, fn {node_name, node,
                                                                               context},
                                                                              {:ok, acc_results} ->
        data.module.handle_stage_start(node, data.current_state)

        case execute_stage(node, context) do
          {:ok, result} ->
            data.module.handle_stage_finish(node, result, data.current_state)
            {:cont, {:ok, Map.put(acc_results, node_name, result)}}

          {:error, reason} ->
            {:halt, {:error, {node_name, node, context, reason}}}
        end
      end)

    case results do
      {:ok, updated_results} ->
        updated_data = %__MODULE__{
          data
          | results: updated_results,
            nodes_to_execute: nil
        }

        {:next_state, :waiting_for_plan, updated_data, [{:next_event, :internal, :plan}]}

      err ->
        handle_error(err, data)
    end
  end

  def retrying(:internal, :retry, %{retry: retry_type} = data) do
    data = %__MODULE__{data | retry: nil}

    case retry_type do
      {:only_stage, _reason} ->
        if data.retry_node do
          {node_name, node, context} = data.retry_node

          data.module.handle_stage_start(node, data.current_state)

          case execute_stage(node, context) do
            {:ok, result} ->
              data.module.handle_stage_finish(node, result, data.current_state)
              updated_results = Map.put(data.results, node_name, result)

              updated_data = %__MODULE__{
                data
                | results: updated_results,
                  nodes_to_execute: nil,
                  retry_count: 0,
                  retry_node: nil
              }

              {:next_state, :waiting_for_plan, updated_data, [{:next_event, :internal, :plan}]}

            {:error, reason} ->
              handle_error(
                {:error, {node_name, node, context, reason}},
                %__MODULE__{data | retry_node: {node_name, node, context}}
              )
          end
        else
          {:error,
           Errors.ExecutionError.exception(
             step: :retrying,
             cause: "Missing node information for retry."
           )}
          |> handle_error(%__MODULE__{data | retry_count: 0})
        end

      {:from_start, _reason} ->
        reset_data = %__MODULE__{
          data
          | results: %{},
            nodes_to_execute: nil,
            current_state: data.initial_state,
            retry_count: 0,
            retry_node: nil
        }

        {:next_state, :waiting_for_plan, reset_data, [{:next_event, :internal, :plan}]}
    end
  end

  def retrying(:info, :retry_timeout, data) do
    {:next_state, :retrying, data, [{:next_event, :internal, :retry}]}
  end

  def completed({:call, from}, :get_results, data) do
    GenStateMachine.reply(from, {:ok, :completed, data.results})
    :keep_state_and_data
  end

  defp execute_stage(stage, exec_context) do
    global_input = exec_context[:global_input]
    dependency_results = exec_context[:dependency_results] || %{}
    inputs = Map.merge(global_input, dependency_results)

    with {:ok, llm_result} <- maybe_call_llm(stage.llm, inputs) do
      {:ok, llm_result}
    else
      {:error, reason} -> {:error, Errors.to_class(reason)}
      result when is_map(result) -> {:ok, result}
    end
  end

  defp maybe_call_llm([config | _], input) do
    if config.model && config.llm_client do
      messages = MessageParser.parse(config.messages, input) || []
      [params | _] = config.params

      case BeamMePrompty.LLM.completion(config.llm_client, config.model, messages, params) do
        {:ok, result} ->
          {:ok, result}

        {:error, err} ->
          {:error, err}
      end
    else
      {:ok, %{}}
    end
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

  defp handle_error({:error, {node_name, node, context, error}}, data) do
    data = %__MODULE__{data | retry_node: {node_name, node, context}}
    handle_error({:error, error}, data)
  end

  defp handle_error({:error, error}, data) do
    error
    |> Errors.to_class()
    |> data.module.handle_error(data.current_state)
    |> handle_error_callback(data)
  end

  defp handle_error_callback({:retry, reason, state}, data) do
    if data.retry_count >= data.retry_config.max_retries do
      {:stop,
       {:error,
        Errors.ExecutionError.exception(
          step: :retry,
          cause: "Maximum retry attempts (#{data.retry_config.max_retries}) exceeded."
        )}, data}
    else
      retry_count = data.retry_count + 1
      backoff_ms = calculate_backoff(retry_count, data.retry_config)

      updated_data = %__MODULE__{
        data
        | current_state: state.current_state,
          retry: {:only_stage, reason},
          retry_count: retry_count,
          retry_started_at: System.monotonic_time(:millisecond)
      }

      {:next_state, :retrying, updated_data, [{:state_timeout, backoff_ms, :retry_timeout}]}
    end
  end

  defp handle_error_callback({:restart, reason}, data) do
    if data.retry_count >= data.retry_config.max_retries do
      {:stop,
       {:error,
        Errors.ExecutionError.exception(
          step: :retry,
          cause: "Maximum retry attempts (#{data.retry_config.max_retries}) exceeded."
        )}, data}
    else
      retry_count = data.retry_count + 1
      backoff_ms = calculate_backoff(retry_count, data.retry_config)

      updated_data = %__MODULE__{
        data
        | current_state: data.initial_state,
          retry: {:from_start, reason},
          retry_count: retry_count,
          retry_started_at: System.monotonic_time(:millisecond)
      }

      {:next_state, :retrying, updated_data, [{:state_timeout, backoff_ms, :retry_timeout}]}
    end
  end

  defp handle_error_callback({:stop, reason}, data) do
    {:stop, reason, data}
  end

  defp calculate_backoff(retry_count, config) do
    backoff = config.backoff_initial * :math.pow(config.backoff_factor, retry_count - 1)

    # Add some jitter (±10%) to prevent thundering herd problem
    # -10% to +10%
    jitter = :rand.uniform(20) - 10
    backoff_with_jitter = backoff * (1 + jitter / 100)

    trunc(min(backoff_with_jitter, config.max_backoff))
  end
end
