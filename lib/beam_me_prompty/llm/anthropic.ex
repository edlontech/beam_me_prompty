defmodule BeamMePrompty.LLM.Anthropic do
  @behaviour BeamMePrompty.LLM

  alias BeamMePrompty.Errors
  alias BeamMePrompty.LLM.Errors.InvalidRequest
  alias BeamMePrompty.LLM.Errors.UnexpectedLLMResponse
  alias BeamMePrompty.LLM.AnthropicOpts

  @impl true
  def completion(messages, opts) do
    with {:ok, opts} <- AnthropicOpts.validate(opts),
         {:ok, response} <- call_api(messages, opts) do
      {:ok, response}
    else
      {:error, error} ->
        {:error, Errors.to_class(error)}
    end
  end

  defp call_api(messages, opts) do
    {system_prompt, user_messages} = prepare_messages(messages)

    payload = %{
      model: opts[:model],
      max_tokens: opts[:max_output_tokens],
      temperature: opts[:temperature],
      top_k: opts[:top_k],
      top_p: opts[:top_p],
      thinking: %{
        budget_tokens: opts[:thinking_budget_tokens],
        type: if(opts[:thinking], do: "enabled", else: "disabled")
      },
      system: system_prompt,
      messages: user_messages
    }

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

  defp get_content(%{"content" => [%{"text" => text} | _]}), do: text

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

  defp prepare_messages(messages) do
    List.wrap(messages)
    |> Enum.split_with(fn %{role: role} -> role in [:system, "system"] end)
    |> then(fn {system_messages, other_messages} ->
      system_prompt =
        Enum.map_join(system_messages, "\n", fn %{content: content} -> content end)

      user_messages =
        Enum.map(other_messages, fn
          %{role: role, content: content} -> %{role: role, content: content}
          {role, content} -> %{role: role, content: content}
          content -> %{role: "user", content: content}
        end)

      {system_prompt, user_messages}
    end)
  end
end
