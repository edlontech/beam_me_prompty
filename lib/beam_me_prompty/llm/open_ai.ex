defmodule BeamMePrompty.LLM.OpenAI do
  @moduledoc """
  Interface to OpenAI's API services for the BeamMePrompty application.

  This module implements the `BeamMePrompty.LLM` behaviour and provides functionality
  to interact with OpenAI's API for language model completions. It handles
  formatting of messages, tools, and options to match OpenAI's API requirements,
  and processes the responses accordingly.

  ## Features

  * Supports text completion with OpenAI's GPT models
  * Handles message formatting between BeamMePrompty's DSL and OpenAI's expected format
  * Supports system messages, user messages, and assistant messages
  * Provides function calling capabilities
  * Supports image inputs via base64 encoding or URLs
  * Manages API authentication and request configuration
  * Handles error cases and converts them to appropriate error types
  * Supports structured JSON responses

  ## Usage

  ```elixir
  alias BeamMePrompty.LLM.OpenAI

  # Basic usage
  {:ok, response} = OpenAI.completion(
    "gpt-4o",
    [user: [%TextPart{text: "Hello, how are you?"}]],
    nil,
    [key: "your-api-key", temperature: 0.7, max_tokens: 1000]
  )

  # With system instruction and function calling
  {:ok, response} = OpenAI.completion(
    "gpt-4o",
    [
      system: [%TextPart{text: "You are a helpful assistant."}],
      user: [%TextPart{text: "Please help me calculate 2+2"}]
    ],
    [
      %{
        type: "function",
        function: %{
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
      }
    ],
    [key: "your-api-key", temperature: 0.7, max_tokens: 1000]
  )

  # With image input
  {:ok, response} = OpenAI.completion(
    "gpt-4o",
    [
      user: [
        %TextPart{text: "Describe this image:"},
        %FilePart{file: %{bytes: image_bytes, mime_type: "image/jpeg"}}
      ]
    ],
    nil,
    [key: "your-api-key"]
  )
  ```

  The module supports various content types through the DSL:
  - `TextPart` - For regular text messages
  - `DataPart` - For structured JSON data
  - `FilePart` - For images and other binary content
  - `FunctionCallPart` - For initiating function calls
  - `FunctionResultPart` - For handling function results

  ## Response Format

  You can also specify a response format to get structured JSON responses:

  ```elixir
  {:ok, response} = OpenAI.completion(
    "gpt-4o",
    [user: [%TextPart{text: "List 3 planets in the solar system"}]],
    nil,
    [
      key: "your-api-key",
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "planets_list",
          schema: %{
            type: "object",
            properties: %{
              planets: %{
                type: "array",
                items: %{type: "string"}
              }
            }
          }
        }
      }
    ]
  )
  ```

  See `BeamMePrompty.LLM.OpenAIOpts` for available configuration options.
  """
  @moduledoc section: :llm_integration

  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse
  alias BeamMePrompty.LLM.OpenAIOpts

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FilePart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.TextPart

  @impl true
  def completion(model, messages, llm_params, tools, opts) do
    with {:ok, llm_params} <- OpenAIOpts.validate(model, tools, llm_params),
         {:ok, response} <- call_api(messages, llm_params, opts) do
      {:ok, response}
    else
      {:error, error} ->
        {:error, Errors.to_class(error)}
    end
  end

  defp call_api(messages, llm_params, opts) do
    payload =
      Map.reject(
        %{
          model: llm_params[:model],
          messages: prepare_messages(messages),
          max_tokens: llm_params[:max_tokens],
          temperature: llm_params[:temperature],
          top_p: llm_params[:top_p],
          frequency_penalty: llm_params[:frequency_penalty],
          presence_penalty: llm_params[:presence_penalty],
          response_format: llm_params[:response_format],
          seed: llm_params[:seed],
          tools: llm_params[:tools],
          tool_choice: llm_params[:tool_choice]
        },
        fn {_k, v} -> is_nil(v) end
      )

    client(llm_params, opts)
    |> Req.post(url: "/chat/completions", json: payload)
    |> parse_response()
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}), do: get_choice(body)

  defp parse_response({:ok, %Req.Response{status: status, body: body}})
       when status in 400..499,
       do: {:error, InvalidRequest.exception(module: __MODULE__, cause: body)}

  defp parse_response({:ok, %Req.Response{status: status, body: body}}) when status in 500..599,
    do: {:error, UnexpectedLLMResponse.exception(module: __MODULE__, status: status, cause: body)}

  defp parse_response({:error, err}),
    do:
      {:error,
       UnexpectedLLMResponse.exception(
         module: __MODULE__,
         cause: err
       )}

  defp get_message_content(%{"content" => content}) when is_binary(content) and content != "",
    do: {:ok, %TextPart{text: content}}

  defp get_message_content(%{"content" => nil, "tool_calls" => tool_calls})
       when is_list(tool_calls) do
    results = Enum.map(tool_calls, &parse_tool_call/1)

    {successes, errors} =
      Enum.reduce(results, {[], []}, fn
        {:ok, content}, {acc_success, acc_errors} -> {[content | acc_success], acc_errors}
        {:error, error}, {acc_success, acc_errors} -> {acc_success, [error | acc_errors]}
      end)

    case errors do
      [] -> {:ok, Enum.reverse(successes)}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  defp get_message_content(unknown_message) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause: "Unknown structure for message in LLM response: #{inspect(unknown_message)}"
     )}
  end

  defp parse_tool_call(%{
         "id" => id,
         "type" => "function",
         "function" => %{"name" => name, "arguments" => arguments}
       }) do
    case Jason.decode(arguments) do
      {:ok, parsed_args} ->
        {:ok,
         %FunctionCallPart{
           function_call: %{
             id: id,
             name: name,
             arguments: parsed_args
           }
         }}

      {:error, _} ->
        {:error,
         UnexpectedLLMResponse.exception(
           module: __MODULE__,
           cause: "Invalid JSON in function call arguments: #{arguments}"
         )}
    end
  end

  defp parse_tool_call(unknown_tool_call) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause: "Unknown tool call structure: #{inspect(unknown_tool_call)}"
     )}
  end

  defp get_choice(%{
         "choices" => [
           %{"message" => message} | _
         ]
       }) do
    case get_message_content(message) do
      {:ok, content} when is_list(content) -> {:ok, content}
      {:ok, content} -> {:ok, [content]}
      {:error, error} -> {:error, error}
    end
  end

  defp get_choice(%{"choices" => []} = body) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause: "LLM response contains no choices. Body: #{inspect(body)}"
     )}
  end

  defp get_choice(body) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause:
         "Malformed or missing 'choices' list/structure in LLM response. Body: #{inspect(body)}"
     )}
  end

  defp client(llm_params, opts) do
    Req.new(
      base_url: "https://api.openai.com/v1",
      auth: {:bearer, llm_params[:key]},
      headers: [
        {"content-type", "application/json"}
      ],
      plug:
        case opts[:http_adapter] do
          nil -> nil
          adapter -> {adapter, __MODULE__}
        end
    )
  end

  # credo:disable-for-next-line
  defp format_dsl_part_to_openai_content(part) do
    case part do
      %TextPart{text: text_content} when is_binary(text_content) ->
        %{type: "text", text: text_content}

      %DataPart{data: data_content} ->
        case Jason.encode(data_content) do
          {:ok, json_string} -> %{type: "text", text: json_string}
          {:error, _} -> nil
        end

      %FilePart{file: %{bytes: bytes, mime_type: mime_type}}
      when not is_nil(bytes) and not is_nil(mime_type) and
             mime_type in ["image/jpeg", "image/png", "image/gif", "image/webp"] ->
        %{
          type: "image_url",
          image_url: %{
            url: "data:#{mime_type};base64,#{Base.encode64(bytes)}"
          }
        }

      _ ->
        nil
    end
  end

  defp format_dsl_parts_to_openai_message(parts, role) do
    content_items =
      parts
      |> Enum.map(&format_dsl_part_to_openai_content/1)
      |> Enum.reject(&is_nil(&1))

    case {content_items, parts} do
      {[], _} ->
        nil

      {[%{type: "text", text: text}], _} ->
        %{role: role, content: text}

      {content_items, _} when length(content_items) > 1 ->
        %{role: role, content: content_items}

      {[content_item], _} ->
        %{role: role, content: [content_item]}
    end
  end

  defp format_function_parts_to_openai_message(parts) do
    tool_calls =
      parts
      |> Enum.map(fn
        %FunctionCallPart{function_call: call} ->
          %{
            id: Map.get(call, :id, generate_tool_call_id()),
            type: "function",
            function: %{
              name: Map.get(call, :name),
              arguments: Jason.encode!(Map.get(call, :arguments, %{}))
            }
          }

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil(&1))

    case tool_calls do
      [] -> nil
      _ -> %{role: "assistant", content: nil, tool_calls: tool_calls}
    end
  end

  defp format_function_result_parts_to_openai_messages(parts) do
    parts
    |> Enum.map(fn
      %FunctionResultPart{id: id, name: name, result: result} ->
        content =
          case result do
            result when is_binary(result) -> result
            result -> Jason.encode!(result)
          end

        %{
          role: "tool",
          tool_call_id: id,
          name: name,
          content: content
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil(&1))
  end

  defp prepare_messages(keyword_messages) do
    Enum.flat_map(keyword_messages, fn
      {:system, parts} ->
        case format_dsl_parts_to_openai_message(parts, "system") do
          nil -> []
          message -> [message]
        end

      {:user, parts} ->
        function_result_parts = Enum.filter(parts, &match?(%FunctionResultPart{}, &1))

        if length(function_result_parts) > 0 do
          format_function_result_parts_to_openai_messages(function_result_parts)
        else
          case format_dsl_parts_to_openai_message(parts, "user") do
            nil -> []
            message -> [message]
          end
        end

      {:assistant, parts} ->
        {function_call_parts, other_parts} =
          Enum.split_with(parts, fn
            %FunctionCallPart{} -> true
            _ -> false
          end)

        {_function_result_parts, content_parts} =
          Enum.split_with(other_parts, fn
            %FunctionResultPart{} -> true
            _ -> false
          end)

        messages = []

        messages =
          case format_dsl_parts_to_openai_message(content_parts, "assistant") do
            nil -> messages
            message -> [message | messages]
          end

        messages =
          case format_function_parts_to_openai_message(function_call_parts) do
            nil -> messages
            message -> [message | messages]
          end

        Enum.reverse(messages)
    end)
  end

  defp generate_tool_call_id do
    "call_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end
end
