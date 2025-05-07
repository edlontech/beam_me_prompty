defmodule BeamMePrompty.A2A.Models.PushNotificationConfig do
  @moduledoc """
  Configuration for push notifications in the A2A system.

  Fields:
  - `url` - The URL to send push notifications to (required)
  - `token` - Optional token unique to this task/session
  - `authentication` - Optional authentication configuration with:
    - `schemes` - List of authentication schemes (required if authentication is present)
    - `credentials` - Optional credentials string
  """

  @type authentication :: %{
          required(:schemes) => [String.t()],
          optional(:credentials) => String.t() | nil
        }

  @type t :: %__MODULE__{
          url: String.t(),
          token: String.t() | nil,
          authentication: authentication() | nil
        }

  @enforce_keys [:url]
  defstruct [:url, :token, :authentication]

  @doc """
  Creates a new PushNotificationConfig struct from the given attributes.

  ## Parameters

  - `attrs` - Map containing the configuration attributes.
    - `url` - Required URL string
    - `token` - Optional token string
    - `authentication` - Optional authentication map with:
      - `schemes` - Required list of authentication scheme strings
      - `credentials` - Optional credentials string

  ## Returns

  `{:ok, config}` if the configuration is valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> PushNotificationConfig.new(%{url: "https://example.com/push"})
      {:ok, %PushNotificationConfig{url: "https://example.com/push"}}
      
      iex> PushNotificationConfig.new(%{
      ...>   url: "https://example.com/push",
      ...>   authentication: %{schemes: ["basic"], credentials: "base64-encoded-string"}
      ...> })
      {:ok, %PushNotificationConfig{
        url: "https://example.com/push",
        authentication: %{schemes: ["basic"], credentials: "base64-encoded-string"}
      }}
  """
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    try do
      config = struct!(__MODULE__, attrs)
      validate(config)
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Creates a new PushNotificationConfig struct from the given attributes.

  Raises an error if the configuration is invalid.
  """
  def new!(attrs) do
    case new(attrs) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, message: reason
    end
  end

  # Private helper functions

  defp normalize_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), normalize_value(key, value)}
      {key, value} when is_atom(key) -> {key, normalize_value(Atom.to_string(key), value)}
    end)
  end

  defp normalize_value("authentication", value) when is_map(value) do
    normalize_keys(value)
  end

  defp normalize_value("authentication", value) when is_list(value) do
    # Handle if authentication is given as a keyword list
    value |> Enum.into(%{}) |> normalize_keys()
  end

  defp normalize_value(_, value), do: value

  defp validate(%__MODULE__{} = config) do
    cond do
      not is_binary(config.url) or String.trim(config.url) == "" ->
        {:error, "URL must be a non-empty string"}

      not is_nil(config.token) and not is_binary(config.token) ->
        {:error, "Token must be a string"}

      not is_nil(config.authentication) ->
        case validate_authentication(config.authentication) do
          :ok -> {:ok, config}
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:ok, config}
    end
  end

  defp validate_authentication(auth) when is_map(auth) do
    schemes = Map.get(auth, :schemes)
    credentials = Map.get(auth, :credentials)

    cond do
      not is_list(schemes) or Enum.empty?(schemes) ->
        {:error, "Authentication schemes must be a non-empty list"}

      not is_nil(credentials) and not is_binary(credentials) ->
        {:error, "Authentication credentials must be a string"}

      true ->
        :ok
    end
  end

  defp validate_authentication(_), do: {:error, "Authentication must be a map"}
end
