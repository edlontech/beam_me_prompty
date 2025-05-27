defmodule BeamMePrompty.Agent.Stage.Config do
  @moduledoc """
  Configuration management for Stage execution.
  Handles default values, validation, and configuration merging for stage execution parameters.
  """

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
    with {:ok, _} <- validate_llm_config(node_def.llm),
         {:ok, _} <- validate_tools_config(node_def.tools || []) do
      :ok
    else
      error -> {:error, {:invalid_stage_config, error}}
    end
  end

  defp validate_llm_config([config | _rest]) when is_map(config) do
    cond do
      is_nil(config.model) -> {:error, :missing_model}
      is_nil(config.llm_client) -> {:error, :missing_llm_client}
      true -> {:ok, config}
    end
  end

  defp validate_llm_config([]) do
    {:ok, :no_llm_config}
  end

  defp validate_llm_config(_invalid) do
    {:error, :invalid_llm_config_format}
  end

  defp validate_tools_config(tools) when is_list(tools) do
    {:ok, tools}
  end

  defp validate_tools_config(_invalid) do
    {:error, :invalid_tools_config}
  end
end
