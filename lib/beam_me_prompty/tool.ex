defmodule BeamMePrompty.Tool do
  @moduledoc """
  A behaviour module for defining tools that can be used by agents in the BeamMePrompty system.

  Tools are executable modules that provide specific functionalities for agents to perform tasks.
  Each tool must implement the `run/1` function that accepts an input map with parameters and
  returns either a success tuple with a result or an error tuple.

  ## Example

  ```elixir
  defmodule MyApp.Tools.Calculator do
    @behaviour BeamMePrompty.Tool
    
    @impl BeamMePrompty.Tool
    def run(%{"operation" => "add", "a" => a, "b" => b}) do
      {:ok, %{"result" => a + b}}
    end
    
    def run(%{"operation" => "subtract", "a" => a, "b" => b}) do
      {:ok, %{"result" => a - b}}
    end
  end
  ```
  """

  @doc """
  Executes the tool with the provided input.

  ## Parameters
    * `input` - A map containing the parameters needed by the tool
    
  ## Returns
    * `{:ok, result}` - On successful execution, where `result` can be a map or string
    * `{:error, reason}` - On failure, with a reason explaining why the execution failed
  """
  @callback run(input :: map()) :: {:ok, map() | String.t()} | {:error, any()}
end
