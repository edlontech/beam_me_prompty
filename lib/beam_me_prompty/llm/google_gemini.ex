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

  @impl true
  def completion(model, messages, opts) do
    dbg(messages)

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
    {:ok, get_candidate(body)}
  end

  defp parse_response({:ok, %Req.Response{status: status, body: body}})
       when status in [400..499] do
    {:error, InvalidRequest.exception(module: __MODULE__, cause: body)}
  end

  defp parse_response({:ok, %Req.Response{status: 500, body: body}}) do
    {:error, UnexpectedLLMResponse.exception(module: __MODULE__, status: 500, cause: body)}
  end

  defp get_candidate(%{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]
       }),
       do: text

  defp client(opts) do
    Req.new(
      base_url: "https://generativelanguage.googleapis.com/v1beta",
      params: [key: opts[:key]],
      path_params: [model: opts[:model]],
      path_params_style: :curly,
      plug: opts[:plug]
    )
  end

  defp prepare_messages(keyword_messages) do
    # 1. Process system instructions
    system_parts = Keyword.get(keyword_messages, :system, [])

    system_instruction =
      if Enum.empty?(system_parts) do
        nil
      else
        # Concatenate all system part texts into one string for the single system instruction part
        text = Enum.map_join(system_parts, "", &format_part_to_text/1)
        %{parts: [%{text: text}]}
      end

    # Initialize an empty list for Gemini API contents
    gemini_api_contents = []

    # 2. Process user messages
    user_parts = Keyword.get(keyword_messages, :user, [])

    gemini_api_contents =
      if not Enum.empty?(user_parts) do
        text = Enum.map_join(user_parts, "", &format_part_to_text/1)
        gemini_api_contents ++ [%{role: "user", parts: [%{text: text}]}]
      else
        gemini_api_contents
      end

    # 3. Process assistant messages (if any)
    assistant_parts = Keyword.get(keyword_messages, :assistant, [])

    gemini_api_contents =
      if not Enum.empty?(assistant_parts) do
        text = Enum.map_join(assistant_parts, "", &format_part_to_text/1)
        gemini_api_contents ++ [%{role: "model", parts: [%{text: text}]}]
      else
        gemini_api_contents
      end

    # 4. Build final payload
    payload = %{}

    payload =
      if system_instruction,
        do: Map.put(payload, :system_instruction, system_instruction),
        else: payload

    # Add contents, ensuring it's not an empty list if there were no user/assistant messages,
    # as Gemini API requires `contents` to be non-empty.
    # If gemini_api_contents is empty here, the API call will likely fail, which is expected
    # if no actual content messages (user/assistant) are provided.
    Map.put(payload, :contents, gemini_api_contents)
  end

  # Helper function to format a Dsl.Part into text for the Gemini API
  defp format_part_to_text(part) do
    alias BeamMePrompty.Agent.Dsl.{TextPart, DataPart, FilePart}

    case part do
      %TextPart{text: text_content} ->
        text_content

      %DataPart{data: data_content} ->
        # Serialize map to JSON string. Assumes Jason is available.
        case Jason.encode(data_content) do
          {:ok, json_string} -> json_string
          # Or handle error appropriately, e.g., log and return empty
          {:error, _} -> ""
        end

      %FilePart{} ->
        # Files are ignored in this text-only version.
        # For multimodal, this would need to handle file URIs or bytes.
        ""

      _ ->
        # Unknown part type
        ""
    end
  end
end
