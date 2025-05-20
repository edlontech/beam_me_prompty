defmodule BeamMePrompty.Tool do
  @moduledoc """
  Defines the behaviour and structure for tools that can be executed by Language Models (LLMs).

  A `BeamMePrompty.Tool` module acts as an interface that LLMs can understand and interact with
  to perform specific actions or retrieve information. Modules implementing this behaviour
  must provide a `tool_info/0` function describing the tool (name, description, parameters)
  and a `run/1` function to execute the tool's logic.

  ## Examples

  A simple tool module might look like this:

  ```elixir
  defmodule MyTool do
    use BeamMePrompty.Tool,
      name: :my_tool,
      description: "A simple example tool",
      parameters: %{
        type: :object,
        properties: %{
          input_string: %{
            type: :string,
            description: "The string to process"
          }
        },
        required: [:input_string]
      }

    @impl BeamMePrompty.Tool
    def run(%{"input_string" => input}) do
      {:ok, "Processed: \#{input}"}
    end

    def run(args) do
      {:error, "Invalid arguments: \#{inspect(args)}"}
    end
  end
  ```
  """

  use TypedStruct

  alias BeamMePrompty.LLM.Errors.ToolError

  typedstruct do
    field :name, atom()
    field :description, String.t()
    field :parameters, map()
    field :module, module()
  end

  @doc """
  Execute the tool with the provided arguments.

  ## Parameters

    - `args`: A map containing the arguments to be passed to the tool.

  ## Returns

    - `{:ok, result}`: A tuple containing the result of the tool execution.
    - `{:error, reason}`: A tuple containing an error reason if the execution fails.
  """
  @callback run(map()) :: {:ok, map() | String.t()} | {:error, ToolError.t()}

  @doc """
  Required informations about the tool, this is used by LLMs to know how to call the tool.

  ## Returns

    - `%Tool{}`: A struct containing the tool's name, description, parameters, and OpenAPI schema.
  """
  @callback tool_info() :: __MODULE__.t()

  defmacro __using__(opts) do
    if not Keyword.has_key?(opts, :name) do
      raise CompileError, description: "BeamMePrompty.Tool requires a :name option"
    end

    if not Keyword.has_key?(opts, :description) do
      raise CompileError, description: "BeamMePrompty.Tool requires a :description option"
    end

    if not Keyword.has_key?(opts, :parameters) do
      raise CompileError, description: "BeamMePrompty.Tool requires a :parameters option"
    end

    quote bind_quoted: [
            name: opts[:name],
            description: opts[:description],
            parameters: Macro.escape(opts[:parameters])
          ] do
      @behaviour BeamMePrompty.Tool

      alias BeamMePrompty.Tool

      @impl BeamMePrompty.Tool
      def tool_info do
        %Tool{
          name: unquote(name),
          description: unquote(description),
          parameters: unquote(parameters),
          module: __MODULE__
        }
      end

      defoverridable tool_info: 0
    end
  end
end
