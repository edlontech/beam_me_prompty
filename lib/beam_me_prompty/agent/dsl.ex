defmodule BeamMePrompty.Agent.Dsl do
  use TypedStruct

  @type part_type() :: :text | :file | :data

  @type role() :: :user | :assistant | :system

  typedstruct module: TextPart do
    @derive Jason.Encoder
    field :type, :text
    field :text, String.t()
  end

  typedstruct module: FilePart do
    @derive Jason.Encoder
    field :type, :file

    field :file, %{
      optional(:name) => String.t(),
      optional(:mime_type) => String.t(),
      optional(:bytes) => binary(),
      optional(:uri) => String.t()
    }
  end

  typedstruct module: DataPart do
    @derive Jason.Encoder
    field :type, :data
    field :data, map()
  end

  typedstruct module: Message do
    field :role, BeamMePrompty.Agent.Dsl.role()
    field :content, list(TextPart.t() | FilePart.t() | DataPart.t())
  end

  typedstruct module: Tool do
    field :module, module()
    field :name, String.t()
    field :description, String.t()
    field :parameters, OpenApiSpex.Schema.t()
  end

  typedstruct module: LLMParams do
    field :max_tokens, integer() | nil
    field :temperature, float() | nil
    field :top_p, float() | nil
    field :top_k, integer() | nil
    field :frequency_penalty, float() | nil
    field :presence_penalty, float() | nil
    field :thinking_budget, integer() | nil
    field :structured_response, OpenApiSpex.Schema.t() | nil
    field :api_key, String.t() | nil
    field :other_params, map() | nil
  end

  typedstruct module: LLM do
    field :model, String.t()
    field :llm_client, {module(), keyword()}
    field :params, LLMParams.t() | nil
    field :messages, list(Message.t())
    field :tools, list(Tool.t())
  end

  typedstruct module: Stage do
    field :name, atom()
    field :depends_on, list(String.t()) | nil
    field :llm, LLM.t() | nil
  end

  @tool_entity %Spark.Dsl.Entity{
    name: :tool,
    target: Tool,
    describe: "Defines a tool that the agent can use.",
    schema: [
      name: [
        type: :string,
        required: true,
        doc: "Name of the tool."
      ],
      module: [
        type: :module,
        required: true,
        doc: "Module implementing the tool."
      ],
      description: [
        type: :string,
        required: true,
        doc: "Description of the tool."
      ],
      parameters: [
        type: {:struct, OpenApiSpex.Schema},
        required: true,
        doc: "Parameters for the tool."
      ]
    ]
  }

  @message_entity %Spark.Dsl.Entity{
    name: :message,
    args: [:role, :content],
    describe: "Defines a message in the stage.",
    target: Message,
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
      messages: [@message_entity],
      tools: [@tool_entity]
    ],
    schema: [
      model: [
        required: true,
        type: :string
      ],
      llm_client: [
        type: {:behaviour, BeamMePrompty.LLM},
        required: true,
        doc: "The LLM client module to use."
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
      ]
    ]
  }

  @agent_section %Spark.Dsl.Section{
    name: :agent,
    entities: [
      @stage_entity
    ],
    schema: [],
    describe: "Defines an LLM agent with one or more stages."
  }

  use Spark.Dsl.Extension,
    sections: [@agent_section],
    verifiers: [
      BeamMePrompty.Agent.Dsl.Verifiers.HasStages,
      BeamMePrompty.Agent.Dsl.Verifiers.StagesAreValid
    ]
end
