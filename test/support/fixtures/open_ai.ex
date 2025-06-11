defmodule BeamMePrompty.Fixtures.OpenAI do
  @moduledoc false

  def ok() do
    "test/support/fixtures/open_ai/ok.json"
    |> File.read!()
    |> JSON.decode!()
  end
end
