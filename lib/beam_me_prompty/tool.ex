defmodule BeamMePrompty.Tool do
  use TypedStruct

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
  @callback run(map()) :: {:ok, map() | String.t()} | {:error, any()}

  @doc """
  Required informations about the tool, this is used by LLMs to know how to call the tool.

  ## Returns

    - `%Tool{}`: A struct containing the tool's name, description, parameters, and OpenAPI schema.
  """
  @callback tool_info() :: __MODULE__.t()

  defmacro __using__(opts) do
    quote bind_quoted: [
            name: opts[:name],
            description: opts[:description],
            parameters: opts[:parameters]
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
