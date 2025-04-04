defmodule BeamMePrompty.Agent.Stage.MessageManagerTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.TextPart
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.LLM.Errors.ToolError

  describe "format_tool_result_message/3" do
    test "formats successful tool result" do
      result_content = %{"status" => "success", "data" => [1, 2, 3]}
      tool_call_id = "call_123"
      tool_name = "test_tool"

      [message] =
        MessageManager.format_tool_result_message(
          {:ok, result_content},
          tool_call_id,
          tool_name
        )

      assert {:user,
              [
                %FunctionResultPart{
                  id: "call_123",
                  name: "test_tool",
                  result: ^result_content
                }
              ]} = message
    end

    test "formats error tool result" do
      error_reason = "Connection timeout"
      tool_call_id = "call_456"
      tool_name = "failing_tool"

      [message] =
        MessageManager.format_tool_result_message(
          {:error, error_reason},
          tool_call_id,
          tool_name
        )

      assert {:user,
              [
                %FunctionResultPart{
                  id: "call_456",
                  name: "failing_tool",
                  result:
                    "Error executing tool failing_tool (call_id: call_456): Connection timeout"
                }
              ]} = message
    end
  end

  describe "format_tool_result_as_message/3" do
    test "creates user message with function result part" do
      tool_call_id = "call_789"
      fun_name = "calculator"
      result = %{"answer" => 42}

      message = MessageManager.format_tool_result_as_message(tool_call_id, fun_name, result)

      assert {:user,
              [
                %FunctionResultPart{
                  id: "call_789",
                  name: "calculator",
                  result: %{"answer" => 42}
                }
              ]} = message
    end

    test "handles nil tool_call_id" do
      message = MessageManager.format_tool_result_as_message(nil, "test", "result")

      assert {:user,
              [
                %FunctionResultPart{
                  id: nil,
                  name: "test",
                  result: "result"
                }
              ]} = message
    end
  end

  describe "format_tool_error_as_message/3" do
    test "formats ToolError struct" do
      tool_error = %ToolError{cause: "Invalid input parameters"}
      tool_call_id = "call_error"
      fun_name = "validator"

      message = MessageManager.format_tool_error_as_message(tool_call_id, fun_name, tool_error)

      assert {:user,
              [
                %FunctionResultPart{
                  id: "call_error",
                  name: "validator",
                  result:
                    "Error executing tool validator (call_id: call_error): Invalid input parameters"
                }
              ]} = message
    end

    test "formats binary error" do
      error = "Database connection failed"
      tool_call_id = "call_db"
      fun_name = "db_query"

      message = MessageManager.format_tool_error_as_message(tool_call_id, fun_name, error)

      assert {:user,
              [
                %FunctionResultPart{
                  id: "call_db",
                  name: "db_query",
                  result:
                    "Error executing tool db_query (call_id: call_db): Database connection failed"
                }
              ]} = message
    end

    test "handles nil tool_call_id in error message" do
      message = MessageManager.format_tool_error_as_message(nil, "test", "error")

      assert {:user,
              [
                %FunctionResultPart{
                  result: "Error executing tool test (call_id: N/A): error"
                }
              ]} = message
    end
  end

  describe "update_message_history/3" do
    test "appends message to existing history when reset is false" do
      current_messages = [{:user, "Hello"}, {:assistant, "Hi there!"}]
      new_message = {:user, "How are you?"}

      result = MessageManager.update_message_history(current_messages, new_message, false)

      assert [
               {:user, "Hello"},
               {:assistant, "Hi there!"},
               {:user, "How are you?"}
             ] = result
    end

    test "appends message to existing history when reset is not provided (defaults to false)" do
      current_messages = [{:user, "Hello"}]
      new_message = {:assistant, "Hi!"}

      result = MessageManager.update_message_history(current_messages, new_message)

      assert [{:user, "Hello"}, {:assistant, "Hi!"}] = result
    end

    test "resets history when reset is true" do
      current_messages = [{:user, "Old message"}, {:assistant, "Old response"}]
      new_message = {:user, "New conversation start"}

      result = MessageManager.update_message_history(current_messages, new_message, true)

      assert [{:user, "New conversation start"}] = result
    end

    test "handles empty current messages" do
      current_messages = []
      new_message = {:user, "First message"}

      result = MessageManager.update_message_history(current_messages, new_message, false)

      assert [{:user, "First message"}] = result
    end
  end

  describe "prepare_messages_for_llm/3" do
    test "returns existing history when not empty" do
      config = %{messages: [{:user, "Template: {{input}}"}]}
      input = %{"input" => "test value"}
      initial_messages_history = [{:user, "Existing message"}, {:assistant, "Response"}]

      result = MessageManager.prepare_messages_for_llm(config, input, initial_messages_history)

      assert ^initial_messages_history = result
    end
  end

  describe "combine_messages_for_llm/2" do
    test "combines accumulated and current messages" do
      accumulated_messages = [{:user, "Previous"}, {:assistant, "Response"}]
      current_request_messages = [{:user, "Current request"}]

      result =
        MessageManager.combine_messages_for_llm(accumulated_messages, current_request_messages)

      assert [
               {:user, "Previous"},
               {:assistant, "Response"},
               {:user, "Current request"}
             ] = result
    end

    test "handles empty accumulated messages" do
      accumulated_messages = []
      current_request_messages = [{:user, "Only current"}]

      result =
        MessageManager.combine_messages_for_llm(accumulated_messages, current_request_messages)

      assert [{:user, "Only current"}] = result
    end

    test "handles empty current messages" do
      accumulated_messages = [{:user, "Only accumulated"}]
      current_request_messages = []

      result =
        MessageManager.combine_messages_for_llm(accumulated_messages, current_request_messages)

      assert [{:user, "Only accumulated"}] = result
    end

    test "handles both empty" do
      result = MessageManager.combine_messages_for_llm([], [])

      assert [] = result
    end
  end

  describe "append_assistant_response/2" do
    test "appends assistant response to message history" do
      message_history = [{:user, "Question"}, {:assistant, "Answer"}]
      assistant_response_message = {:assistant, "Follow-up response"}

      result =
        MessageManager.append_assistant_response(message_history, assistant_response_message)

      assert [
               {:user, "Question"},
               {:assistant, "Answer"},
               {:assistant, "Follow-up response"}
             ] = result
    end

    test "appends to empty history" do
      message_history = []
      assistant_response_message = {:assistant, "First response"}

      result =
        MessageManager.append_assistant_response(message_history, assistant_response_message)

      assert [{:assistant, "First response"}] = result
    end

    test "handles complex assistant response structure" do
      message_history = [{:user, "Hello"}]
      assistant_response_message = {:assistant, [%TextPart{text: "Complex response"}]}

      result =
        MessageManager.append_assistant_response(message_history, assistant_response_message)

      assert [
               {:user, "Hello"},
               {:assistant, [%TextPart{text: "Complex response"}]}
             ] = result
    end
  end
end
