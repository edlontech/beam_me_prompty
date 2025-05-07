defmodule BeamMePrompty.A2A.Models.Message do
  @moduledoc """
  Defines the structure for Agent-to-Agent (A2A) communication messages.

  A message consists of:
  - role: Either "user" or "agent"
  - parts: A list of Part structs
  - metadata: Optional metadata as key-value pairs
  """

  alias BeamMePrompty.A2A.Models.Part

  @type t :: %{
          # "user" | "agent"
          role: String.t(),
          parts: [Part.t()],
          metadata: map()
        }

  @doc """
  Creates a new message.

  ## Examples

      iex> Message.new("user", [Part.text("Hello")])
      %{role: "user", parts: [%{type: "text", text: "Hello", metadata: %{}}], metadata: %{}}
      
      iex> Message.new("agent", [Part.text("How can I help?")], %{timestamp: "2023-01-01"})
      %{role: "agent", parts: [%{type: "text", text: "How can I help?", metadata: %{}}], metadata: %{timestamp: "2023-01-01"}}

  ## Parameters
    - role: Either "user" or "agent"
    - parts: A list of Part structs
    - metadata: Optional metadata as a map (default: %{})

  ## Returns
    - A new message map
  """
  def new(role, parts, metadata \\ %{}) when role in ["user", "agent"] and is_list(parts) do
    %{
      role: role,
      parts: parts,
      metadata: metadata
    }
  end

  @doc """
  Creates a new user message.

  ## Examples

      iex> Message.user([Part.text("Hello")])
      %{role: "user", parts: [%{type: "text", text: "Hello", metadata: %{}}], metadata: %{}}
      
      iex> Message.user([Part.text("Help")], %{urgent: true})
      %{role: "user", parts: [%{type: "text", text: "Help", metadata: %{}}], metadata: %{urgent: true}}

  ## Parameters
    - parts: A list of Part structs
    - metadata: Optional metadata as a map (default: %{})

  ## Returns
    - A new user message map
  """
  def user(parts, metadata \\ %{}) when is_list(parts) do
    new("user", parts, metadata)
  end

  @doc """
  Creates a new agent message.

  ## Examples

      iex> Message.agent([Part.text("How can I help?")])
      %{role: "agent", parts: [%{type: "text", text: "How can I help?", metadata: %{}}], metadata: %{}}
      
      iex> Message.agent([Part.text("Processing")], %{status: "thinking"})
      %{role: "agent", parts: [%{type: "text", text: "Processing", metadata: %{}}], metadata: %{status: "thinking"}}

  ## Parameters
    - parts: A list of Part structs
    - metadata: Optional metadata as a map (default: %{})

  ## Returns
    - A new agent message map
  """
  def agent(parts, metadata \\ %{}) when is_list(parts) do
    new("agent", parts, metadata)
  end
end
