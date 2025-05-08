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
    field :content, TextPart.t() | FilePart.t() | DataPart.t()
  end

  typedstruct module: LLMParams do
    field :max_tokens, integer() | nil
    field :temperature, float() | nil
    field :top_p, float() | nil
    field :top_k, integer() | nil
    field :frequency_penalty, float() | nil
    field :presence_penalty, float() | nil
  end

  typedstruct module: LLM do
    field :model, String.t()
    field :llm_client, module()
    field :params, LLMParams.t() | nil
  end

  typedstruct module: Stage do
    field :name, atom()
    field :depends_on, list(String.t()) | nil
    field :llm, LLM.t() | nil
    field :messages, list(Message.t())
  end

  @message_entity %Spark.Dsl.Entity{
    name: :message,
    args: [:role, :content],
    describe: "Defines a message in the stage.",
    target: Message,
    schema: [
      role: [
        type: :atom,
        doc: "Role of the message sender."
      ],
      content: [
        type: :any,
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
        type: :integer,
        doc: "Maximum number of tokens to generate."
      ],
      temperature: [
        type: :float,
        doc: "Sampling temperature."
      ],
      top_p: [
        type: :float,
        doc: "Nucleus sampling parameter."
      ],
      top_k: [
        type: :integer,
        doc: "Top-k sampling parameter."
      ],
      frequency_penalty: [
        type: :float,
        doc: "Frequency penalty."
      ],
      presence_penalty: [
        type: :float,
        doc: "Presence penalty."
      ]
    ]
  }

  @llm_entity %Spark.Dsl.Entity{
    name: :llm,
    args: [:model, :llm_client],
    describe: "Defines the LLM model and client.",
    target: LLM,
    entities: [
      params: [@llm_params_entity]
    ],
    schema: [
      model: [
        type: :string
      ],
      llm_client: [
        type: :module,
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
      llm: [@llm_entity],
      messages: [@message_entity]
    ],
    schema: [
      name: [
        type: :atom,
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
    sections: [@agent_section]
end
