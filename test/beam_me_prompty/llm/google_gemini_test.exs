defmodule BeamMePrompty.LLM.GoogleGeminiTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.LLM.GoogleGemini
  alias BeamMePrompty.Fixtures.GoogleGemini, as: GeminiFixtures

  describe "completion/3" do
    test "should return a valid completion response" do
      Req.Test.stub(GoogleGemini, fn conn ->
        Req.Test.json(conn, GeminiFixtures.ok())
      end)

      assert {:ok, response} =
               GoogleGemini.completion(
                 [{:system, "You are a funny writter"}, "Tell me a joke"],
                 key: "FAKE_KEY",
                 model: "gemini-2.0-flash",
                 plug: {Req.Test, GoogleGemini}
               )

      assert response =~ "Why don't scientists trust atoms?"
    end
  end
end
