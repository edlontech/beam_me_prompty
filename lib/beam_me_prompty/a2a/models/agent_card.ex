defmodule BeamMePrompty.A2A.Models.AgentCard do
  @moduledoc """
  Represents an agent's identity and capabilities in the Agent-to-Agent (A2A) protocol.

  An AgentCard serves as a standardized way for agents to share information about:
  - Who they are (identity)
  - What they can do (capabilities/skills)
  - How to interact with them (interface, authentication)

  This enables dynamic discovery and communication between agents.
  """

  @type provider :: %{
          optional(:organization) => String.t(),
          optional(:url) => String.t()
        }

  @type capabilities :: %{
          optional(:streaming) => boolean(),
          optional(:pushNotifications) => boolean(),
          optional(:stateTransitionHistory) => boolean()
        }

  @type authentication :: %{
          required(:schemes) => [String.t()],
          optional(:credentials) => String.t()
        }

  @type skill :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:description) => String.t(),
          required(:tags) => [String.t()],
          optional(:examples) => [String.t()],
          optional(:inputModes) => [String.t()],
          optional(:outputModes) => [String.t()]
        }

  @type t :: %__MODULE__{
          # Core identity
          id: String.t(),
          name: String.t(),
          description: String.t(),
          version: String.t(),

          # Communication endpoints
          url: String.t(),
          documentationUrl: String.t() | nil,

          # Provider information
          provider: provider() | nil,

          # Capabilities
          capabilities: capabilities(),

          # Authentication
          authentication: authentication(),

          # Interaction modes
          defaultInputModes: [String.t()],
          defaultOutputModes: [String.t()],

          # Skills
          skills: [skill()],

          # Metadata
          metadata: map(),

          # Creation and update timestamps
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    # Core identity
    :id,
    :name,
    :description,
    :version,

    # Communication endpoints
    :url,
    :documentationUrl,

    # Provider information
    :provider,

    # Capabilities
    capabilities: %{},

    # Authentication
    authentication: %{schemes: []},

    # Interaction modes
    defaultInputModes: [],
    defaultOutputModes: [],

    # Skills
    skills: [],

    # Metadata
    metadata: %{},

    # Creation and update timestamps
    created_at: nil,
    updated_at: nil
  ]

  @doc """
  Creates a new AgentCard with the given attributes.

  ## Examples
      
      iex> BeamMePrompty.A2A.Models.AgentCard.new(%{
      ...>   id: "agent-123",
      ...>   name: "Data Processor",
      ...>   description: "Processes and analyzes data",
      ...>   version: "1.0.0",
      ...>   capabilities: [%{name: "data_analysis", description: "Analyzes data"}]
      ...> })
      %BeamMePrompty.A2A.Models.AgentCard{
        id: "agent-123",
        name: "Data Processor",
        description: "Processes and analyzes data",
        version: "1.0.0",
        capabilities: [%{name: "data_analysis", description: "Analyzes data"}],
        created_at: ~U[...],
        updated_at: ~U[...]
      }
  """
  def new(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{}
    |> Map.merge(Map.new(attrs))
    |> Map.put(:created_at, Map.get(attrs, :created_at, now))
    |> Map.put(:updated_at, Map.get(attrs, :updated_at, now))
  end

  @doc """
  Validates that the AgentCard has all required fields.

  Returns `:ok` if valid, or `{:error, reasons}` if invalid.
  """
  def validate(%__MODULE__{} = card) do
    with :ok <- validate_required_fields(card),
         :ok <- validate_capabilities(card) do
      :ok
    end
  end

  defp validate_required_fields(%__MODULE__{} = card) do
    required_fields = [:id, :name, :description, :version]

    missing_fields =
      required_fields
      |> Enum.filter(fn field -> is_nil(Map.get(card, field)) end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, "Missing required fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_capabilities(%__MODULE__{capabilities: capabilities}) do
    if is_list(capabilities) do
      :ok
    else
      {:error, "Capabilities must be a list"}
    end
  end

  @doc """
  Updates an AgentCard with new attributes.

  This function preserves the original created_at timestamp and
  updates the updated_at timestamp to the current time.
  """
  def update(%__MODULE__{} = card, attrs) do
    now = DateTime.utc_now()

    card
    |> Map.merge(Map.new(attrs))
    |> Map.put(:updated_at, now)
  end
end
