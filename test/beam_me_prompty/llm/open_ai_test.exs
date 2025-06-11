defmodule BeamMePrompty.LLM.OpenAITest do
  use ExUnit.Case, async: true

  import BeamMePrompty.Agent.Dsl.Part, only: [text_part: 1]

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.Fixtures.OpenAI, as: OpenAIFixtures
  alias BeamMePrompty.LLM.OpenAI

  describe "completion/5" do
    test "should return a valid completion response" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(conn, OpenAIFixtures.ok())
      end)

      assert {:ok, [response]} =
               OpenAI.completion(
                 "gpt-4o",
                 [
                   {:system, [text_part("You are a funny writter")]},
                   {:user, [text_part("Tell me a joke")]}
                 ],
                 %LLMParams{
                   api_key: "FAKE_KEY"
                 },
                 [],
                 http_adapter: Req.Test
               )

      assert response.text =~ "Why don't scientists trust atoms?"
    end

    test "should deal with 400s" do
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(%{conn | status: 400}, OpenAIFixtures.ok())
      end)

      assert {:error, response} =
               OpenAI.completion(
                 "gpt-4o",
                 [
                   {:system, [text_part("You are a funny writter")]},
                   {:user, [text_part("Tell me a joke")]}
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
      Req.Test.stub(OpenAI, fn conn ->
        Req.Test.json(%{conn | status: 500}, OpenAIFixtures.ok())
      end)

      assert {:error, response} =
               OpenAI.completion(
                 "gpt-4o",
                 [
                   {:system, [text_part("You are a funny writter")]},
                   {:user, [text_part("Tell me a joke")]}
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
