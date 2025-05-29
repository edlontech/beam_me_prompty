defmodule BeamMePrompty.Agent.Stage.ToolExecutorTest do
  use ExUnit.Case, async: true
  use Mimic

  alias BeamMePrompty.Agent.Stage.AgentCallbacks
  alias BeamMePrompty.Agent.Stage.MessageManager
  alias BeamMePrompty.Agent.Stage.ToolExecutor
  alias BeamMePrompty.LLM.Errors.ToolError
  alias BeamMePrompty.Telemetry

  # Test data setup
  defp sample_tool_info do
    %{
      tool_name: "test_tool",
      tool_args: %{"param" => "value"},
      tool_call_id: "call_123"
    }
  end

  defp sample_tool_def do
    %{
      name: "test_tool",
      module: BeamMePrompty.WhatDoesTheFoxSayTool
    }
  end

  defp sample_available_tools do
    [sample_tool_def()]
  end

  defp sample_params do
    {
      :llm_client,
      :model,
      sample_available_tools(),

      # llm_params
      %{},

      # message_history
      [],

      # remaining_iterations
      5,
      TestAgent,

      # current_agent_state
      %{},
      "test_stage",
      "session_123"
    }
  end

  describe "handle_tool_not_found/12" do
    setup :verify_on_exit!

    test "handles tool not found scenario" do
      tool_info = sample_tool_info()

      {llm_client, model, available_tools, llm_params, message_history, remaining_iterations,
       agent_module, current_agent_state, stage_name, session_id} = sample_params()

      # Mock telemetry calls
      expect(Telemetry, :tool_execution_start, fn ^agent_module,
                                                  ^session_id,
                                                  ^stage_name,
                                                  tool_name,
                                                  tool_args ->
        assert tool_name == "test_tool"
        assert tool_args == %{"param" => "value"}
        :ok
      end)

      expect(Telemetry, :tool_execution_stop, fn ^agent_module,
                                                 ^session_id,
                                                 ^stage_name,
                                                 tool_name,
                                                 status,
                                                 error_content ->
        assert tool_name == "test_tool"
        assert status == :error
        assert error_content == "Tool not defined: test_tool"
        :ok
      end)

      # Mock message manager
      expected_error_message = %{role: "tool", content: "Tool not defined: test_tool"}

      expect(MessageManager, :format_tool_error_as_message, fn call_id,
                                                               tool_name,
                                                               error_content ->
        assert call_id == "call_123"
        assert tool_name == "test_tool"
        assert error_content == "Tool not defined: test_tool"
        expected_error_message
      end)

      # Mock agent callbacks
      expect(AgentCallbacks, :call_tool_result, fn ^agent_module, tool_name, outcome, state ->
        assert tool_name == "test_tool"
        assert elem(outcome, 0) == :error
        assert state == %{}
        {:ok, %{updated: true}}
      end)

      expect(AgentCallbacks, :update_agent_state_from_callback, fn status, new_state, old_state ->
        assert status == :ok
        assert new_state == %{updated: true}
        assert old_state == %{}
        %{final: true}
      end)

      result =
        ToolExecutor.handle_tool_not_found(
          tool_info,
          llm_client,
          model,
          available_tools,
          llm_params,
          message_history,
          remaining_iterations,
          agent_module,
          current_agent_state,
          stage_name,
          session_id
        )

      assert {
               :continue_llm_interactions,
               ^llm_client,
               ^model,
               ^available_tools,
               ^llm_params,
               ^message_history,
               [^expected_error_message],
               ^remaining_iterations,
               ^agent_module,
               %{final: true}
             } = result
    end
  end

  describe "handle_tool_execution/12" do
    setup :verify_on_exit!

    test "handles successful tool execution" do
      tool_def = sample_tool_def()
      tool_info = sample_tool_info()

      {llm_client, model, available_tools, llm_params, message_history, remaining_iterations,
       agent_module, current_agent_state, stage_name, session_id} = sample_params()

      # Mock the tool module
      expect(BeamMePrompty.WhatDoesTheFoxSayTool, :run, fn args, _context ->
        assert args == %{"param" => "value"}
        {:ok, "tool result"}
      end)

      # Mock telemetry calls
      expect(Telemetry, :tool_execution_start, fn ^agent_module,
                                                  ^session_id,
                                                  ^stage_name,
                                                  tool_name,
                                                  tool_args ->
        assert tool_name == "test_tool"
        assert tool_args == %{"param" => "value"}
        :ok
      end)

      expect(Telemetry, :tool_execution_stop, fn ^agent_module,
                                                 ^session_id,
                                                 ^stage_name,
                                                 tool_name,
                                                 status,
                                                 result ->
        assert tool_name == "test_tool"
        assert status == :ok
        assert result == {:ok, "tool result"}
        :ok
      end)

      # Mock message manager
      expected_result_message = [%{role: "tool", content: "tool result"}]

      expect(MessageManager, :format_tool_result_message, fn result, call_id, tool_name ->
        assert result == {:ok, "tool result"}
        assert call_id == "call_123"
        assert tool_name == "test_tool"
        expected_result_message
      end)

      # Mock agent callbacks
      expect(AgentCallbacks, :call_tool_result, fn ^agent_module, tool_name, outcome, state ->
        assert tool_name == "test_tool"
        assert outcome == {:ok, "tool result"}
        assert state == %{}
        {:ok, %{updated: true}}
      end)

      expect(AgentCallbacks, :update_agent_state_from_callback, fn status, new_state, old_state ->
        assert status == :ok
        assert new_state == %{updated: true}
        assert old_state == %{}
        %{final: true}
      end)

      result =
        ToolExecutor.handle_tool_execution(
          tool_def,
          tool_info,
          llm_client,
          model,
          available_tools,
          llm_params,
          message_history,
          remaining_iterations,
          agent_module,
          current_agent_state,
          stage_name,
          session_id
        )

      assert {
               :continue_llm_interactions,
               ^llm_client,
               ^model,
               ^available_tools,
               ^llm_params,
               ^message_history,
               ^expected_result_message,
               ^remaining_iterations,
               ^agent_module,
               %{final: true}
             } = result
    end

    test "handles tool execution error" do
      tool_def = sample_tool_def()
      tool_info = sample_tool_info()

      {llm_client, model, available_tools, llm_params, message_history, remaining_iterations,
       agent_module, current_agent_state, stage_name, session_id} = sample_params()

      # Mock the tool module to return error
      expect(BeamMePrompty.WhatDoesTheFoxSayTool, :run, fn _args, _context ->
        {:error, "tool failed"}
      end)

      # Mock telemetry calls
      expect(Telemetry, :tool_execution_start, fn _, _, _, _, _ -> :ok end)

      expect(Telemetry, :tool_execution_stop, fn ^agent_module,
                                                 ^session_id,
                                                 ^stage_name,
                                                 tool_name,
                                                 status,
                                                 result ->
        assert tool_name == "test_tool"
        assert status == :error
        assert result == {:error, "tool failed"}
        :ok
      end)

      # Mock message manager
      expected_result_message = [%{role: "tool", content: "error: tool failed"}]

      expect(MessageManager, :format_tool_result_message, fn result, call_id, tool_name ->
        assert result == {:error, "tool failed"}
        assert call_id == "call_123"
        assert tool_name == "test_tool"
        expected_result_message
      end)

      # Mock agent callbacks
      expect(AgentCallbacks, :call_tool_result, fn _, _, _, _ -> {:ok, %{}} end)
      expect(AgentCallbacks, :update_agent_state_from_callback, fn _, _, _ -> %{} end)

      result =
        ToolExecutor.handle_tool_execution(
          tool_def,
          tool_info,
          llm_client,
          model,
          available_tools,
          llm_params,
          message_history,
          remaining_iterations,
          agent_module,
          current_agent_state,
          stage_name,
          session_id
        )

      assert {
               :continue_llm_interactions,
               ^llm_client,
               ^model,
               ^available_tools,
               ^llm_params,
               ^message_history,
               ^expected_result_message,
               ^remaining_iterations,
               ^agent_module,
               %{}
             } = result
    end
  end

  describe "execute_tool/2" do
    setup :verify_on_exit!

    test "executes tool successfully" do
      tool_def = sample_tool_def()
      tool_args = %{"param" => "value"}

      expect(BeamMePrompty.WhatDoesTheFoxSayTool, :run, fn args, _context ->
        assert args == tool_args
        {:ok, "success"}
      end)

      result = ToolExecutor.execute_tool(tool_def, tool_args)
      assert result == {:ok, "success"}
    end

    test "handles tool execution exception" do
      tool_def = sample_tool_def()
      tool_args = %{"param" => "value"}

      expect(BeamMePrompty.WhatDoesTheFoxSayTool, :run, fn _args, _context ->
        raise "Something went wrong"
      end)

      result = ToolExecutor.execute_tool(tool_def, tool_args)
      assert {:error, %ToolError{}} = result
    end
  end

  describe "find_tool_definition/2" do
    test "finds existing tool" do
      available_tools = sample_available_tools()
      result = ToolExecutor.find_tool_definition(available_tools, "test_tool")
      assert result == sample_tool_def()
    end

    test "returns nil for non-existent tool" do
      available_tools = sample_available_tools()
      result = ToolExecutor.find_tool_definition(available_tools, "non_existent")
      assert result == nil
    end

    test "works with empty tool list" do
      result = ToolExecutor.find_tool_definition([], "any_tool")
      assert result == nil
    end
  end

  describe "extract_tool_info/1" do
    test "extracts tool info with string tool name" do
      tool_function_call_part = %{
        function_call: %{
          name: "test_tool",
          arguments: %{"param" => "value"},
          id: "call_123"
        }
      }

      result = ToolExecutor.extract_tool_info(tool_function_call_part)

      assert result == %{
               tool_name: :test_tool,
               tool_args: %{"param" => "value"},
               tool_call_id: "call_123"
             }
    end

    test "extracts tool info without id" do
      tool_function_call_part = %{
        function_call: %{
          name: "test_tool",
          arguments: %{"param" => "value"}
        }
      }

      result = ToolExecutor.extract_tool_info(tool_function_call_part)

      assert result == %{
               tool_name: :test_tool,
               tool_args: %{"param" => "value"},
               tool_call_id: nil
             }
    end
  end

  describe "process_tool_call/11" do
    setup :verify_on_exit!

    test "processes tool call with existing tool" do
      tool_info = sample_tool_info()

      {llm_client, model, available_tools, llm_params, message_history, remaining_iterations,
       agent_module, current_agent_state, stage_name, session_id} = sample_params()

      # Mock tool call callback
      expect(AgentCallbacks, :call_tool_call, fn ^agent_module, tool_name, tool_args, state ->
        assert tool_name == "test_tool"
        assert tool_args == %{"param" => "value"}
        assert state == %{}
        {:ok, %{called: true}}
      end)

      expect(AgentCallbacks, :update_agent_state_from_callback, fn status, new_state, old_state ->
        assert status == :ok
        assert new_state == %{called: true}
        assert old_state == %{}
        %{updated_after_call: true}
      end)

      # Mock the subsequent tool execution flow
      expect(BeamMePrompty.WhatDoesTheFoxSayTool, :run, fn _args, _context -> {:ok, "result"} end)
      expect(Telemetry, :tool_execution_start, fn _, _, _, _, _ -> :ok end)
      expect(Telemetry, :tool_execution_stop, fn _, _, _, _, _, _ -> :ok end)
      expect(MessageManager, :format_tool_result_message, fn _, _, _ -> [] end)
      expect(AgentCallbacks, :call_tool_result, fn _, _, _, _ -> {:ok, %{}} end)
      expect(AgentCallbacks, :update_agent_state_from_callback, fn _, _, _ -> %{} end)

      result =
        ToolExecutor.process_tool_call(
          tool_info,
          available_tools,
          llm_client,
          model,
          llm_params,
          message_history,
          remaining_iterations,
          agent_module,
          current_agent_state,
          stage_name,
          session_id
        )

      assert {
               :continue_llm_interactions,
               ^llm_client,
               ^model,
               ^available_tools,
               ^llm_params,
               ^message_history,
               [],

               # remaining_iterations - 1
               4,
               ^agent_module,
               %{}
             } = result
    end

    test "processes tool call with non-existent tool" do
      tool_info = %{sample_tool_info() | tool_name: "non_existent_tool"}

      {llm_client, model, available_tools, llm_params, message_history, remaining_iterations,
       agent_module, current_agent_state, stage_name, session_id} = sample_params()

      # Mock tool call callback
      expect(AgentCallbacks, :call_tool_call, fn _, _, _, _ -> {:ok, %{}} end)
      expect(AgentCallbacks, :update_agent_state_from_callback, fn _, _, _ -> %{} end)

      # Mock the tool not found flow
      expect(Telemetry, :tool_execution_start, fn _, _, _, _, _ -> :ok end)
      expect(Telemetry, :tool_execution_stop, fn _, _, _, _, _, _ -> :ok end)
      expect(MessageManager, :format_tool_error_as_message, fn _, _, _ -> %{} end)
      expect(AgentCallbacks, :call_tool_result, fn _, _, _, _ -> {:ok, %{}} end)
      expect(AgentCallbacks, :update_agent_state_from_callback, fn _, _, _ -> %{} end)

      result =
        ToolExecutor.process_tool_call(
          tool_info,
          available_tools,
          llm_client,
          model,
          llm_params,
          message_history,
          remaining_iterations,
          agent_module,
          current_agent_state,
          stage_name,
          session_id
        )

      assert {
               :continue_llm_interactions,
               ^llm_client,
               ^model,
               ^available_tools,
               ^llm_params,
               ^message_history,
               [%{}],

               # remaining_iterations - 1
               4,
               ^agent_module,
               %{}
             } = result
    end
  end

  describe "normalize_tool_name/1 (private)" do
    # We can't directly test private functions, but we can test the behavior through extract_tool_info
    test "normalizes tool name to atom when possible" do
      # First create the atom so String.to_existing_atom works
      _ = :existing_tool_atom

      tool_function_call_part = %{
        function_call: %{
          name: "existing_tool_atom",
          arguments: %{}
        }
      }

      result = ToolExecutor.extract_tool_info(tool_function_call_part)
      assert result.tool_name == :existing_tool_atom
    end

    test "keeps tool name as string when atom doesn't exist" do
      tool_function_call_part = %{
        function_call: %{
          name: "non_existing_atom_tool",
          arguments: %{}
        }
      }

      result = ToolExecutor.extract_tool_info(tool_function_call_part)
      assert result.tool_name == "non_existing_atom_tool"
    end
  end
end
