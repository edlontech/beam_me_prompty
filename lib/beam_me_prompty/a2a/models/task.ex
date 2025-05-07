defmodule BeamMePrompty.A2A.Models.Task do
  @moduledoc """
  Defines the Task model and related structures for Agent to Agent (A2A) communication.

  This module implements the Task interface as specified in the A2A protocol.
  """
  defstruct [:id, :session_id, :status, :history, :artifacts, :metadata]

  @type task_state ::
          :submitted | :working | :"input-required" | :completed | :canceled | :failed | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          status: task_status(),
          history: [message()] | nil,
          artifacts: [artifact()] | nil,
          metadata: map() | nil
        }

  @type task_status :: %{
          state: task_state(),
          message: message() | nil,
          timestamp: String.t() | nil
        }

  @type task_status_update_event :: %{
          id: String.t(),
          status: task_status(),
          final: boolean(),
          metadata: map() | nil
        }

  @type task_artifact_update_event :: %{
          id: String.t(),
          artifact: artifact(),
          metadata: map() | nil
        }

  @type task_send_params :: %{
          id: String.t(),
          session_id: String.t() | nil,
          message: message(),
          history_length: integer() | nil,
          push_notification: push_notification_config() | nil,
          metadata: map() | nil
        }

  # These would need to be defined elsewhere based on the full specification
  @type message :: map()
  @type artifact :: map()
  @type push_notification_config :: map()

  @doc """
  Creates a new Task with the given parameters.

  ## Parameters
    - params: A map containing the task parameters (id, session_id, status, etc.)

  ## Returns
    - A new Task struct
  """
  def new(params \\ %{}) do
    %__MODULE__{
      id: Map.get(params, :id),
      session_id: Map.get(params, :session_id),
      status:
        Map.get(params, :status, %{
          state: :submitted,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }),
      history: Map.get(params, :history),
      artifacts: Map.get(params, :artifacts),
      metadata: Map.get(params, :metadata)
    }
  end

  @doc """
  Updates the status of a task.

  ## Parameters
    - task: The task to update
    - state: The new state (:submitted, :working, etc.)
    - message: Optional message to include with the status update

  ## Returns
    - An updated Task struct with the new status
  """
  def update_status(task, state, message \\ nil) do
    status = %{
      state: state,
      message: message,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{task | status: status}
  end

  @doc """
  Creates a task status update event.

  ## Parameters
    - task: The task for which to create the status update event
    - final: Whether this is the final update in the stream
    - metadata: Optional metadata to include

  ## Returns
    - A map representing the status update event
  """
  def create_status_update_event(task, final, metadata \\ nil) do
    %{
      id: task.id,
      status: task.status,
      final: final,
      metadata: metadata
    }
  end

  @doc """
  Creates a task artifact update event.

  ## Parameters
    - task: The task for which to create the artifact update event
    - artifact: The artifact to include in the update
    - metadata: Optional metadata to include

  ## Returns
    - A map representing the artifact update event
  """
  def create_artifact_update_event(task, artifact, metadata \\ nil) do
    %{
      id: task.id,
      artifact: artifact,
      metadata: metadata
    }
  end

  @doc """
  Adds an artifact to the task.

  ## Parameters
    - task: The task to update
    - artifact: The artifact to add

  ## Returns
    - An updated Task struct with the new artifact
  """
  def add_artifact(task, artifact) do
    artifacts = (task.artifacts || []) ++ [artifact]
    %{task | artifacts: artifacts}
  end

  @doc """
  Adds a message to the task history.

  ## Parameters
    - task: The task to update
    - message: The message to add to the history

  ## Returns
    - An updated Task struct with the new message in history
  """
  def add_to_history(task, message) do
    history = (task.history || []) ++ [message]
    %{task | history: history}
  end

  @doc """
  Converts a Task struct to a map with camelCase keys for external interfaces.

  ## Parameters
    - task: The task to convert

  ## Returns
    - A map with camelCase keys suitable for external JSON serialization
  """
  def to_external_map(task) do
    %{
      "id" => task.id,
      "sessionId" => task.session_id,
      "status" => task_status_to_external_map(task.status),
      "history" => task.history,
      "artifacts" => task.artifacts,
      "metadata" => task.metadata
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  # Converts a task status map to an external format with camelCase keys and string state
  defp task_status_to_external_map(nil), do: nil

  defp task_status_to_external_map(status) do
    state_str =
      case status.state do
        :"input-required" -> "input-required"
        other -> other |> Atom.to_string()
      end

    %{
      "state" => state_str,
      "message" => status.message,
      "timestamp" => status.timestamp
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  @doc """
  Converts an external map with camelCase keys to a Task struct.

  ## Parameters
    - map: The external map representation to convert

  ## Returns
    - A Task struct
  """
  def from_external_map(map) do
    %__MODULE__{
      id: map["id"],
      session_id: map["sessionId"],
      status: task_status_from_external_map(map["status"]),
      history: map["history"],
      artifacts: map["artifacts"],
      metadata: map["metadata"]
    }
  end

  # Converts an external task status map to an internal format with atom state
  defp task_status_from_external_map(nil), do: nil

  defp task_status_from_external_map(status) do
    state_atom =
      case status["state"] do
        "input-required" -> :"input-required"
        other -> other |> String.to_atom()
      end

    %{
      state: state_atom,
      message: status["message"],
      timestamp: status["timestamp"]
    }
  end
end
