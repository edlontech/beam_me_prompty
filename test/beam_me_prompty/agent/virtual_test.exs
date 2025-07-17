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
      {:ok, agent_definition} = FullAgent.to_spec()

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)

      assert {:ok, deserialized_agent} = Serialization.deserialize(json_string)
      assert :ok = Serialization.validate(deserialized_agent)

      assert %{stages: stages, memory_sources: memory_sources, agent_config: agent_config} =
               deserialized_agent

      assert is_list(stages)
      assert is_list(memory_sources)
      assert is_map(agent_config)

      assert length(stages) == 3
      stage_names = Enum.map(stages, & &1.name)
      assert :first_stage in stage_names
      assert :second_stage in stage_names
      assert :third_stage in stage_names

      assert length(memory_sources) == 1
      [memory_source] = memory_sources

      assert %Dsl.MemorySource{name: :short_term, module: BeamMePrompty.Agent.Memory.ETS} =
               memory_source

      assert Map.has_key?(agent_config, :name)
      assert Map.has_key?(agent_config, :version)
      assert Map.has_key?(agent_config, :agent_state)
    end

    test "virtual agent with memory tools" do
      input = %{"text" => "memory test"}

      expect(FakeLlmClient.completion(_model, _messages, _llm_params, tools, _opts),
        do:
          (
            assert length(tools) > 0

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

      {:ok, agent_definition} = FullAgent.to_spec()

      assert {:ok, results} = Virtual.run_sync(agent_definition, input)

      assert is_map(results)

      assert results.first_stage == [
               %Dsl.TextPart{text: "Memory tools available", type: :text}
             ]
    end

    test "virtual agent preserves message templating" do
      input = %{"text" => "template test"}

      expect(FakeLlmClient.completion(_model, messages, _llm_params, _tools, _opts),
        do:
          (
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
            assert Enum.any?(messages, fn
                     {:user, [%Dsl.DataPart{data: %{this: "that"}}]} ->
                       true

                     _ ->
                       false
                   end)

            {:ok, [text_part("Data part preserved")]}
          )
      )

      {:ok, agent_definition} = FullAgent.to_spec()

      assert {:ok, results} = Virtual.run_sync(agent_definition, input)

      assert is_map(results)

      assert results.first_stage == [
               %Dsl.TextPart{text: "Template processed correctly", type: :text}
             ]

      assert results.third_stage == [
               %Dsl.TextPart{text: "Data part preserved", type: :text}
             ]
    end

    test "virtual agent handles LLM errors gracefully" do
      input = %{"text" => "error test"}

      expect(
        FakeLlmClient.completion(_, _, _, _, _),
        do: {:error, BeamMePrompty.LLM.Errors.UnexpectedLLMResponse.exception()}
      )

      {:ok, agent_definition} = FullAgent.to_spec()

      capture_log(fn ->
        assert {:error, _reason} = Virtual.run_sync(agent_definition, input)
      end)
    end

    test "virtual agent round-trip preserves functionality" do
      input = %{"text" => "round trip test"}

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

      {:ok, original_agent} = FullAgent.to_spec()

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
