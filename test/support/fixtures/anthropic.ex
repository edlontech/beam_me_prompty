defmodule BeamMePrompty.Fixtures.Anthropic do
  @moduledoc false

  def ok() do
    "test/support/fixtures/anthropic/ok.json"
    |> File.read!()
    |> JSON.decode!()
  end
end
