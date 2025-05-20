defmodule BeamMePrompty.WhatDoesTheFoxSayTool do
  @moduledoc false
  use BeamMePrompty.Tool, name: :sounds_of_the_fox

  @impl true
  def run(%{"fox_species" => fox}) do
    {:ok, "The fox #{fox} says ding ding ding"}
  end
end
