defmodule BeamMePrompty.LLM.GoogleGeminiTest do
  use ExUnit.Case, async: true

  import BeamMePrompty.Agent.Dsl.Part, only: [text_part: 1]

  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.Fixtures.GoogleGemini, as: GeminiFixtures
  alias BeamMePrompty.LLM.GoogleGemini

  describe "completion/4" do
    test "should return a valid completion response" do
      Req.Test.stub(GoogleGemini, fn conn ->
        Req.Test.json(conn, GeminiFixtures.ok())
      end)

      assert {:ok, [response]} =
               GoogleGemini.completion(
                 "gemini-2.0-flash",
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
      Req.Test.stub(GoogleGemini, fn conn ->
        Req.Test.json(%{conn | status: 400}, GeminiFixtures.ok())
      end)

      assert {:error, response} =
               GoogleGemini.completion(
                 "gemini-2.0-flash",
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
      Req.Test.stub(GoogleGemini, fn conn ->
        Req.Test.json(%{conn | status: 500}, GeminiFixtures.ok())
      end)

      assert {:error, response} =
               GoogleGemini.completion(
                 "gemini-2.0-flash",
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
