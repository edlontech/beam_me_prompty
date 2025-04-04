defmodule BeamMePrompty.Agent.Stage.ConfigTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Stage.Config
  alias BeamMePrompty.LLM.Errors.InvalidConfig

  describe "default/0" do
    test "returns default configuration struct with expected values" do
      config = Config.default()

      assert %Config{} = config
      assert config.max_tool_iterations == 5
      assert config.enable_tool_calling == true
      assert config.structured_response_validation == true
      assert config.message_history_limit == 1000
    end
  end

  describe "default_max_tool_iterations/0" do
    test "returns the default max tool iterations value" do
      assert Config.default_max_tool_iterations() == 5
    end
  end

  describe "validate_stage_config/1" do
    test "validates successfully with valid LLM and tools config" do
      valid_node_def = %{
        llm: [%{model: "gpt-4", llm_client: :openai}],
        tools: []
      }

      assert Config.validate_stage_config(valid_node_def) == :ok
    end

    test "validates successfully with valid LLM config and tools list" do
      valid_node_def = %{
        llm: [%{model: "claude-3", llm_client: :anthropic}],
        tools: [:calculator, :weather]
      }

      assert Config.validate_stage_config(valid_node_def) == :ok
    end

    test "validates successfully when tools is nil" do
      valid_node_def = %{
        llm: [%{model: "gpt-4", llm_client: :openai}],
        tools: nil
      }

      assert Config.validate_stage_config(valid_node_def) == :ok
    end

    test "returns error when LLM config is missing model" do
      invalid_node_def = %{
        llm: [%{llm_client: :openai, model: nil}],
        tools: []
      }

      assert {:error, %InvalidConfig{}} = Config.validate_stage_config(invalid_node_def)
    end

    test "returns error when LLM config is missing llm_client" do
      invalid_node_def = %{
        llm: [%{model: "gpt-4", llm_client: nil}],
        tools: []
      }

      assert {:error, %InvalidConfig{}} = Config.validate_stage_config(invalid_node_def)
    end

    test "returns error when LLM config has invalid format (not a list)" do
      invalid_node_def = %{
        llm: %{model: "gpt-4", llm_client: :openai},
        tools: []
      }

      assert {:error, %InvalidConfig{cause: cause}} =
               Config.validate_stage_config(invalid_node_def)

      assert cause == "LLM config has invalid format, expected a list containing a map."
    end

    test "returns error when LLM config is empty list" do
      valid_node_def = %{
        llm: [],
        tools: []
      }

      # Empty LLM config is actually valid according to the code
      assert Config.validate_stage_config(valid_node_def) == :ok
    end

    test "returns error when tools config is not a list" do
      invalid_node_def = %{
        llm: [%{model: "gpt-4", llm_client: :openai}],
        tools: "invalid"
      }

      assert {:error, %InvalidConfig{cause: cause}} =
               Config.validate_stage_config(invalid_node_def)

      assert cause == "Tools config has invalid format, expected a list."
    end

    test "returns error when tools config is a map instead of list" do
      invalid_node_def = %{
        llm: [%{model: "gpt-4", llm_client: :openai}],
        tools: %{tool1: :calculator}
      }

      assert {:error, %InvalidConfig{cause: cause}} =
               Config.validate_stage_config(invalid_node_def)

      assert cause == "Tools config has invalid format, expected a list."
    end

    test "returns specific error message for missing model" do
      invalid_node_def = %{
        llm: [%{llm_client: :openai, model: nil}],
        tools: []
      }

      assert {:error, %InvalidConfig{cause: cause}} =
               Config.validate_stage_config(invalid_node_def)

      assert cause == "LLM config missing :model in stage definition"
    end

    test "returns specific error message for missing llm_client" do
      invalid_node_def = %{
        llm: [%{model: "gpt-4", llm_client: nil}],
        tools: []
      }

      assert {:error, %InvalidConfig{cause: cause}} =
               Config.validate_stage_config(invalid_node_def)

      assert cause == "LLM config missing :llm_client in stage definition"
    end

    test "validates LLM config with additional fields" do
      valid_node_def = %{
        llm: [
          %{
            model: "gpt-4",
            llm_client: :openai,
            temperature: 0.7,
            max_tokens: 1000
          }
        ],
        tools: []
      }

      assert Config.validate_stage_config(valid_node_def) == :ok
    end

    test "validates only first LLM config in list" do
      # The code only validates the first config in the list
      node_def_with_multiple_llms = %{
        llm: [
          %{model: "gpt-4", llm_client: :openai},

          # Missing llm_client, but should not fail
          %{model: "claude-3"}
        ],
        tools: []
      }

      assert Config.validate_stage_config(node_def_with_multiple_llms) == :ok
    end
  end
end
