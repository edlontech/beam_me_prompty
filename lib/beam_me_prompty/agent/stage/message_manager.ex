defmodule BeamMePrompty.Agent.Stage.MessageManager do
  @moduledoc """
  Handles message formatting, response normalization, and message history management.

  This module centralizes all message-related operations including:
  - Formatting LLM responses into proper message structures
  - Creating tool result and error messages
  - Normalizing responses for validation
  - Managing message history
  """
  @moduledoc section: :agent_stage_and_execution

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.Part
  alias BeamMePrompty.LLM.Errors.ToolError
  alias BeamMePrompty.LLM.MessageParser

  @doc """
  Wraps a response in an assistant message format.
  """
  @spec format_response(Part.parts()) :: {:assistant, [Part.parts()]}
  def format_response(response), do: {:assistant, List.wrap(response)}

  @doc """
  Fetches the DataPart from the response.
  """
  @spec fetch_data_part_from_response([Part.parts()]) :: DataPart.t() | nil
  def fetch_data_part_from_response(response), do: Enum.find(response, &is_struct(&1, DataPart))

  @doc """
  Creates a tool result message for successful tool execution.
  """
  def format_tool_result_message({:ok, result_content}, tool_call_id, tool_name_str),
    do: [format_tool_result_as_message(tool_call_id, tool_name_str, result_content)]

  def format_tool_result_message({:error, error_reason}, tool_call_id, tool_name_str),
    do: [format_tool_error_as_message(tool_call_id, tool_name_str, error_reason)]

  @doc """
  Creates a user message containing tool execution results.
  """
  def format_tool_result_as_message(tool_call_id, fun_name, result) do
    {:user,
     [
       %FunctionResultPart{
         id: tool_call_id,
         name: fun_name,
         result: result
       }
     ]}
  end

  @doc """
  Creates a user message containing tool execution errors.
  """
  def format_tool_error_as_message(tool_call_id, fun_name, error)
      when is_struct(error, ToolError) do
    format_tool_error_as_message(tool_call_id, fun_name, error.cause)
  end

  def format_tool_error_as_message(tool_call_id, fun_name, error) when is_binary(error) do
    content =
      "Error executing tool #{fun_name} (call_id: #{tool_call_id || "N/A"}): #{error}"

    {:user,
     [
       %FunctionResultPart{
         id: tool_call_id,
         name: fun_name,
         result: content
       }
     ]}
  end

  @doc """
  Formats multiple tool results into a single user message with multiple parts.
  """
  def format_multiple_tool_results(tool_results) when is_list(tool_results) do
    parts =
      Enum.flat_map(tool_results, fn
        {:ok, result, tool_call_id, tool_name} ->
          [
            %FunctionResultPart{
              id: tool_call_id,
              name: tool_name,
              result: result
            }
          ]

        {:error, error, tool_call_id, tool_name} ->
          [format_tool_error_part(tool_call_id, tool_name, error)]
      end)

    {:user, parts}
  end

  defp format_tool_error_part(tool_call_id, tool_name, error) when is_struct(error, ToolError),
    do: format_tool_error_part(tool_call_id, tool_name, error.cause)

  defp format_tool_error_part(tool_call_id, tool_name, error) do
    %FunctionResultPart{
      id: tool_call_id,
      name: tool_name,
      result: "Error: #{inspect(error)}"
    }
  end

  @doc """
  Extracts specific types of parts from a message.
  """
  def extract_parts_by_type({_role, parts}, part_type) when is_list(parts) do
    Enum.filter(parts, fn
      %^part_type{} -> true
      _ -> false
    end)
  end

  def extract_parts_by_type(_, _), do: []

  @doc """
  Separates function call parts from other content parts in a message.
  """
  def separate_function_calls({role, parts}) when is_list(parts) do
    {function_calls, other_parts} =
      Enum.split_with(parts, fn
        %FunctionCallPart{} -> true
        _ -> false
      end)

    {{role, other_parts}, function_calls}
  end

  def separate_function_calls(message), do: {message, []}

  @doc """
  Updates message history with a new message, optionally resetting history.
  """
  def update_message_history(current_messages, new_message, reset_history \\ false) do
    if reset_history do
      [new_message]
    else
      current_messages ++ [new_message]
    end
  end

  @doc """
  Prepares messages for LLM by parsing initial messages or using existing history.
  """
  def prepare_messages_for_llm(config, input, initial_messages_history) do
    if Enum.empty?(initial_messages_history) do
      MessageParser.parse(config.messages, input)
    else
      initial_messages_history
    end
  end

  @doc """
  Combines accumulated messages with current request messages for LLM.
  """
  def combine_messages_for_llm(accumulated_messages, current_request_messages),
    do: accumulated_messages ++ current_request_messages

  @doc """
  Appends assistant response to message history.
  """
  def append_assistant_response(message_history, assistant_response_message),
    do: message_history ++ [assistant_response_message]

  @doc """
  Combines intermediate content (like thoughts) with tool execution results.
  """
  def merge_intermediate_content_with_results(nil, tool_result_message), do: tool_result_message

  def merge_intermediate_content_with_results(intermediate_parts, {:user, tool_parts}) do
    [
      {:assistant, intermediate_parts},
      {:user, tool_parts}
    ]
  end
end
