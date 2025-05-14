defmodule BeamMePrompty.WhatDoesTheFoxSayTool do
  @behaviour BeamMePrompty.Tool

  @impl true
  def run(%{"fox_species" => fox}) do
    {:ok, "The fox #{fox} says ding ding ding"}
  end
end
