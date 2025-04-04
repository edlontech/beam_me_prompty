defmodule BeamMePrompty.TestTool do
  @moduledoc false
  use BeamMePrompty.Tool,
    name: :test_tool,
    description: "A tool for testing purposes",
    parameters: %{
      type: :object,
      properties: %{
        arg1: %{
          type: :string,
          description: "First argument for the test tool"
        },
        arg2: %{
          type: :integer,
          description: "Second argument for the test tool"
        }
      },
      required: [:arg1]
    }

  @impl true
  def run(args, _context) do
    {:ok, "instructed to run with args: #{inspect(args)}"}
  end
end
