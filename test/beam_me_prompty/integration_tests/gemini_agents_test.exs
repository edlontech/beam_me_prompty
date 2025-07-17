defmodule BeamMePrompty.IntegrationTests.GeminiAgentsTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.IntegrationAgents.Gemini.AgentWithMemory
  alias BeamMePrompty.IntegrationAgents.Gemini.AgentWithStructuredResponse
  alias BeamMePrompty.IntegrationAgents.Gemini.AgentWithTools
  alias BeamMePrompty.IntegrationAgents.Gemini.FullFeaturedAgent
  alias BeamMePrompty.IntegrationAgents.Gemini.SimpleAgent

  # @moduletag :integration

  test "simple agent" do
    assert {:ok, %{simple_response: [text_part | _]}} =
             SimpleAgent.run_sync(%{question: "What is the capital of France?"})

    assert text_part.text =~ "Paris"
  end

  test "agent with memory" do
    assert {:ok, %{store_info: [store_text | _], recall_info: [recall_text | _]}} =
             AgentWithMemory.run_sync(%{
               info: "The sky is blue",
               query: "the color of the sky"
             })

    assert store_text.text != nil
    assert recall_text.text =~ "sky"
  end

  test "agent with structured response" do
    assert {:ok, %{structured_analysis: structured_data}} =
             AgentWithStructuredResponse.run_sync(%{topic: "climate change"})

    assert %{analysis: analysis, confidence: confidence, recommendations: recommendations} =
             structured_data

    assert is_binary(analysis)
    assert is_number(confidence)
    assert is_list(recommendations)
  end

  test "agent with tools" do
    assert {:ok, %{calculate: [calc_text | _], weather_check: [weather_text | _]}} =
             AgentWithTools.run_sync(%{
               expression: "5 + 3",
               location: "New York"
             })

    assert calc_text.text != nil
    assert weather_text.text != nil
  end

  test "full featured agent" do
    # Gemini does not support structured response with function calling
    assert {:error, _} =
             FullFeaturedAgent.run_sync(%{topic: "renewable energy"})
  end
end
