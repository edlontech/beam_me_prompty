defmodule BeamMePrompty.LLM.GoogleGemini do
  @moduledoc """
  Google Gemini API adapter implementing the BeamMePrompty.LLM behaviour.
  Constructs requests, communicates with the Gemini endpoint via Req,
  and parses responses into plain text or structured output for pipelines.
  """
  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse
  alias BeamMePrompty.LLM.GoogleGeminiOpts

  @impl true
  def completion(messages, opts) do
    with {:ok, opts} <- GoogleGeminiOpts.validate(opts),
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

  defp prepare_messages(prompt) do
    case List.wrap(prompt) do
      [message] ->
        [text_content(message)]

      [maybe_system | messages] ->
        [text_content(maybe_system, :system) | Enum.map(messages, &text_content/1)]
    end
    |> Enum.split_with(fn %{role: role} -> role == [:system, "system"] end)
    |> then(fn {system_messages, other_messages} ->
      merged_system_message =
        %{
          role: :system,
          parts: [
            %{
              text: Enum.map_join(system_messages, "\n", fn %{parts: [%{text: text}]} -> text end)
            }
          ]
        }

      %{
        system_instruction: merged_system_message,
        contents: other_messages
      }
    end)
  end

  defp text_content(text, default_role \\ :user)
  defp text_content(%{role: role, content: text}, _), do: %{role: role, parts: [%{text: text}]}
  defp text_content({role, text}, _), do: %{role: role, parts: [%{text: text}]}
  defp text_content(text, role), do: %{role: role, parts: [%{text: text}]}
end
