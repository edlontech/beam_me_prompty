defmodule BeamMePrompty.Agent.Dsl.Info do
  @moduledoc false
  use Spark.InfoGenerator, extension: BeamMePrompty.Agent.Dsl, sections: [:agent, :memory]
end
