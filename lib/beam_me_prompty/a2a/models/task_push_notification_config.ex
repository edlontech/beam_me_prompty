defmodule BeamMePrompty.A2A.Models.TaskPushNotificationConfig do
  @moduledoc """
  Configuration for task-specific push notifications in the A2A system.

  Fields:
  - `id` - The task ID (required)
  - `push_notification_config` - The push notification configuration (required)
  """

  alias BeamMePrompty.A2A.Models.PushNotificationConfig

  @type t :: %__MODULE__{
          id: String.t(),
          push_notification_config: PushNotificationConfig.t()
        }

  @enforce_keys [:id, :push_notification_config]
  defstruct [:id, :push_notification_config]

  @doc """
  Creates a new TaskPushNotificationConfig struct from the given attributes.

  ## Parameters

  - `attrs` - Map containing the configuration attributes.
    - `id` - Required task ID string
    - `push_notification_config` - Required PushNotificationConfig struct or map to create one

  ## Returns

  `{:ok, config}` if the configuration is valid, or `{:error, reason}` if invalid.

  ## Examples

      iex> push_config = %PushNotificationConfig{url: "https://example.com/push"}
      iex> TaskPushNotificationConfig.new(%{id: "task-123", push_notification_config: push_config})
      {:ok, %TaskPushNotificationConfig{id: "task-123", push_notification_config: ^push_config}}
      
      iex> TaskPushNotificationConfig.new(%{
      ...>   id: "task-123",
      ...>   push_notification_config: %{url: "https://example.com/push"}
      ...> })
      {:ok, %TaskPushNotificationConfig{
        id: "task-123",
        push_notification_config: %PushNotificationConfig{url: "https://example.com/push"}
      }}
  """
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    try do
      # Process push_notification_config if it's a map
      attrs =
        case attrs do
          %{push_notification_config: config} when is_map(config) and not is_struct(config) ->
            # Convert the map to a PushNotificationConfig struct
            case PushNotificationConfig.new(config) do
              {:ok, push_config} ->
                Map.put(attrs, :push_notification_config, push_config)

              {:error, reason} ->
                raise ArgumentError, message: "Invalid push notification config: #{reason}"
            end

          _ ->
            attrs
        end

      config = struct!(__MODULE__, attrs)
      validate(config)
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc """
  Creates a new TaskPushNotificationConfig struct from the given attributes.

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
      {key, value} when is_binary(key) ->
        {String.to_atom(key), normalize_value(key, value)}

      {key, value} when is_atom(key) ->
        {key, normalize_value(Atom.to_string(key), value)}
    end)
  end

  defp normalize_value("push_notification_config", value) when is_map(value) do
    if is_struct(value, PushNotificationConfig) do
      value
    else
      normalize_keys(value)
    end
  end

  defp normalize_value("pushNotificationConfig", value) when is_map(value) do
    normalize_value("push_notification_config", value)
  end

  defp normalize_value(_, value), do: value

  defp validate(%__MODULE__{} = config) do
    cond do
      not is_binary(config.id) or String.trim(config.id) == "" ->
        {:error, "Task ID must be a non-empty string"}

      not is_struct(config.push_notification_config, PushNotificationConfig) ->
        {:error, "Push notification config must be a PushNotificationConfig struct"}

      true ->
        {:ok, config}
    end
  end
end
