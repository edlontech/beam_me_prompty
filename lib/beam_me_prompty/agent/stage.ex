defmodule BeamMePrompty.Agent.Stage do
  use GenStateMachine, callback_mode: :state_functions

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.MessageParser

  defstruct [
    :stage_name,
    :messages,
    :tool_responses
  ]

  def start_link(stage_name) do
    GenStateMachine.start_link(__MODULE__, stage_name, [])
  end

  @impl true
  def init(stage_name) do
    actual_stage_name =
      case stage_name do
        {s_name} when is_atom(s_name) or is_binary(s_name) -> s_name
        s_name -> s_name
      end

    {:ok, :idle, %__MODULE__{stage_name: actual_stage_name}}
  end

  def idle(:cast, {:execute, node_name, node_def, node_ctx, caller_pid}, data) do
    case do_execute_stage(node_def, node_ctx) do
      {:ok, result} ->
        send(caller_pid, {:stage_response, node_name, {:ok, result}})

      {:error, reason} ->
        send(caller_pid, {:stage_response, node_name, {:error, reason}})
    end

    # Stay in idle state, ready for next command
    {:next_state, :idle, data}
  end

  def idle(_event_type, _event_content, data) do
    {:keep_state, data}
  end

  @impl true
  def terminate(_reason, _state, _data) do
    :ok
  end

  # --- Private Helper Functions for Stage Execution ---

  defp do_execute_stage(stage_node, exec_context) do
    global_input = exec_context[:global_input] || %{}
    dependency_results = exec_context[:dependency_results] || %{}
    inputs = Map.merge(global_input, dependency_results)

    with {:ok, llm_result} <- maybe_call_llm(stage_node.llm, inputs) do
      {:ok, llm_result}
    else
      {:error, reason} -> {:error, Errors.to_class(reason)}
    end
  end

  defp maybe_call_llm([config | _rest_configs], input) when is_map(config) do
    if config.model && config.llm_client do
      messages = MessageParser.parse(config.messages, input) || []
      [params | _] = config.params

      BeamMePrompty.LLM.completion(
        config.llm_client,
        config.model,
        messages,
        config.tools,
        params
      )
    else
      {:ok, %{}}
    end
  end

  defp maybe_call_llm([], _input) do
    {:ok, %{}}
  end

  defp maybe_call_llm(_, _input) do
    {:ok, %{}}
  end
end
