defmodule BeamMePrompty.WhatDoesTheFoxSayTool do
  @moduledoc false
  @behaviour BeamMePrompty.Tool

  @impl true
  def run(%{"fox_species" => fox}) do
    {:ok, "The fox #{fox} says ding ding ding"}
  end
end
