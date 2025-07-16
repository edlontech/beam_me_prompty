defmodule BeamMePrompty.Agent.SerializerTest do
  use ExUnit.Case, async: true

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Agent.Serialization
  alias BeamMePrompty.Errors.DeserializationError
  alias BeamMePrompty.Errors.SerializationError

  describe "serialize/1" do
    test "serializes a basic agent definition" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: BeamMePrompty.FakeLlmClient,
              params: %Dsl.LLMParams{
                temperature: 0.5,
                api_key: "test-key"
              },
              messages: [
                %Dsl.Message{
                  role: :system,
                  content: [
                    %Dsl.TextPart{type: :text, text: "You are a helpful assistant."}
                  ]
                }
              ],
              tools: [BeamMePrompty.TestTool]
            },
            entrypoint: false
          }
        ],
        memory: [],
        opts: []
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)

      assert {:ok, _} = Jason.decode(json_string)
    end

    test "serializes agent with memory sources" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: BeamMePrompty.FakeLlmClient,
              params: nil,
              messages: [],
              tools: []
            },
            entrypoint: false
          }
        ],
        memory: [
          %Dsl.MemorySource{
            name: :short_term,
            description: "Short-term memory",
            module: BeamMePrompty.Agent.Memory.ETS,
            opts: [table: :test_table],
            default: true
          }
        ],
        opts: []
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)
    end

    test "serializes function references in API keys" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: BeamMePrompty.FakeLlmClient,
              params: %Dsl.LLMParams{
                api_key: fn -> System.get_env("API_KEY") end
              },
              messages: [],
              tools: []
            },
            entrypoint: false
          }
        ],
        memory: [],
        opts: []
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)
    end

    test "serializes different message part types" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: BeamMePrompty.FakeLlmClient,
              params: nil,
              messages: [
                %Dsl.Message{
                  role: :user,
                  content: [
                    %Dsl.TextPart{type: :text, text: "Hello"},
                    %Dsl.DataPart{type: :data, data: %{key: "value"}},
                    %Dsl.FilePart{
                      type: :file,
                      file: %{
                        name: "test.txt",
                        mime_type: "text/plain",
                        bytes: "test content"
                      }
                    }
                  ]
                }
              ],
              tools: []
            },
            entrypoint: false
          }
        ],
        memory: [],
        opts: []
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)
    end

    test "returns error for invalid input" do
      assert {:error, %SerializationError{}} = Serialization.serialize("invalid")
    end

    test "handles LLM client with options" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: {BeamMePrompty.FakeLlmClient, [timeout: 5000]},
              params: nil,
              messages: [],
              tools: []
            },
            entrypoint: false
          }
        ],
        memory: [],
        opts: []
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert is_binary(json_string)
    end
  end

  describe "deserialize/1" do
    test "deserializes a basic agent definition" do
      json_string = """
      {
        "agent": [
          {
            "__struct__": "BeamMePrompty.Agent.Dsl.Stage",
            "name": "first_stage",
            "depends_on": null,
            "llm": {
              "__struct__": "BeamMePrompty.Agent.Dsl.LLM",
              "model": "test-model",
              "llm_client": "BeamMePrompty.FakeLlmClient",
              "params": {
                "__struct__": "BeamMePrompty.Agent.Dsl.LLMParams",
                "temperature": 0.5,
                "api_key": "test-key",
                "max_tokens": null,
                "top_p": null,
                "top_k": null,
                "frequency_penalty": null,
                "presence_penalty": null,
                "thinking_budget": null,
                "structured_response": null,
                "other_params": null
              },
              "messages": [
                {
                  "__struct__": "BeamMePrompty.Agent.Dsl.Message",
                  "role": "system",
                  "content": [
                    {
                      "__struct__": "BeamMePrompty.Agent.Dsl.TextPart",
                      "type": "text",
                      "text": "You are a helpful assistant."
                    }
                  ]
                }
              ],
              "tools": ["BeamMePrompty.TestTool"]
            },
            "entrypoint": false
          }
        ],
        "memory": [],
        "opts": []
      }
      """

      assert {:ok, agent_definition} = Serialization.deserialize(json_string)
      assert is_map(agent_definition)
      assert %{agent: [stage], memory: [], opts: []} = agent_definition
      assert %Dsl.Stage{name: :first_stage} = stage
    end

    test "deserializes agent with memory sources" do
      json_string = """
      {
        "agent": [],
        "memory": [
          {
            "__struct__": "BeamMePrompty.Agent.Dsl.MemorySource",
            "name": "short_term",
            "description": "Short-term memory",
            "module": "BeamMePrompty.Agent.Memory.ETS",
            "opts": [["table", "test_table"]],
            "default": true
          }
        ],
        "opts": []
      }
      """

      assert {:ok, agent_definition} = Serialization.deserialize(json_string)
      assert %{agent: [], memory: [memory_source], opts: []} = agent_definition

      assert %Dsl.MemorySource{name: :short_term, module: BeamMePrompty.Agent.Memory.ETS} =
               memory_source
    end

    test "deserializes function references in API keys" do
      json_string = """
      {
        "agent": [
          {
            "__struct__": "BeamMePrompty.Agent.Dsl.Stage",
            "name": "first_stage",
            "depends_on": null,
            "llm": {
              "__struct__": "BeamMePrompty.Agent.Dsl.LLM",
              "model": "test-model",
              "llm_client": "BeamMePrompty.FakeLlmClient",
              "params": {
                "__struct__": "BeamMePrompty.Agent.Dsl.LLMParams",
                "api_key": {
                  "__type__": "mfa",
                  "module": "System",
                  "function": "get_env",
                  "arity": 1
                },
                "temperature": null,
                "max_tokens": null,
                "top_p": null,
                "top_k": null,
                "frequency_penalty": null,
                "presence_penalty": null,
                "thinking_budget": null,
                "structured_response": null,
                "other_params": null
              },
              "messages": [],
              "tools": []
            },
            "entrypoint": false
          }
        ],
        "memory": [],
        "opts": []
      }
      """

      assert {:ok, agent_definition} = Serialization.deserialize(json_string)
      assert %{agent: [stage], memory: [], opts: []} = agent_definition
      assert %Dsl.Stage{llm: %Dsl.LLM{params: %Dsl.LLMParams{api_key: api_key}}} = stage
      assert is_function(api_key, 1)
    end

    test "deserializes different message part types" do
      json_string = """
      {
        "agent": [
          {
            "__struct__": "BeamMePrompty.Agent.Dsl.Stage",
            "name": "first_stage",
            "depends_on": null,
            "llm": {
              "__struct__": "BeamMePrompty.Agent.Dsl.LLM",
              "model": "test-model",
              "llm_client": "BeamMePrompty.FakeLlmClient",
              "params": null,
              "messages": [
                {
                  "__struct__": "BeamMePrompty.Agent.Dsl.Message",
                  "role": "user",
                  "content": [
                    {
                      "__struct__": "BeamMePrompty.Agent.Dsl.TextPart",
                      "type": "text",
                      "text": "Hello"
                    },
                    {
                      "__struct__": "BeamMePrompty.Agent.Dsl.DataPart",
                      "type": "data",
                      "data": {"key": "value"}
                    },
                    {
                      "__struct__": "BeamMePrompty.Agent.Dsl.FilePart",
                      "type": "file",
                      "file": {
                        "name": "test.txt",
                        "mime_type": "text/plain",
                        "bytes": "dGVzdCBjb250ZW50"
                      }
                    }
                  ]
                }
              ],
              "tools": []
            },
            "entrypoint": false
          }
        ],
        "memory": [],
        "opts": []
      }
      """

      assert {:ok, agent_definition} = Serialization.deserialize(json_string)
      assert %{agent: [stage], memory: [], opts: []} = agent_definition
      assert %Dsl.Stage{llm: %Dsl.LLM{messages: [message]}} = stage
      assert %Dsl.Message{content: [text_part, data_part, file_part]} = message
      assert %Dsl.TextPart{text: "Hello"} = text_part
      assert %Dsl.DataPart{data: %{"key" => "value"}} = data_part
      assert %Dsl.FilePart{file: %{bytes: "test content"}} = file_part
    end

    test "returns error for invalid JSON" do
      assert {:error, %DeserializationError{}} = Serialization.deserialize("invalid json")
    end

    test "returns error for invalid input type" do
      assert {:error, %DeserializationError{}} = Serialization.deserialize(123)
    end

    test "returns error for unknown function" do
      json_string = """
      {
        "agent": [
          {
            "__struct__": "BeamMePrompty.Agent.Dsl.Stage",
            "name": "first_stage",
            "depends_on": null,
            "llm": {
              "__struct__": "BeamMePrompty.Agent.Dsl.LLM",
              "model": "test-model",
              "llm_client": "BeamMePrompty.FakeLlmClient",
              "params": {
                "__struct__": "BeamMePrompty.Agent.Dsl.LLMParams",
                "api_key": {
                  "__type__": "mfa",
                  "module": "System",
                  "function": "unknown_function",
                  "arity": 1
                },
                "temperature": null,
                "max_tokens": null,
                "top_p": null,
                "top_k": null,
                "frequency_penalty": null,
                "presence_penalty": null,
                "thinking_budget": null,
                "structured_response": null,
                "other_params": null
              },
              "messages": [],
              "tools": []
            },
            "entrypoint": false
          }
        ],
        "memory": [],
        "opts": []
      }
      """

      assert {:error, %DeserializationError{}} = Serialization.deserialize(json_string)
    end
  end

  describe "validate/1" do
    test "validates a valid agent definition" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: BeamMePrompty.FakeLlmClient,
              params: nil,
              messages: [],
              tools: []
            },
            entrypoint: false
          }
        ],
        memory: [
          %Dsl.MemorySource{
            name: :short_term,
            description: "Short-term memory",
            module: BeamMePrompty.Agent.Memory.ETS,
            opts: [],
            default: true
          }
        ],
        opts: []
      }

      assert :ok = Serialization.validate(agent_definition)
    end

    test "returns error for invalid agent structure" do
      assert {:error, %BeamMePrompty.Errors.ValidationError{}} = Serialization.validate("invalid")
    end

    test "returns error for invalid stages" do
      agent_definition = %{
        agent: ["invalid_stage"],
        memory: [],
        opts: []
      }

      assert {:error, %BeamMePrompty.Errors.ValidationError{}} =
               Serialization.validate(agent_definition)
    end

    test "returns error for invalid memory sources" do
      agent_definition = %{
        agent: [],
        memory: ["invalid_memory_source"],
        opts: []
      }

      assert {:error, %BeamMePrompty.Errors.ValidationError{}} =
               Serialization.validate(agent_definition)
    end
  end

  describe "round-trip serialization" do
    test "serializes and deserializes a complete agent definition" do
      agent_definition = %{
        agent: [
          %Dsl.Stage{
            name: :first_stage,
            depends_on: nil,
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: BeamMePrompty.FakeLlmClient,
              params: %Dsl.LLMParams{
                temperature: 0.5,
                max_tokens: 100,
                api_key: "test-key"
              },
              messages: [
                %Dsl.Message{
                  role: :system,
                  content: [
                    %Dsl.TextPart{type: :text, text: "You are a helpful assistant."}
                  ]
                },
                %Dsl.Message{
                  role: :user,
                  content: [
                    %Dsl.TextPart{type: :text, text: "Hello <%= name %>"},
                    %Dsl.DataPart{type: :data, data: %{key: "value"}}
                  ]
                }
              ],
              tools: [BeamMePrompty.TestTool]
            },
            entrypoint: false
          },
          %Dsl.Stage{
            name: :second_stage,
            depends_on: [:first_stage],
            llm: %Dsl.LLM{
              model: "test-model",
              llm_client: {BeamMePrompty.FakeLlmClient, [timeout: 5000]},
              params: nil,
              messages: [],
              tools: []
            },
            entrypoint: false
          }
        ],
        memory: [
          %Dsl.MemorySource{
            name: :short_term,
            description: "Short-term memory",
            module: BeamMePrompty.Agent.Memory.ETS,
            opts: [table: :test_table],
            default: true
          }
        ],
        opts: [session_id: "test-session"]
      }

      assert {:ok, json_string} = Serialization.serialize(agent_definition)
      assert {:ok, deserialized_definition} = Serialization.deserialize(json_string)
      assert :ok = Serialization.validate(deserialized_definition)

      assert %{agent: [stage1, stage2], memory: [memory_source], opts: opts} =
               deserialized_definition

      assert %Dsl.Stage{name: :first_stage, depends_on: nil} = stage1
      assert %Dsl.Stage{name: :second_stage, depends_on: [:first_stage]} = stage2

      assert %Dsl.MemorySource{name: :short_term, module: BeamMePrompty.Agent.Memory.ETS} =
               memory_source

      assert [session_id: "test-session"] = opts
    end
  end
end
