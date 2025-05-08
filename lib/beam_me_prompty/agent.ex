defmodule BeamMePrompty.Agent do
  use Spark.Dsl,
    default_extensions: [
      extensions: [BeamMePrompty.Agent.Dsl]
    ]
end
