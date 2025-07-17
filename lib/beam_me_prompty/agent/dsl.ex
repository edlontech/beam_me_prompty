defmodule BeamMePrompty.Agent.Dsl do
  @moduledoc """
  A Domain-Specific Language (DSL) for defining intelligent agents in BeamMePrompty.

  This module, built upon the `Spark.Dsl` framework, provides a declarative way to 
  configure complex, multi-stage agents. It allows you to define how an agent
  interacts with Large Language Models (LLMs), utilizes tools, manages memory,
  and orchestrates its workflow.

  ## Core Philosophy

  The DSL is designed to be declarative: you define *what* the agent's structure and 
  capabilities are, and BeamMePrompty handles the *how* of executing the defined
  workflow, managing dependencies, and interacting with LLMs and tools.

  ## Key Building Blocks

  The DSL is structured around several key components:

  *   `agent do ... end`: The top-level block that encapsulates the entire agent definition.
      It can define global agent configurations like versioning and statefulness.

  *   `stage :stage_name do ... end`: Defines a distinct processing step or phase within 
      the agent's workflow. 
      *   Stages can have dependencies on each other using `depends_on [:another_stage]`, 
          forming a Directed Acyclic Graph (DAG) that dictates the execution order.
      *   A stage can be marked as an `entrypoint` for agents designed to resume or be
          triggered at specific points.

  *   `llm "model-name", YourLlmClientModule do ... end`: Configures an LLM interaction 
      within a stage.
      *   You specify the `model-name` (e.g., "gemini-2.0-flash", "claude-3-opus-20240229") 
          and the `YourLlmClientModule` (e.g., `BeamMePrompty.LLM.GoogleGemini`).
      *   `with_params do ... end`: Allows setting LLM-specific parameters like 
          `temperature`, `max_tokens`, `api_key`, etc. API keys can be provided directly
          or via a function for dynamic retrieval.
      *   `tools [YourToolModule]`: Lists the tools (modules implementing 
          `BeamMePrompty.Tool`) available to the LLM for this interaction.
      *   `message :role, [content_parts]` (see below): Defines the messages to be sent to 
          the LLM.

  *   `message :role, [content_parts]` (inside `llm` block): Defines the content of 
      interactions with the LLM.
      *   `:role` can be `:system` (instructions for the LLM), `:user` (input to the LLM),
          or `:assistant` (previous LLM responses, useful for conversational context).
      *   `[content_parts]` is a list of one or more message parts (see "Message Content Types").
      *   Text parts support EEx templating (`<%= ... %>`) to interpolate data from 
          global inputs or the results of previous stages (e.g., `<%= first_stage.result %>`).

  *   `memory_source :source_name, YourMemoryModule do ... end` (inside a top-level `memory do ... end` block): 
      Configures a memory backend for the agent.
      *   `:source_name` is an atom identifying this memory store.
      *   `YourMemoryModule` is a module implementing the `BeamMePrompty.Agent.Memory` behaviour.
      *   `description` provides context for the LLM on when to use this source.
      *   `opts` allow passing configuration specific to the memory module.
      *   `default: true` marks this as the default memory source if multiple are defined.
      Memory tools (`:memory_store`, `:memory_retrieve`, etc.) are automatically injected 
      into LLM-enabled stages if memory sources are configured.

  ## Message Content Types

  Messages exchanged with the LLM are composed of one or more "parts":

  *   `TextPart`: Represents plain text. Use `text_part("your text")`.
  *   `FilePart`: For including file-based content, typically images. Requires `name`, 
      `mime_type`, and either `bytes` or a `uri`. Use `file_part(%{...})`.
  *   `DataPart`: Allows sending structured map data, usually serialized to JSON for the LLM. 
      Use `data_part(%{your: "data"})`.
  *   `FunctionResultPart`: Represents the output returned by a tool after the LLM invoked it.
      Used by the framework to feed tool results back to the LLM. Use `function_result_part(id, name, result)`.
  *   `FunctionCallPart`: Represents a request from the LLM to invoke a tool. 
      Use `function_call_part(id, name, arguments)`.
  *   `ThoughtPart`: Can represent an LLM's intermediate "thoughts" or reasoning steps if supported
      by the model. Use `thought_part("signature")`.

  These parts are typically constructed using helper functions from `BeamMePrompty.Agent.Dsl.Part`.

  ## How It Works

  When an agent is defined using this DSL:
  1.  `Spark.Dsl` parses and validates the structure.
  2.  Transformers (like `InjectMemoryTools`) can automatically modify the DSL structure, 
      for example, by adding standard memory tools to stages if a memory source is defined.
  3.  Verifiers (like `HasStages`, `StagesAreValid`) ensure the agent definition is sound.
  4.  The resulting configuration is used by `BeamMePrompty.Agent.Executor` to build a DAG 
      and manage the execution flow, calling LLMs and tools as defined in each stage.
  """
  @moduledoc section: :dsl
  use TypedStruct

  @typedoc """
  When defining a message part, this type indicates the kind of content it holds.
  """
  @type part_type() :: :text | :file | :data | :function_result | :function_call

  @typedoc """
  When defining a message, this type indicates the role of the sender.
  """
  @type role() :: :user | :assistant | :system

  alias BeamMePrompty.Tool

  typedstruct module: ThoughtPart do
    @moduledoc """
    Defines a Thought Part of a LLM Message.
    """
    @moduledoc section: :dsl

    field :type, atom(), default: :thought
    field :thought_signature, String.t()
  end

  typedstruct module: TextPart do
    @moduledoc """
    Represents a Text Part of a LLM Message.
    """
    @moduledoc section: :dsl

    field :type, atom(), default: :text
    field :text, String.t()
  end

  typedstruct module: FilePart do
    @moduledoc """
    Represents a File Part of a LLM Message.
    """
    @moduledoc section: :dsl

    field :type, atom(), default: :file

    field :file, %{
      optional(:name) => String.t(),
      optional(:mime_type) => String.t(),
      optional(:bytes) => binary(),
      optional(:uri) => String.t()
    }
  end

  typedstruct module: DataPart do
    @moduledoc """
    Represents a Data Part of a LLM Message.

    Data parts can be any serializable map structure, they are usually sent as a plain text json-string to the LLM.
    """
    @moduledoc section: :dsl

    field :type, atom(), default: :data
    field :data, map()
  end

  typedstruct module: FunctionResultPart do
    @moduledoc """
    Represents the result of a function call in a LLM Message.
    """
    @moduledoc section: :dsl

    field :id, String.t() | nil
    field :name, String.t() | atom()
    field :result, any()
  end

  typedstruct module: FunctionCallPart do
    @moduledoc """
    Represents a LLM function call request.
    """
    @moduledoc section: :dsl

    field :function_call, %{
      optional(:id) => String.t(),
      optional(:name) => String.t(),
      optional(:arguments) => map()
    }
  end

  typedstruct module: Message do
    @moduledoc """
    Represents a message in the LLM conversation history.
    """
    @moduledoc section: :dsl

    alias BeamMePrompty.Agent.Dsl

    field :role, Dsl.role()
    field :content, list(Dsl.Part.parts())
  end

  typedstruct module: LLMParams do
    @moduledoc """
    Represents the parameters for configuring an LLM model.
    """
    @moduledoc section: :dsl

    field :max_tokens, integer() | nil
    field :temperature, float() | nil
    field :top_p, float() | nil
    field :top_k, integer() | nil
    field :frequency_penalty, float() | nil
    field :presence_penalty, float() | nil
    field :thinking_budget, integer() | nil
    field :structured_response, map() | nil
    field :api_key, String.t() | function() | nil
    field :other_params, map() | nil
  end

  typedstruct module: LLM do
    @moduledoc """
    Represents a Language Model (LLM) configuration within a stage.
    """
    @moduledoc section: :dsl

    field :model, String.t()
    field :llm_client, {module(), keyword()} | module()
    field :params, LLMParams.t() | nil
    field :messages, list(Message.t())
    field :tools, list(Tool.t()), default: []
  end

  typedstruct module: Stage do
    @moduledoc """
    Represents a processing stage in the LLM agent.
    """
    @moduledoc section: :dsl

    field :name, atom()
    field :depends_on, list(atom()) | nil
    field :llm, LLM.t() | nil
    field :entrypoint, boolean(), default: false
  end

  typedstruct module: MemorySource do
    @moduledoc """
    Represents a memory source configuration for an agent.
    """
    @moduledoc section: :dsl

    field :name, atom()
    field :description, String.t()
    field :module, module()
    field :opts, keyword(), default: []
    field :default, boolean(), default: false
  end

  @message_entity %Spark.Dsl.Entity{
    name: :message,
    args: [:role, :content],
    describe: "Defines a message in the stage.",
    target: Message,
    imports: [
      BeamMePrompty.Agent.Dsl.Part
    ],
    schema: [
      role: [
        type: :atom,
        required: true,
        doc: "Role of the message sender."
      ],
      content: [
        type: {:list, :any},
        required: true,
        doc: "Content of the message."
      ]
    ]
  }

  @llm_params_entity %Spark.Dsl.Entity{
    name: :with_params,
    describe: "Defines the parameters for the LLM.",
    target: LLMParams,
    schema: [
      max_tokens: [
        type: :non_neg_integer,
        doc: "Maximum number of tokens to generate."
      ],
      temperature: [
        type:
          {:custom, BeamMePrompty.Commons.CustomValidations, :validate_float_range, [0.0, 2.0]},
        doc: "Sampling temperature."
      ],
      top_p: [
        type:
          {:custom, BeamMePrompty.Commons.CustomValidations, :validate_float_range, [0.0, 1.0]},
        doc: "Nucleus sampling parameter."
      ],
      top_k: [
        type: :non_neg_integer,
        doc: "Top-k sampling parameter."
      ],
      frequency_penalty: [
        type:
          {:custom, BeamMePrompty.Commons.CustomValidations, :validate_float_range, [-2.0, 2.0]},
        doc: "Frequency penalty."
      ],
      thinking_budget: [
        type: :non_neg_integer,
        doc: "Maximum number of tokens for the thinking budget."
      ],
      presence_penalty: [
        type:
          {:custom, BeamMePrompty.Commons.CustomValidations, :validate_float_range, [-2.0, 2.0]},
        doc: "Presence penalty."
      ],
      structured_response: [
        type: {:struct, OpenApiSpex.Schema},
        doc: "Schema that the LLM should follow for structured responses"
      ],
      api_key: [
        type: {:or, [:string, {:fun, [], :string}]},
        doc: "API key for the LLM client."
      ],
      other_params: [
        type: :map,
        doc: "Other parameters for the LLM client."
      ]
    ]
  }

  @llm_entity %Spark.Dsl.Entity{
    name: :llm,
    args: [:model, :llm_client],
    describe: "Defines the LLM model and client.",
    target: LLM,
    entities: [
      params: [@llm_params_entity],
      messages: [@message_entity]
    ],
    schema: [
      model: [
        required: true,
        type: :string
      ],
      tools: [
        required: false,
        type: {:list, :any}
      ],
      llm_client: [
        type:
          {:or,
           [
             {:behaviour, BeamMePrompty.LLM},
             {:tuple, [{:behaviour, BeamMePrompty.LLM}, :keyword_list]}
           ]},
        required: true,
        doc: "The LLM client module to use."
      ]
    ]
  }

  @memory_source_entity %Spark.Dsl.Entity{
    name: :memory_source,
    args: [:name, :module],
    describe: "Defines a memory source for the agent.",
    target: MemorySource,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Name of the memory source."
      ],
      module: [
        type: {:behaviour, BeamMePrompty.Agent.Memory},
        required: true,
        doc: "The memory implementation module."
      ],
      description: [
        type: :string,
        required: true,
        doc:
          "Thoughtful description of this memory tool, this should describe to the LLM when to use this source."
      ],
      opts: [
        type: :keyword_list,
        default: [],
        doc: "Options to pass to the memory module."
      ],
      default: [
        type: :boolean,
        default: false,
        doc: "Whether this is the default memory source."
      ]
    ]
  }

  @stage_entity %Spark.Dsl.Entity{
    name: :stage,
    args: [:name],
    describe: "Defines a stage in the agent.",
    target: Stage,
    entities: [
      llm: [@llm_entity]
    ],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "Name of the stage."
      ],
      depends_on: [
        type: {:list, :atom},
        default: [],
        doc: "List of stages that this stage depends on."
      ],
      entrypoint: [
        type: :boolean,
        default: false,
        doc: "Whether this stage can be used as an entrypoint for the agent."
      ]
    ]
  }

  @agent_section %Spark.Dsl.Section{
    name: :agent,
    entities: [
      @stage_entity
    ],
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "A human-readable name for the agent."
      ],
      agent_state: [
        type: {:one_of, [:stateful, :stateless]},
        default: :stateless,
        doc: "Indicates whether the agent maintains a state across calls"
      ],
      version: [
        type: :string,
        default: "0.0.1",
        doc: "Version of the agent configuration"
      ]
    ],
    describe: "Defines an LLM agent with one or more stages."
  }

  @memory_section %Spark.Dsl.Section{
    name: :memory,
    entities: [
      @memory_source_entity
    ],
    schema: [],
    describe: "Defines an LLM agent with one or more stages."
  }

  use Spark.Dsl.Extension,
    sections: [
      @agent_section,
      @memory_section
    ],
    transformers: [
      BeamMePrompty.Agent.Dsl.Transformers.InjectMemoryTools
    ]

  defmodule Part do
    @moduledoc """
    Helpers for creating different parts of messages in the DSL.
    """
    @moduledoc section: :dsl

    @type parts() ::
            TextPart.t()
            | FilePart.t()
            | DataPart.t()
            | FunctionResultPart.t()
            | FunctionCallPart.t()
            | ThoughtPart.t()

    defguard is_part(part)
             when is_struct(part, TextPart) or
                    is_struct(part, FilePart) or
                    is_struct(part, DataPart) or
                    is_struct(part, FunctionResultPart) or
                    is_struct(part, FunctionCallPart) or
                    is_struct(part, ThoughtPart)

    @spec text_part(String.t()) :: TextPart.t()
    def text_part(text) do
      %TextPart{
        type: :text,
        text: text
      }
    end

    @spec data_part(map()) :: DataPart.t()
    def data_part(data) do
      %DataPart{
        type: :data,
        data: data
      }
    end

    @spec file_part(%{
            required(:name) => String.t(),
            required(:mime_type) => String.t(),
            optional(:bytes) => binary(),
            optional(:uri) => String.t()
          }) :: FilePart.t()
    def file_part(%{
          name: name,
          mime_type: mime_type,
          bytes: bytes,
          uri: uri
        }) do
      %FilePart{
        type: :file,
        file: %{
          name: name,
          mime_type: mime_type,
          bytes: bytes,
          uri: uri
        }
      }
    end

    @spec function_result_part(String.t() | nil, String.t() | atom(), any()) ::
            FunctionResultPart.t()
    def function_result_part(id, name, result) do
      %FunctionResultPart{
        id: id,
        name: name,
        result: result
      }
    end

    @spec function_call_part(String.t() | nil, String.t() | atom(), map()) ::
            FunctionCallPart.t()
    def function_call_part(id, name, arguments) do
      %FunctionCallPart{
        function_call: %{
          id: id,
          name: name,
          arguments: arguments
        }
      }
    end

    @spec thought_part(String.t()) :: ThoughtPart.t()
    def thought_part(thought_signature) do
      %ThoughtPart{
        thought_signature: thought_signature
      }
    end
  end
end
