defmodule BeamMePrompty.WhatDoesTheFoxSayTool do
  @moduledoc false
  use BeamMePrompty.Tool,
    name: :sounds_of_the_fox,
    description: "Returns the sound of the fox",
    parameters: %{
      type: :object,
      properties: %{
        fox_species: %{
          type: :string,
          description: "The species of the fox"
        }
      },
      required: [:fox_species]
    }

  @impl true
  def run(%{"fox_species" => fox}, _context) do
    {:ok, "The fox #{fox} says ding ding ding"}
  end
end
