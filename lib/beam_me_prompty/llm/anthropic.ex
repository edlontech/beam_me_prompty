defmodule BeamMePrompty.LLM.Anthropic do
  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Agent.Dsl.{TextPart, DataPart, FilePart}
  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse
  alias BeamMePrompty.LLM.AnthropicOpts

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
       when status in [400..499] do
    {:error, InvalidRequest.exception(module: __MODULE__, cause: body)}
  end

  defp parse_response({:ok, %Req.Response{status: 500, body: body}}) do
    {:error, UnexpectedLLMResponse.exception(module: __MODULE__, status: 500, cause: body)}
  end

  defp tool_choice(nil), do: %{}

  defp tool_choice(tools) do
    tools =
      Enum.map(tools.function_declarations, fn function_declaration ->
        %{
          name: function_declaration.name,
          description: function_declaration.description,
          input_schema: function_declaration.parameters
        }
      end)

    %{tools: tools}
  end

  defp get_content(%{"content" => content_list}) do
    case Enum.find(content_list, &(&1["type"] == "text")) do
      %{"text" => text} -> text
      _ -> ""
    end
  end

  defp client(opts) do
    Req.new(
      base_url: "https://api.anthropic.com/v1",
      headers: %{
        :"x-api-key" => opts[:key],
        :"anthropic-version" => opts[:version]
      },
      plug: opts[:plug]
    )
  end

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

    roles_to_process = [
      {:user, "user"},
      {:assistant, "assistant"}
    ]

    messages_list =
      Enum.flat_map(roles_to_process, fn {dsl_role_key, api_role_name} ->
        dsl_parts_for_role = Keyword.get(keyword_messages, dsl_role_key, [])

        formatted_parts_for_role =
          dsl_parts_for_role
          |> Enum.map(&format_dsl_part/1)
          |> Enum.reject(&is_nil(&1))

        if Enum.empty?(formatted_parts_for_role) do
          []
        else
          [%{role: api_role_name, content: formatted_parts_for_role}]
        end
      end)

    output = %{messages: messages_list}

    if system_string do
      Map.put(output, :system, system_string)
    else
      output
    end
  end
end
