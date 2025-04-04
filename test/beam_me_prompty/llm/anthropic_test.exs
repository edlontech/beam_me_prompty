defmodule BeamMePrompty.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  import BeamMePrompty.Agent.Dsl.Part, only: [text_part: 1]

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.Fixtures.Anthropic, as: AnthropicFixtures
  alias BeamMePrompty.LLM.Anthropic

  describe "completion/4" do
    test "should return a valid completion response" do
      Req.Test.stub(Anthropic, fn conn ->
        Req.Test.json(conn, AnthropicFixtures.ok())
      end)

      assert {:ok, [response]} =
               Anthropic.completion(
                 "claude-3-5-sonnet-20241022",
                 [
                   {:system, [text_part("You are a helpful assistant")]},
                   {:user, [text_part("Hello, how are you?")]}
                 ],
                 %LLMParams{
                   api_key: "FAKE_KEY"
                 },
                 [],
                 http_adapter: Req.Test
               )

      assert response.text =~ "Hi! My name is Claude."
    end

    test "should deal with 400s" do
      Req.Test.stub(Anthropic, fn conn ->
        Req.Test.json(%{conn | status: 400}, AnthropicFixtures.ok())
      end)

      assert {:error, response} =
               Anthropic.completion(
                 "claude-3-5-sonnet-20241022",
                 [
                   {:system, [text_part("You are a helpful assistant")]},
                   {:user, [text_part("Hello, how are you?")]}
                 ],
                 %LLMParams{
                   api_key: "FAKE_KEY"
                 },
                 [],
                 http_adapter: Req.Test
               )

      assert is_struct(response, BeamMePrompty.Errors.Invalid)
    end

    test "should deal with 500s" do
      Req.Test.stub(Anthropic, fn conn ->
        Req.Test.json(%{conn | status: 500}, AnthropicFixtures.ok())
      end)

      assert {:error, response} =
               Anthropic.completion(
                 "claude-3-5-sonnet-20241022",
                 [
                   {:system, [text_part("You are a helpful assistant")]},
                   {:user, [text_part("Hello, how are you?")]}
                 ],
                 %LLMParams{
                   api_key: "FAKE_KEY"
                 },
                 [],
                 http_adapter: Req.Test
               )

      assert is_struct(response, BeamMePrompty.Errors.External)
    end
  end
end
