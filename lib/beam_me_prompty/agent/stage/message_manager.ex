defmodule BeamMePrompty.Agent.Stage.MessageManager do
  @moduledoc """
  Handles message formatting, response normalization, and message history management.

  This module centralizes all message-related operations including:
  - Formatting LLM responses into proper message structures
  - Creating tool result and error messages
  - Normalizing responses for validation
  - Managing message history
  """

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.TextPart
  alias BeamMePrompty.LLM.Errors.ToolError
  alias BeamMePrompty.LLM.MessageParser

  @doc """
  Formats an LLM response into a proper assistant message structure.
  """
  def format_response(response) when is_list(response) do
    {:assistant,
     Enum.map(response, fn part ->
       {_, response} = format_response(part)
       response
     end)}
  end

  def format_response(response) when is_binary(response) do
    {:assistant, [%TextPart{text: response}]}
  end

  def format_response(%{function_call: call}) do
    {:assistant, [%FunctionCallPart{function_call: call}]}
  end

  def format_response(response) when is_map(response) do
    {:assistant, [%DataPart{data: response}]}
  end

  @doc """
  Creates a tool result message for successful tool execution.
  """
  def format_tool_result_message({:ok, result_content}, tool_call_id, tool_name_str) do
    [format_tool_result_as_message(tool_call_id, tool_name_str, result_content)]
  end

  def format_tool_result_message({:error, error_reason}, tool_call_id, tool_name_str) do
    [format_tool_error_as_message(tool_call_id, tool_name_str, error_reason)]
  end

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
  Normalizes LLM response for validation purposes.
  """
  def normalize_response_for_validation(response) when is_map(response), do: response

  def normalize_response_for_validation(response) when is_binary(response) do
    case Jason.decode(response) do
      {:ok, parsed} when is_map(parsed) -> parsed
      _ -> %{"content" => response}
    end
  end

  def normalize_response_for_validation(response) when is_list(response) do
    %{"parts" => response}
  end

  def normalize_response_for_validation(response), do: %{"data" => response}

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
  def combine_messages_for_llm(accumulated_messages, current_request_messages) do
    accumulated_messages ++ current_request_messages
  end

  @doc """
  Appends assistant response to message history.
  """
  def append_assistant_response(message_history, assistant_response_message) do
    message_history ++ [assistant_response_message]
  end
end
