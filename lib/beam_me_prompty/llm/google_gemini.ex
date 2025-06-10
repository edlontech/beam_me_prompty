defmodule BeamMePrompty.LLM.GoogleGemini do
  @moduledoc """
  Interface to Google's Gemini API services for the BeamMePrompty application.

  This module implements the `BeamMePrompty.LLM` behaviour and provides functionality
  to interact with Google's Gemini API for language model completions. It handles
  formatting of messages, tools, and options to match Gemini's API requirements,
  and processes the responses accordingly.

  ## Features

  * Supports text completion with Google's Gemini models
  * Handles message formatting between BeamMePrompty's DSL and Gemini's expected format
  * Supports system instructions, user messages, and assistant messages
  * Provides function calling capabilities
  * Supports image inputs via base64 encoding
  * Manages API authentication and request configuration
  * Handles error cases and converts them to appropriate error types

  ## Usage

  ```elixir
  alias BeamMePrompty.LLM.GoogleGemini

  # Basic usage
  {:ok, response} = GoogleGemini.completion(
    "gemini-pro",
    [user: [%TextPart{text: "Hello, how are you?"}]],
    nil,
    [key: "your-api-key", temperature: 0.7, max_output_tokens: 1000]
  )

  # With system instruction and function calling
  {:ok, response} = GoogleGemini.completion(
    "gemini-pro",
    [
      system: [%TextPart{text: "You are a helpful assistant."}],
      user: [%TextPart{text: "Please help me calculate 2+2"}]
    ],
    %{
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
    },
    [key: "your-api-key", temperature: 0.7, max_output_tokens: 1000]
  )

  # With image input
  {:ok, response} = GoogleGemini.completion(
    "gemini-pro-vision",
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

  ## Response Schema

  You can also specify a response schema to get structured JSON responses:

  ```elixir
  {:ok, response} = GoogleGemini.completion(
    "gemini-pro",
    [user: [%TextPart{text: "List 3 planets in the solar system"}]],
    nil,
    [
      key: "your-api-key",
      response_schema: %{
        type: "object",
        properties: %{
          planets: %{
            type: "array",
            items: %{type: "string"}
          }
        }
      }
    ]
  )
  ```

  See `BeamMePrompty.LLM.GoogleGeminiOpts` for available configuration options.
  """
  @moduledoc section: :llm_integration

  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse
  alias BeamMePrompty.LLM.GoogleGeminiOpts

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FilePart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.TextPart
  alias BeamMePrompty.Agent.Dsl.ThoughtPart

  @impl true
  def completion(model, messages, llm_params, tools, opts) do
    with {:ok, llm_params} <- GoogleGeminiOpts.validate(model, tools, llm_params),
         {:ok, response} <- call_api(messages, llm_params, opts) do
      {:ok, response}
    else
      {:error, error} ->
        {:error, Errors.to_class(error)}
    end
  end

  defp call_api(messages, llm_params, opts) do
    generation_config =
      %{
        top_k: llm_params[:top_k],
        top_p: llm_params[:top_p],
        temperature: llm_params[:temperature],
        max_output_tokens: llm_params[:max_output_tokens],
        thinking_config: llm_params[:thinking_config],
        response_schema: llm_params[:response_schema]
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    generation_config =
      if llm_params[:response_schema] do
        Map.put(generation_config, :response_mime_type, "application/json")
      else
        generation_config
      end

    base_payload = Map.merge(prepare_messages(messages), %{generation_config: generation_config})

    payload =
      if tools_config = llm_params[:tools] do
        Map.put(base_payload, :tools, [Map.new(tools_config)])
      else
        base_payload
      end

    client(llm_params, opts)
    |> Req.post(url: "/models/{model}:generateContent", json: payload)
    |> parse_response()
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}), do: get_candidate(body)

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

  defp get_candidate_content(%{"text" => text_content}) when is_binary(text_content),
    do: {:ok, %TextPart{text: text_content}}

  defp get_candidate_content(%{
         "functionCall" => %{
           "args" => args,
           "name" => name
         }
       }) do
    {:ok,
     %FunctionCallPart{
       function_call: %{
         arguments: args,
         name: name
       }
     }}
  end

  defp get_candidate_content(%{"thoughtSignature" => signature}) do
    {:ok, %ThoughtPart{thought_signature: signature}}
  end

  defp get_candidate_content(unknown_part) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause: "Unknown structure for content part in LLM response: #{inspect(unknown_part)}"
     )}
  end

  defp get_candidate(%{
         "candidates" => [
           %{"content" => %{"parts" => parts}} | _
         ]
       }) do
    results = Enum.map(parts, &get_candidate_content/1)

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

  defp get_candidate(%{"candidates" => []} = body) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause: "LLM response contains no candidates. Body: #{inspect(body)}"
     )}
  end

  defp get_candidate(body) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause:
         "Malformed or missing 'candidates' list/structure in LLM response. Body: #{inspect(body)}"
     )}
  end

  defp client(llm_params, opts) do
    Req.new(
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      params: [key: llm_params[:key]],
      path_params: [model: llm_params[:model]],
      path_params_style: :curly,
      plug:
        case opts[:http_adapter] do
          nil -> nil
          adapter -> {adapter, __MODULE__}
        end
    )
  end

  # credo:disable-for-next-line
  defp format_dsl_part_to_gemini_api_part(part) do
    case part do
      %TextPart{text: text_content} when is_binary(text_content) ->
        %{text: text_content}

      %DataPart{data: data_content} ->
        Jason.encode(data_content)
        |> case do
          {:ok, json_string} -> %{text: json_string}
          {:error, _} -> nil
        end

      %FilePart{file: %{bytes: bytes, mime_type: mime_type}}
      when not is_nil(bytes) and not is_nil(mime_type) ->
        %{inlineData: %{mimeType: mime_type, data: Base.encode64(bytes)}}

      %FunctionResultPart{id: id, name: name, result: result} ->
        %{
          function_response: %{
            id: id,
            name: name,
            response: %{result: result}
          }
        }

      %FunctionCallPart{function_call: call} ->
        %{
          function_call: %{
            id: Map.get(call, :id),
            name: Map.get(call, :name),
            args: Map.get(call, :arguments)
          }
        }

      _ ->
        nil
    end
  end

  defp prepare_messages(keyword_messages) do
    gemini_system_api_parts =
      Keyword.get(keyword_messages, :system, [])
      |> Enum.map(&format_dsl_part_to_gemini_api_part/1)
      |> Enum.reject(&is_nil(&1))

    system_instruction =
      case gemini_system_api_parts do
        [] -> nil
        parts_list -> %{parts: parts_list}
      end

    gemini_api_contents =
      keyword_messages
      |> Enum.filter(fn {role, _} -> role in [:user, :assistant] end)
      |> Enum.map(fn
        {:user, parts} ->
          api_parts =
            parts
            |> Enum.map(&format_dsl_part_to_gemini_api_part/1)
            |> Enum.reject(&is_nil(&1))

          if Enum.empty?(api_parts), do: nil, else: %{role: "user", parts: api_parts}

        {:assistant, parts} ->
          api_parts =
            parts
            |> Enum.map(&format_dsl_part_to_gemini_api_part/1)
            |> Enum.reject(&is_nil(&1))

          if Enum.empty?(api_parts), do: nil, else: %{role: "model", parts: api_parts}
      end)
      |> Enum.reject(&is_nil(&1))

    if system_instruction do
      %{system_instruction: system_instruction, contents: gemini_api_contents}
    else
      %{contents: gemini_api_contents}
    end
  end
end
