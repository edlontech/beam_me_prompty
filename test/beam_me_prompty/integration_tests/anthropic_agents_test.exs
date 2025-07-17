defmodule BeamMePrompty.IntegrationTests.AnthropicAgentsTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.IntegrationAgents.Anthropic.AgentWithMemory
  alias BeamMePrompty.IntegrationAgents.Anthropic.AgentWithStructuredResponse
  alias BeamMePrompty.IntegrationAgents.Anthropic.AgentWithTools
  alias BeamMePrompty.IntegrationAgents.Anthropic.FullFeaturedAgent
  alias BeamMePrompty.IntegrationAgents.Anthropic.SimpleAgent

  @moduletag :integration

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
    assert recall_text.text =~ "blue"
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
    assert {:ok, %{collect_data: [collect_text | _], analyze_data: analyze_data}} =
             FullFeaturedAgent.run_sync(%{topic: "renewable energy"})

    assert collect_text.text != nil

    assert %{
             summary: summary,
             key_findings: key_findings,
             confidence_score: confidence_score,
             next_steps: next_steps
           } = analyze_data

    assert is_binary(summary)
    assert is_list(key_findings)
    assert is_number(confidence_score)
    assert is_list(next_steps)
  end
end
