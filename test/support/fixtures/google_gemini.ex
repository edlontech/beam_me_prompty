defmodule BeamMePrompty.Fixtures.GoogleGemini do
  @moduledoc false

  def ok() do
    "test/support/fixtures/google_gemini/ok.json"
    |> File.read!()
    |> JSON.decode!()
  end
end
