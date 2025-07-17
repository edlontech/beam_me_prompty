defmodule BeamMePrompty.TestTools.DataProcessor do
  @moduledoc false
  use BeamMePrompty.Tool,
    name: :process_data,
    description: "Processes and transforms data structures",
    parameters: %{
      type: :object,
      properties: %{
        data: %{
          type: :array,
          description: "Array of data items to process",
          items: %{type: :object}
        },
        operation: %{
          type: :string,
          description: "Operation to perform on the data",
          enum: ["count", "sum", "filter", "sort"]
        },
        field: %{
          type: :string,
          description: "Field to operate on (for sum, filter, sort operations)"
        },
        filter_value: %{
          type: :string,
          description: "Value to filter by (for filter operation)"
        }
      },
      required: [:data, :operation]
    }

  @impl true
  def run(%{"data" => data, "operation" => "count"}, _context) do
    {:ok, %{count: length(data)}}
  end

  def run(%{"data" => data, "operation" => "sum", "field" => field}, _context) do
    sum =
      data
      |> Enum.map(& &1[field])
      |> Enum.filter(&is_number/1)
      |> Enum.sum()

    {:ok, %{sum: sum, field: field}}
  end

  def run(
        %{"data" => data, "operation" => "filter", "field" => field, "filter_value" => value},
        _context
      ) do
    filtered = Enum.filter(data, &(&1[field] == value))
    {:ok, %{filtered_data: filtered, count: length(filtered)}}
  end

  def run(%{"data" => data, "operation" => "sort", "field" => field}, _context) do
    sorted = Enum.sort_by(data, & &1[field])
    {:ok, %{sorted_data: sorted}}
  end

  def run(%{"data" => _data, "operation" => operation}, _context) do
    {:error, "Unsupported operation: #{operation}"}
  end
end

