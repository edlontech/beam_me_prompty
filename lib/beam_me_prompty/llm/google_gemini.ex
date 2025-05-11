defmodule BeamMePrompty.LLM.GoogleGemini do
  @moduledoc """
  Google Gemini API adapter implementing the BeamMePrompty.LLM behaviour.
  Constructs requests, communicates with the Gemini endpoint via Req,
  and parses responses into plain text or structured output for agents.
  """
  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse
  alias BeamMePrompty.LLM.GoogleGeminiOpts
  alias BeamMePrompty.Agent.Dsl.{TextPart, DataPart, FilePart}

  @impl true
  def completion(model, messages, opts) do
    with {:ok, opts} <- GoogleGeminiOpts.validate(model, opts),
         {:ok, response} <- call_api(messages, opts) do
      {:ok, response}
    else
      {:error, error} ->
        {:error, Errors.to_class(error)}
    end
  end

  defp call_api(messages, opts) do
    generation_config =
      %{
        top_k: opts[:top_k],
        top_p: opts[:top_p],
        temperature: opts[:temperature],
        max_output_tokens: opts[:max_output_tokens],
        thinking_budget: opts[:thinking_budget],
        response_schema: opts[:response_schema]
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    generation_config =
      if opts[:response_schema] do
        %{
          generation_config
          | response_mime_type: "application/json"
        }
      else
        generation_config
      end

    payload = Map.merge(prepare_messages(messages), %{generation_config: generation_config})

    client(opts)
    |> Req.post(url: "/models/{model}:generateContent", json: payload)
    |> parse_response()
  end

  defp parse_response({:ok, %Req.Response{status: 200, body: body}}) do
    get_candidate(body)
  end

  defp parse_response({:ok, %Req.Response{status: status, body: body}})
       when status in [400..499] do
    {:error, InvalidRequest.exception(module: __MODULE__, cause: body)}
  end

  defp parse_response({:ok, %Req.Response{status: 500, body: body}}) do
    {:error, UnexpectedLLMResponse.exception(module: __MODULE__, status: 500, cause: body)}
  end

  defp get_candidate_content(%{"text" => text_content}) when is_binary(text_content) do
    {:ok, text_content}
  end

  defp get_candidate_content(part_map) when is_map(part_map) do
    {:ok, part_map}
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
           %{"content" => %{"parts" => [first_part | _]}} | _
         ]
       }) do
    get_candidate_content(first_part)
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

  defp client(opts) do
    Req.new(
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      params: [key: opts[:key]],
      path_params: [model: opts[:model]],
      path_params_style: :curly,
      plug: opts[:plug]
    )
  end

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

    roles_to_process = [
      {:user, "user"},
      {:assistant, "model"}
    ]

    gemini_api_contents =
      Enum.flat_map(roles_to_process, fn {dsl_role_key, api_role_name} ->
        dsl_parts_for_role = Keyword.get(keyword_messages, dsl_role_key, [])

        api_parts_for_role =
          dsl_parts_for_role
          |> Enum.map(&format_dsl_part_to_gemini_api_part/1)
          |> Enum.reject(&is_nil(&1))

        if Enum.empty?(api_parts_for_role) do
          []
        else
          [%{role: api_role_name, parts: api_parts_for_role}]
        end
      end)

    if system_instruction do
      %{system_instruction: system_instruction, contents: gemini_api_contents}
    else
      %{contents: gemini_api_contents}
    end
  end
end
