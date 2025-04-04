defmodule BeamMePrompty.Agent.Stage.Config do
  @moduledoc """
  Configuration management for Stage execution.
  Handles default values, validation, and configuration merging for stage execution parameters.
  """
  @moduledoc section: :agent_stage_and_execution

  defstruct [
    :max_tool_iterations,
    :enable_tool_calling,
    :structured_response_validation,
    :message_history_limit
  ]

  @default_max_tool_iterations 5
  @default_enable_tool_calling true
  @default_structured_response_validation true
  @default_message_history_limit 1000

  alias BeamMePrompty.LLM.Errors

  @doc """
  Returns the default configuration for stage execution.
  """
  def default do
    %__MODULE__{
      max_tool_iterations: @default_max_tool_iterations,
      enable_tool_calling: @default_enable_tool_calling,
      structured_response_validation: @default_structured_response_validation,
      message_history_limit: @default_message_history_limit
    }
  end

  @doc """
  Returns the default maximum tool iterations.
  """
  def default_max_tool_iterations, do: @default_max_tool_iterations

  @doc """
  Validates stage configuration.
  """
  def validate_stage_config(node_def) do
    with {:ok, _llm_validation_result} <- validate_llm_config(node_def.llm),
         {:ok, _tools_validation_result} <- validate_tools_config(node_def.tools || []) do
      :ok
    end
  end

  defp validate_llm_config([config | _rest]) when is_map(config) do
    cond do
      is_nil(config.model) ->
        {:error,
         Errors.InvalidConfig.exception(
           module: __MODULE__,
           cause: "LLM config missing :model in stage definition"
         )}

      is_nil(config.llm_client) ->
        {:error,
         Errors.InvalidConfig.exception(
           module: __MODULE__,
           cause: "LLM config missing :llm_client in stage definition"
         )}

      true ->
        {:ok, config}
    end
  end

  defp validate_llm_config([]) do
    {:ok, :no_llm_config_present}
  end

  defp validate_llm_config(_invalid) do
    {:error,
     Errors.InvalidConfig.exception(
       module: __MODULE__,
       cause: "LLM config has invalid format, expected a list containing a map."
     )}
  end

  defp validate_tools_config(tools) when is_list(tools) do
    # Currently, tools are just a list, more specific validation can be added if needed.
    # For now, if it's a list, it's considered structurally valid at this level.
    {:ok, tools}
  end

  defp validate_tools_config(_invalid) do
    {:error,
     Errors.InvalidConfig.exception(
       module: __MODULE__,
       cause: "Tools config has invalid format, expected a list."
     )}
  end
end
