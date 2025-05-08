defmodule BeamMePrompty.Agent.Dsl do
  use TypedStruct

  @type part_type() :: :text | :file | :data

  @type role() :: :user | :assistant | :system

  typedstruct module: TextPart do
    field :type, :text
    field :text, String.t()
  end

  typedstruct module: FilePart do
    field :type, :file

    field :file, %{
      optional(:name) => String.t(),
      optional(:mime_type) => String.t(),
      optional(:bytes) => binary(),
      optional(:uri) => String.t()
    }
  end

  typedstruct module: DataPart do
    field :type, :data
    field :data, map()
  end

  typedstruct module: Message do
    field :role, BeamMePrompty.Agent.Dsl.role()
    field :content, list(TextPart.t() | FilePart.t() | DataPart.t())
  end

  typedstruct module: LLMParams do
    field :max_tokens, integer() | nil
    field :temperature, float() | nil
    field :top_p, float() | nil
    field :top_k, integer() | nil
    field :frequency_penalty, float() | nil
    field :presence_penalty, float() | nil
    field :structured_response, OpenApiSpex.Schema.t() | nil
  end

  typedstruct module: LLM do
    field :model, String.t()
    field :llm_client, module()
    field :params, LLMParams.t() | nil
    field :messages, list(Message.t())
  end

  typedstruct module: Stage do
    field :name, atom()
    field :depends_on, list(String.t()) | nil
    field :llm, LLM.t() | nil
  end

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
      presence_penalty: [
        type:
          {:custom, BeamMePrompty.Commons.CustomValidations, :validate_float_range, [-2.0, 2.0]},
        doc: "Presence penalty."
      ],
      structured_response: [
        type: {:struct, OpenApiSpex.Schema},
        doc: "Schema that the LLM should follow for structured responses"
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
      llm_client: [
        type: :module,
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
