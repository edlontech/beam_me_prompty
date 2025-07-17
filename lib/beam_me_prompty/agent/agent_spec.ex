defmodule BeamMePrompty.Agent.AgentSpec do
  @moduledoc """
  Canonical specification structure for BeamMePrompty agents.

  This struct represents the complete specification of an agent, containing
  all necessary information for execution regardless of whether the agent
  was compiled from DSL or loaded from a persisted configuration.

  ## Fields

  - `stages` - List of stage definitions in the agent
  - `memory_sources` - List of memory source configurations
  - `agent_config` - Agent configuration options
  """
  @moduledoc section: :agent_core_and_lifecycle

  @type t :: %__MODULE__{
          stages: list(),
          memory_sources: list(),
          agent_config: map(),
          callback_module: module()
        }

  @derive Jason.Encoder
  defstruct [:stages, :memory_sources, :agent_config, :callback_module]

  @doc """
  Creates a new AgentSpec from a deserialized agent specification map.

  This function is used by virtual agents to create a spec from persisted
  agent configuration data.

  ## Parameters

  - `spec_map` - Map containing agent specification data

  ## Returns

  - `{:ok, %AgentSpec{}}` - Successfully created specification
  - `{:error, reason}` - Invalid specification map
  """
  @spec from_map(map(), module()) :: {:ok, t()} | {:error, term()}
  def from_map(map, module) do
    agent_spec = Map.put(map, :callback_module, module)
    {:ok, struct!(__MODULE__, agent_spec)}
  rescue
    e in ArgumentError ->
      {:error, "Invalid AgentSpec map: #{inspect(e.message)}"}
  end

  @doc """
  Validates that an AgentSpec contains all required fields and valid data.

  ## Parameters

  - `spec` - The AgentSpec to validate

  ## Returns

  - `:ok` - Specification is valid
  - `{:error, reason}` - Specification is invalid
  """
  @spec validate(t()) :: :ok | {:error, term()}
  def validate(%__MODULE__{
        stages: stages,
        memory_sources: memory_sources,
        agent_config: agent_config,
        callback_module: callback_module
      })
      when is_list(stages) and
             is_list(memory_sources) and
             is_map(agent_config) and
             is_atom(callback_module) do
    :ok
  end

  def validate(spec), do: {:error, "Invalid AgentSpec: #{inspect(spec)}"}
end
