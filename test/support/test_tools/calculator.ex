defmodule BeamMePrompty.TestTools.Calculator do
  @moduledoc false
  use BeamMePrompty.Tool,
    name: :calculate,
    description: "Performs basic arithmetic operations",
    parameters: %{
      type: :object,
      properties: %{
        operation: %{
          type: :string,
          description: "The operation to perform (add, subtract, multiply, divide)",
          enum: ["add", "subtract", "multiply", "divide"]
        },
        a: %{
          type: :number,
          description: "First number"
        },
        b: %{
          type: :number,
          description: "Second number"
        }
      },
      required: [:operation, :a, :b]
    }

  @impl true
  def run(%{"operation" => "add", "a" => a, "b" => b}, _context) do
    {:ok, %{result: a + b, operation: "addition"}}
  end

  def run(%{"operation" => "subtract", "a" => a, "b" => b}, _context) do
    {:ok, %{result: a - b, operation: "subtraction"}}
  end

  def run(%{"operation" => "multiply", "a" => a, "b" => b}, _context) do
    {:ok, %{result: a * b, operation: "multiplication"}}
  end

  def run(%{"operation" => "divide", "a" => a, "b" => b}, _context) when b != 0 do
    {:ok, %{result: a / b, operation: "division"}}
  end

  def run(%{"operation" => "divide", "a" => _a, "b" => 0}, _context) do
    {:error, "Division by zero is not allowed"}
  end
end

