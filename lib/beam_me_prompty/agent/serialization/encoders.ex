defmodule BeamMePrompty.Agent.Serialization.Encoders do
  @moduledoc """
  Implements custom JSON encoders for the BeamMePrompty DSL structures.
  """

  alias BeamMePrompty.Agent.Dsl.DataPart
  alias BeamMePrompty.Agent.Dsl.FilePart
  alias BeamMePrompty.Agent.Dsl.FunctionCallPart
  alias BeamMePrompty.Agent.Dsl.FunctionResultPart
  alias BeamMePrompty.Agent.Dsl.LLM
  alias BeamMePrompty.Agent.Dsl.LLMParams
  alias BeamMePrompty.Agent.Dsl.MemorySource
  alias BeamMePrompty.Agent.Dsl.Message
  alias BeamMePrompty.Agent.Dsl.Stage
  alias BeamMePrompty.Agent.Dsl.TextPart
  alias BeamMePrompty.Agent.Dsl.ThoughtPart

  defimpl Jason.Encoder, for: ThoughtPart do
    def encode(part, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.ThoughtPart",
          "type" => part.type,
          "thought_signature" => part.thought_signature
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: TextPart do
    def encode(part, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.TextPart",
          "type" => part.type,
          "text" => part.text
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: DataPart do
    def encode(part, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.DataPart",
          "type" => part.type,
          "data" => part.data
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: FunctionResultPart do
    def encode(part, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.FunctionResultPart",
          "id" => part.id,
          "name" => to_string(part.name),
          "result" => part.result
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: FunctionCallPart do
    def encode(part, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.FunctionCallPart",
          "function_call" => part.function_call
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: Message do
    def encode(message, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.Message",
          "role" => message.role,
          "content" => message.content
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: Stage do
    def encode(stage, opts) do
      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.Stage",
          "name" => stage.name,
          "depends_on" => stage.depends_on,
          "llm" => stage.llm,
          "entrypoint" => stage.entrypoint
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: MemorySource do
    def encode(source, opts) do
      # Convert keyword list to JSON-serializable format
      serialized_opts =
        Enum.map(source.opts, fn {key, value} -> [to_string(key), serialize_value(value)] end)

      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.MemorySource",
          "name" => source.name,
          "description" => source.description,
          "module" => source.module |> Module.split() |> Enum.join("."),
          "opts" => serialized_opts,
          "default" => source.default
        },
        opts
      )
    end

    defp serialize_value(value) when is_atom(value), do: to_string(value)
    defp serialize_value(value), do: value
  end

  defimpl Jason.Encoder, for: FilePart do
    def encode(part, opts) do
      encoded_file =
        part.file
        |> Enum.map(fn
          {:bytes, bytes} when is_binary(bytes) ->
            {"bytes", Base.encode64(bytes)}

          {key, value} ->
            {to_string(key), value}
        end)
        |> Map.new()

      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.FilePart",
          "type" => part.type,
          "file" => encoded_file
        },
        opts
      )
    end
  end

  defimpl Jason.Encoder, for: LLMParams do
    def encode(params, opts) do
      encoded_params = %{
        "__struct__" => "BeamMePrompty.Agent.Dsl.LLMParams",
        "max_tokens" => params.max_tokens,
        "temperature" => params.temperature,
        "top_p" => params.top_p,
        "top_k" => params.top_k,
        "frequency_penalty" => params.frequency_penalty,
        "presence_penalty" => params.presence_penalty,
        "thinking_budget" => params.thinking_budget,
        "structured_response" => params.structured_response,
        "other_params" => params.other_params
      }

      encoded_params =
        case params.api_key do
          fun when is_function(fun) ->
            fun_info = :erlang.fun_info(fun)

            case {fun_info[:module], fun_info[:name], fun_info[:arity]} do
              {module, name, arity}
              when is_atom(module) and is_atom(name) and is_integer(arity) ->
                Map.put(encoded_params, "api_key", %{
                  "__type__" => "mfa",
                  "module" => module |> Module.split() |> Enum.join("."),
                  "function" => to_string(name),
                  "arity" => arity
                })

              _ ->
                # For anonymous functions, we can't serialize them
                Map.put(encoded_params, "api_key", %{
                  "__type__" => "function",
                  "error" => "anonymous_function_not_serializable"
                })
            end

          api_key when is_binary(api_key) ->
            Map.put(encoded_params, "api_key", api_key)

          nil ->
            Map.put(encoded_params, "api_key", nil)
        end

      Jason.Encode.map(encoded_params, opts)
    end
  end

  defimpl Jason.Encoder, for: LLM do
    def encode(llm, opts) do
      llm_client =
        case llm.llm_client do
          {module, client_opts} when is_atom(module) and is_list(client_opts) ->
            serialized_opts =
              Enum.map(client_opts, fn {key, value} ->
                [to_string(key), serialize_value(value)]
              end)

            %{
              "__type__" => "module_with_opts",
              "module" => module |> Module.split() |> Enum.join("."),
              "opts" => serialized_opts
            }

          module when is_atom(module) ->
            module |> Module.split() |> Enum.join(".")
        end

      Jason.Encode.map(
        %{
          "__struct__" => "BeamMePrompty.Agent.Dsl.LLM",
          "model" => llm.model,
          "llm_client" => llm_client,
          "params" => llm.params,
          "messages" => llm.messages,
          "tools" => Enum.map(llm.tools, &to_string/1)
        },
        opts
      )
    end

    defp serialize_value(value) when is_atom(value), do: to_string(value)
    defp serialize_value(value), do: value
  end
end
