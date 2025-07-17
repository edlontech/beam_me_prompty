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
  @moduledoc section: :llm_integration

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
  def completion(model, messages, llm_params, tools, opts) do
    with {:ok, llm_params} <- AnthropicOpts.validate(model, tools, llm_params),
         {:ok, response} <- call_api(messages, llm_params, opts) do
      {:ok, response}
    else
      {:error, error} ->
        {:error, Errors.to_class(error)}
    end
  end

  defp call_api(messages, llm_params, opts) do
    prepared_data = prepare_messages(messages)

    payload_base = %{
      model: llm_params[:model],
      max_tokens: llm_params[:max_tokens],
      temperature: llm_params[:temperature],
      top_k: llm_params[:top_k],
      top_p: llm_params[:top_p]
    }

    thinking_budget =
      case llm_params[:thinking_budget] do
        nil ->
          %{}

        thinking_budget when is_integer(thinking_budget) and thinking_budget > 0 ->
          %{thinking: %{budget_tokens: thinking_budget, type: "enabled"}}

        _ ->
          raise InvalidRequest.exception(
                  module: __MODULE__,
                  cause: "Invalid thinking budget provided. It must be a positive integer."
                )
      end

    tooling = prepare_anthropic_tools_payload(llm_params[:tools])

    # Add structured response instructions to system prompt if needed
    enhanced_system_prompt = enhance_system_prompt_for_structured_response(
      prepared_data[:system],
      llm_params[:structured_response]
    )

    payload =
      payload_base
      |> Map.put(:messages, prepared_data[:messages])
      |> then(fn p ->
        if enhanced_system_prompt do
          Map.put(p, :system, enhanced_system_prompt)
        else
          p
        end
      end)
      |> Map.merge(tooling)
      |> Map.merge(thinking_budget)
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    client(llm_params, opts)
    |> Req.post(url: "/messages", json: payload)
    |> parse_response(llm_params)
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}, llm_params), do: get_content(body, llm_params)

  defp parse_response({:ok, %Req.Response{status: status, body: body}}, _llm_params)
       when status in 400..499,
       do: {:error, InvalidRequest.exception(module: __MODULE__, cause: body)}

  defp parse_response({:ok, %Req.Response{status: status, body: body}}, _llm_params) when status in 500..599,
    do: {:error, UnexpectedLLMResponse.exception(module: __MODULE__, status: status, cause: body)}

  defp prepare_anthropic_tools_payload(nil), do: %{}

  defp prepare_anthropic_tools_payload(%{function_declarations: declarations})
       when is_list(declarations) and declarations != [] do
    formatted_tools =
      Enum.map(declarations, fn function_declaration ->
        %{
          name: function_declaration.name,
          description: function_declaration.description,
          input_schema: function_declaration.parameters
        }
      end)

    %{tools: formatted_tools}
  end

  defp prepare_anthropic_tools_payload(_), do: %{}

  defp get_content(%{
         "content" => content_list
       }, llm_params) do
    results = Enum.map(content_list, &parse_content(&1, llm_params))

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

  defp parse_content(%{"type" => "tool_use"} = content, _llm_params) do
    {:ok,
     %FunctionCallPart{
       function_call: %{
         id: content["id"],
         name: content["name"],
         arguments: content["input"]
       }
     }}
  end

  defp parse_content(%{"type" => "text"} = content, llm_params) do
    text_content = content["text"]
    
    # Check if structured response is expected and try to parse as JSON
    case llm_params[:structured_response] do
      nil ->
        {:ok, %TextPart{text: text_content}}
      
      _schema ->
        case Jason.decode(text_content) do
          {:ok, parsed_data} ->
            {:ok, %DataPart{data: parsed_data}}
          
          {:error, json_error} ->
            {:error,
             UnexpectedLLMResponse.exception(
               module: __MODULE__,
               cause: "Failed to parse structured response as JSON: #{inspect(json_error)}. Response: #{text_content}"
             )}
        end
    end
  end

  defp parse_content(content, _llm_params) when is_binary(content) do
    {:ok,
     %TextPart{
       text: content
     }}
  end

  defp parse_content(unknown_part, _llm_params) do
    {:error,
     UnexpectedLLMResponse.exception(
       module: __MODULE__,
       cause: "Unknown structure for content part in LLM response: #{inspect(unknown_part)}"
     )}
  end

  defp client(llm_params, opts) do
    Req.new(
      base_url: "https://api.anthropic.com/v1",
      headers: %{
        :"x-api-key" => llm_params[:api_key],
        :"anthropic-version" => llm_params[:version]
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
      |> Enum.join("")
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
            # Unknown roles are skipped
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

  defp enhance_system_prompt_for_structured_response(existing_system_prompt, nil), do: existing_system_prompt

  defp enhance_system_prompt_for_structured_response(existing_system_prompt, schema) do
    schema_json = 
      schema
      |> OpenApiSpex.OpenApi.to_map()
      |> Jason.encode!(pretty: true)
    
    structured_instruction = """
    
    IMPORTANT: You must respond with valid JSON that matches this exact schema:
    
    #{schema_json}
    
    Your response should be ONLY the JSON object, with no additional text, explanations, or formatting.
    """
    
    case existing_system_prompt do
      nil -> String.trim(structured_instruction)
      existing -> existing <> structured_instruction
    end
  end

  defp format_role_messages(role, parts) when is_list(parts) do
    formatted_api_content_blocks =
      parts
      |> Enum.map(&format_dsl_part/1)
      |> Enum.reject(&is_nil/1)

    # If all parts for this role were nil (e.g., unsupported types) or the initial list was empty,
    # then formatted_api_content_blocks will be empty. In this case, we don't create a message
    # for this role, effectively skipping it.
    if Enum.empty?(formatted_api_content_blocks) do
      []
    else
      [%{role: role, content: formatted_api_content_blocks}]
    end
  end
end
