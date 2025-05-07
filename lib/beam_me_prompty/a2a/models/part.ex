defmodule BeamMePrompty.A2A.Models.Part do
  @moduledoc """
  Defines the structure for Agent-to-Agent (A2A) communication parts.

  Parts can be one of three types:
  - text: Contains text content
  - file: Contains file information (name, mimeType, bytes or uri)
  - data: Contains arbitrary data as key-value pairs

  Each part also includes metadata as key-value pairs.
  """

  @type text_part :: %{
          type: String.t(),
          text: String.t(),
          metadata: map()
        }

  @type file_part :: %{
          type: String.t(),
          file: %{
            optional(:name) => String.t(),
            optional(:mimeType) => String.t(),
            # base64 encoded content
            optional(:bytes) => String.t(),
            optional(:uri) => String.t()
          },
          metadata: map()
        }

  @type data_part :: %{
          type: String.t(),
          data: map(),
          metadata: map()
        }

  @type t :: text_part() | file_part() | data_part()

  @doc """
  Creates a new text part.

  ## Examples

      iex> Part.text("Hello, world!")
      %{type: "text", text: "Hello, world!", metadata: %{}}
      
      iex> Part.text("Hello, world!", %{sender: "bot"})
      %{type: "text", text: "Hello, world!", metadata: %{sender: "bot"}}

  ## Parameters
    - text: The text content
    - metadata: Optional metadata as a map (default: %{})

  ## Returns
    - A new text part map
  """
  def text(text, metadata \\ %{}) when is_binary(text) do
    %{
      type: "text",
      text: text,
      metadata: metadata
    }
  end

  @doc """
  Creates a new file part.

  ## Examples

      iex> Part.file(%{name: "image.png", mimeType: "image/png", bytes: "base64..."})
      %{type: "file", file: %{name: "image.png", mimeType: "image/png", bytes: "base64..."}, metadata: %{}}
      
      iex> Part.file(%{uri: "https://example.com/image.png"}, %{source: "web"})
      %{type: "file", file: %{uri: "https://example.com/image.png"}, metadata: %{source: "web"}}

  ## Parameters
    - file_info: A map containing file information
      - :name (optional): The name of the file
      - :mimeType (optional): The MIME type of the file
      - :bytes (optional): Base64 encoded content of the file
      - :uri (optional): URI pointing to the file
    - metadata: Optional metadata as a map (default: %{})

  ## Returns
    - A new file part map
  """
  def file(file_info, metadata \\ %{}) when is_map(file_info) do
    %{
      type: "file",
      file: file_info,
      metadata: metadata
    }
  end

  @doc """
  Creates a new data part.

  ## Examples

      iex> Part.data(%{count: 42, active: true})
      %{type: "data", data: %{count: 42, active: true}, metadata: %{}}
      
      iex> Part.data(%{user_id: 123}, %{sensitive: true})
      %{type: "data", data: %{user_id: 123}, metadata: %{sensitive: true}}

  ## Parameters
    - data: A map containing arbitrary data
    - metadata: Optional metadata as a map (default: %{})

  ## Returns
    - A new data part map
  """
  def data(data, metadata \\ %{}) when is_map(data) do
    %{
      type: "data",
      data: data,
      metadata: metadata
    }
  end
end
