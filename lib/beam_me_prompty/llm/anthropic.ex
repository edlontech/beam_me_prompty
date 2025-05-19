defmodule BeamMePrompty.LLM.Anthropic do
  @moduledoc """
  Interface to Anthropic's LLM API services for the BeamMePrompty application.

  This module implements the `BeamMePrompty.LLM` behaviour and provides functionality
  to interact with Anthropic's API for language model completions, including Claude models.
  It handles formatting of messages, tools, and options to match Anthropic's API requirements,
  and processes the responses accordingly.

  ## Features

  * Supports text completion with Anthropic's models
  * Handles message formatting between BeamMePrompty's DSL and Anthropic's expected format
  * Supports system prompts, user messages, and assistant messages
  * Provides tools/function calling capabilities
  * Supports image inputs via base64 encoding
  * Manages API authentication and request configuration
  * Handles error cases and converts them to appropriate error types

  ## Usage

  ```elixir
  alias BeamMePrompty.LLM.Anthropic

  # Basic usage
  {:ok, response} = Anthropic.completion(
    "claude-3-opus-20240229",
    [user: [%TextPart{text: "Hello, how are you?"}]],
    nil,
    [key: "your-api-key", temperature: 0.7, max_tokens: 1000]
  )

  # With system prompt and tools
  {:ok, response} = Anthropic.completion(
    "claude-3-opus-20240229",
    [
      system: [%TextPart{text: "You are a helpful assistant."}],
      user: [%TextPart{text: "Please help me calculate 2+2"}]
    ],
    [
      function_declarations: [
        %{
          name: "calculate",
          description: "Calculate a math expression",
          parameters: %{
            type: "object",
            properties: %{
              expression: %{type: "string", description: "Math expression to calculate"}
            },
            required: ["expression"]
          }
        }
      ]
    ],
    [key: "your-api-key", temperature: 0.7, max_tokens: 1000]
  )
  ```

  The module supports various content types through the DSL:
  - `TextPart` - For regular text messages
  - `DataPart` - For structured JSON data
  - `FilePart` - For images and other binary content
  - `FunctionCallPart` - For initiating tool/function calls
  - `FunctionResultPart` - For handling function results

  See `BeamMePrompty.LLM.AnthropicOpts` for available configuration options.
  """

  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FilePart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.TextPart

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.AnthropicOpts
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse

  @impl true
  def completion(model, messages, tools, opts) do
    with {:ok, opts} <- AnthropicOpts.validate(model, tools, opts),
         {:ok, response} <- call_api(messages, opts) do
      {:ok, response}
    else
      {:error, error} ->
        {:error, Errors.to_class(error)}
    end
  end

  defp call_api(messages, opts) do
    prepared_data = prepare_messages(messages)

    payload_base = %{
      model: opts[:model],
      max_tokens: opts[:max_tokens],
      temperature: opts[:temperature],
      top_k: opts[:top_k],
      top_p: opts[:top_p]
    }

    thinking_budget =
      if opts[:thinking] do
        %{budget_tokens: opts[:thinking_budget_tokens], type: "enabled"}
      else
        %{}
      end

    tooling = tool_choice(opts[:tools])

    payload =
      payload_base
      |> Map.put(:messages, prepared_data[:messages])
      |> then(fn p ->
        if system_prompt = prepared_data[:system] do
          Map.put(p, :system, system_prompt)
        else
          p
        end
      end)
      |> Map.merge(tooling)
      |> Map.merge(thinking_budget)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    client(opts)
    |> Req.post(url: "/messages", json: payload)
    |> parse_response()
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:ok, get_content(body)}
  end

  defp parse_response({:ok, %Req.Response{status: status, body: body}})
       when status in 400..499,
       do: {:error, InvalidRequest.exception(module: __MODULE__, cause: body)}

  defp parse_response({:ok, %Req.Response{status: 500, body: body}}),
    do: {:error, UnexpectedLLMResponse.exception(module: __MODULE__, status: 500, cause: body)}

  defp tool_choice(nil), do: %{}

  defp tool_choice(tools) do
    tools =
      Enum.map(tools[:function_declarations], fn function_declaration ->
        %{
          name: function_declaration.name,
          description: function_declaration.description,
          input_schema: function_declaration.parameters
        }
      end)

    %{tools: tools}
  end

  defp get_content(%{"content" => content_list}), do: Enum.map(content_list, &parse_content/1)

  defp parse_content(%{"type" => "tool_use"} = content) do
    %{
      function_call: %{
        id: content["id"],
        name: content["name"],
        arguments: content["input"]
      }
    }
  end

  defp parse_content(%{"type" => "tool_result"} = content) do
    %{
      function_result: %{
        tool_use_id: content["tool_use_id"],
        name: content["name"],
        content: content["content"]
      }
    }
  end

  defp parse_content(content), do: content

  defp client(opts) do
    Req.new(
      base_url: "https://api.anthropic.com/v1",
      headers: %{
        :"x-api-key" => opts[:key],
        :"anthropic-version" => opts[:version]
      },
      plug:
        case opts[:http_adapter] do
          nil -> nil
          adapter -> {adapter, __MODULE__}
        end
    )
  end

  # credo:disable-for-next-line
  defp format_dsl_part(part) do
    case part do
      %TextPart{text: text_content} when is_binary(text_content) ->
        %{type: "text", text: text_content}

      %DataPart{data: data_content} ->
        Jason.encode(data_content)
        |> case do
          {:ok, json_string} -> %{type: "text", text: json_string}
          {:error, _} -> nil
        end

      %FilePart{file: %{bytes: bytes, mime_type: mime_type}}
      when not is_nil(bytes) and not is_nil(mime_type) ->
        %{
          type: "image",
          source: %{
            type: "base64",
            media_type: mime_type,
            data: Base.encode64(bytes)
          }
        }

      %FunctionResultPart{id: id, result: result} ->
        %{
          type: "tool_result",
          tool_use_id: id,
          content: result
        }

      %FunctionCallPart{function_call: call} ->
        %{
          type: "tool_use",
          id: Map.get(call, :id),
          name: Map.get(call, :name),
          input: Map.get(call, :arguments)
        }

      _ ->
        nil
    end
  end

  defp prepare_messages(keyword_messages) do
    system_dsl_parts = Keyword.get(keyword_messages, :system, [])

    system_string =
      system_dsl_parts
      |> Enum.map(fn
        %TextPart{text: text_content} ->
          text_content

        %DataPart{data: data_content} ->
          Jason.encode(data_content) |> elem(1)

        _ ->
          ""
      end)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
      |> case do
        "" -> nil
        s -> s
      end

    messages_list =
      keyword_messages
      |> Enum.reject(fn {k, _v} -> k == :system end)
      |> Enum.flat_map(fn {role, parts} ->
        api_role =
          case role do
            :user -> "user"
            :assistant -> "assistant"
            _ -> nil
          end

        if is_nil(api_role) do
          []
        else
          format_role_messages(api_role, parts)
        end
      end)

    output = %{messages: messages_list}

    if system_string do
      Map.put(output, :system, system_string)
    else
      output
    end
  end

  defp format_role_messages(role, parts) when is_list(parts) do
    formatted_parts =
      Enum.flat_map(parts, fn
        parts_list when is_list(parts_list) ->
          Enum.map(parts_list, &format_dsl_part/1) |> Enum.reject(&is_nil/1)

        part ->
          case format_dsl_part(part) do
            nil -> []
            formatted -> [formatted]
          end
      end)

    if Enum.empty?(formatted_parts) do
      []
    else
      [%{role: role, content: formatted_parts}]
    end
  end
end
