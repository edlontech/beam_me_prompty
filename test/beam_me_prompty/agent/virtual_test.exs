defmodule BeamMePrompty.Agent.VirtualTest do
  use ExUnit.Case, async: false
  use Mimic.DSL

  import BeamMePrompty.Agent.Dsl.Part
  import ExUnit.CaptureLog

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Agent.Serialization
  alias BeamMePrompty.Agent.Virtual
  alias BeamMePrompty.FakeLlmClient
  alias BeamMePrompty.FullAgent

  setup :set_mimic_global
  setup :verify_on_exit!

  describe "virtual agent serialization/deserialization" do
    test "serializes and deserializes FullAgent successfully" do
      # Get the agent configuration from FullAgent
      agent_definition = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      # Serialize the agent
      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)

      # Deserialize the agent
      assert {:ok, deserialized_agent} = Serialization.deserialize(json_string)

      # Validate the deserialized agent
      assert :ok = Serialization.validate(deserialized_agent)

      # Check the structure matches expectations
      assert %{agent: stages, memory: memory_sources, agent_config: agent_config} =
               deserialized_agent

      assert is_list(stages)
      assert is_list(memory_sources)
      assert is_map(agent_config)

      # Validate stages
      assert length(stages) == 3
      stage_names = Enum.map(stages, & &1.name)
      assert :first_stage in stage_names
      assert :second_stage in stage_names
      assert :third_stage in stage_names

      # Validate memory sources
      assert length(memory_sources) == 1
      [memory_source] = memory_sources

      assert %Dsl.MemorySource{name: :short_term, module: BeamMePrompty.Agent.Memory.ETS} =
               memory_source

      # Validate agent config
      assert Map.has_key?(agent_config, :version)
      assert Map.has_key?(agent_config, :agent_state)
    end

    test "runs virtual agent with serialized/deserialized configuration" do
      # Create test input
      input = %{"text" => "bonk bonk bonk"}

      # Mock the LLM client responses
      expect(FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [data_part(%{"result" => "first stage result"})]}
      )

      expect(BeamMePrompty.TestTool.run(%{"val1" => "test1", "val2" => "test2"}, _context),
        do: {:ok, "Tool executed successfully"}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do:
          {:ok,
           [
             function_call_part("id", "test_tool", %{
               "val1" => "test1",
               "val2" => "test2"
             })
           ]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Tool result processed")]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Final stage complete")]}
      )

      # Get the agent configuration and serialize it
      agent_definition = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)

      # Run the virtual agent with the serialized configuration
      assert {:ok, results} = Virtual.run_sync(json_string, input)

      # Verify the results
      assert is_map(results)
      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      # Verify stage results
      assert results.first_stage == [
               %Dsl.DataPart{data: %{"result" => "first stage result"}, type: :data}
             ]

      assert results.second_stage == [
               %Dsl.TextPart{text: "Tool result processed", type: :text}
             ]

      assert results.third_stage == [
               %Dsl.TextPart{text: "Final stage complete", type: :text}
             ]
    end

    test "runs virtual agent with deserialized map configuration" do
      # Create test input
      input = %{"text" => "test with map"}

      # Mock the LLM client responses
      expect(FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Map config works")]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Second stage from map")]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Third stage from map")]}
      )

      # Get the agent configuration and serialize/deserialize it
      agent_definition = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert {:ok, deserialized_agent} = Serialization.deserialize(json_string)

      # Run the virtual agent with the deserialized map configuration
      assert {:ok, results} = Virtual.run_sync(deserialized_agent, input)

      # Verify the results
      assert is_map(results)
      assert Map.has_key?(results, :first_stage)
      assert Map.has_key?(results, :second_stage)
      assert Map.has_key?(results, :third_stage)

      # Verify stage results
      assert results.first_stage == [
               %Dsl.TextPart{text: "Map config works", type: :text}
             ]

      assert results.second_stage == [
               %Dsl.TextPart{text: "Second stage from map", type: :text}
             ]

      assert results.third_stage == [
               %Dsl.TextPart{text: "Third stage from map", type: :text}
             ]
    end

    test "handles validation errors in virtual agent" do
      # Create an invalid agent configuration
      invalid_agent_spec = %{
        agent: ["invalid_stage"],
        memory: [],
        agent_config: %{}
      }

      # Try to run the virtual agent with invalid configuration
      assert {:error, %BeamMePrompty.Errors.ValidationError{}} =
               Virtual.run_sync(invalid_agent_spec, %{})
    end

    test "handles deserialization errors in virtual agent" do
      # Create invalid JSON
      invalid_json = "{invalid json"

      # Try to run the virtual agent with invalid JSON
      assert {:error, %BeamMePrompty.Errors.DeserializationError{}} =
               Virtual.run_sync(invalid_json, %{})
    end

    test "handles invalid agent spec format" do
      # Try to run the virtual agent with invalid spec format
      assert {:error, %BeamMePrompty.Errors.ValidationError{}} = Virtual.run_sync(123, %{})
    end

    test "virtual agent with memory tools" do
      # Create test input
      input = %{"text" => "memory test"}

      # Mock the LLM client responses - expect memory tools to be included
      expect(FakeLlmClient.completion(_model, _messages, _llm_params, tools, _opts),
        do:
          (
            # Should have memory tools injected
            assert length(tools) > 0

            # Check for memory tools
            tool_names = Enum.map(tools, & &1.name)
            assert :memory_store in tool_names
            assert :memory_retrieve in tool_names
            assert :memory_search in tool_names
            assert :memory_delete in tool_names
            assert :memory_list_keys in tool_names
            assert :memory_list_sources in tool_names

            {:ok, [text_part("Memory tools available")]}
          )
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Second stage with memory")]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Third stage with memory")]}
      )

      # Get the agent configuration and serialize it
      agent_definition = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)

      # Run the virtual agent
      assert {:ok, results} = Virtual.run_sync(json_string, input)

      # Verify the results
      assert is_map(results)

      assert results.first_stage == [
               %Dsl.TextPart{text: "Memory tools available", type: :text}
             ]
    end

    test "virtual agent preserves message templating" do
      # Create test input with template variables
      input = %{"text" => "template test"}

      # Mock the LLM client responses
      expect(FakeLlmClient.completion(_model, messages, _llm_params, _tools, _opts),
        do:
          (
            # Check that the template was processed correctly
            assert Enum.any?(messages, fn
                     {:user, [%Dsl.TextPart{text: text}]} ->
                       text == "Wat dis template test"

                     _ ->
                       false
                   end)

            {:ok, [text_part("Template processed correctly")]}
          )
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Second stage")]}
      )

      expect(
        FakeLlmClient.completion(_model, messages, _llm_params, _tools, _opts),
        do:
          (
            # Check that the data part is preserved
            assert Enum.any?(messages, fn
                     {:user, [%Dsl.DataPart{data: %{"this" => "that"}}]} ->
                       true

                     _ ->
                       false
                   end)

            {:ok, [text_part("Data part preserved")]}
          )
      )

      # Get the agent configuration and serialize it
      agent_definition = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)

      # Run the virtual agent
      assert {:ok, results} = Virtual.run_sync(json_string, input)

      # Verify the results
      assert is_map(results)

      assert results.first_stage == [
               %Dsl.TextPart{text: "Template processed correctly", type: :text}
             ]

      assert results.third_stage == [
               %Dsl.TextPart{text: "Data part preserved", type: :text}
             ]
    end

    test "virtual agent handles LLM errors gracefully" do
      # Create test input
      input = %{"text" => "error test"}

      # Mock the LLM client to return an error
      expect(
        FakeLlmClient.completion(_, _, _, _, _),
        do: {:error, BeamMePrompty.LLM.Errors.UnexpectedLLMResponse.exception()}
      )

      # Get the agent configuration and serialize it
      agent_definition = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)

      # Run the virtual agent and expect it to handle the error gracefully
      capture_log(fn ->
        assert {:error, _reason} = Virtual.run_sync(json_string, input)
      end)
    end

    test "virtual agent round-trip preserves functionality" do
      # Create test input
      input = %{"text" => "round trip test"}

      # Mock the LLM client responses
      expect(FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Round trip first")]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Round trip second")]}
      )

      expect(
        FakeLlmClient.completion(_model, _messages, _llm_params, _tools, _opts),
        do: {:ok, [text_part("Round trip third")]}
      )

      # Get the original agent configuration
      original_agent = %{
        agent: FullAgent.stages(),
        memory: FullAgent.memory_sources(),
        agent_config: FullAgent.agent_config()
      }

      # Serialize and deserialize multiple times to test round-trip stability
      assert {:ok, json_string1} = Serialization.serialize(original_agent)
      assert {:ok, deserialized_agent1} = Serialization.deserialize(json_string1)
      assert {:ok, json_string2} = Serialization.serialize(deserialized_agent1)
      assert {:ok, deserialized_agent2} = Serialization.deserialize(json_string2)

      # Validate all configurations
      assert :ok = Serialization.validate(original_agent)
      assert :ok = Serialization.validate(deserialized_agent1)
      assert :ok = Serialization.validate(deserialized_agent2)

      # Run the virtual agent with the final configuration
      assert {:ok, results} = Virtual.run_sync(deserialized_agent2, input)

      # Verify the results
      assert is_map(results)

      assert results.first_stage == [
               %Dsl.TextPart{text: "Round trip first", type: :text}
             ]

      assert results.second_stage == [
               %Dsl.TextPart{text: "Round trip second", type: :text}
             ]

      assert results.third_stage == [
               %Dsl.TextPart{text: "Round trip third", type: :text}
             ]
    end
  end
end
