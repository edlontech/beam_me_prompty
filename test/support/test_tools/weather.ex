defmodule BeamMePrompty.TestTools.Weather do
  @moduledoc false
  use BeamMePrompty.Tool,
    name: :get_weather,
    description: "Gets weather information for a given location",
    parameters: %{
      type: :object,
      properties: %{
        location: %{
          type: :string,
          description: "The city and country (e.g., 'New York, US')"
        },
        unit: %{
          type: :string,
          description: "Temperature unit (celsius or fahrenheit)",
          enum: ["celsius", "fahrenheit"]
        }
      },
      required: [:location]
    }

  @impl true
  def run(%{"location" => location} = args, _context) do
    unit = Map.get(args, "unit", "celsius")

    # Mock weather data
    weather_data = %{
      location: location,
      temperature: if(unit == "celsius", do: 22, else: 72),
      unit: unit,
      condition: "sunny",
      humidity: 65,
      wind_speed: 10
    }

    {:ok, weather_data}
  end
end
