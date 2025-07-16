defmodule BeamMePrompty.Agent.Serialization.Deserializer do
  @moduledoc """
  Deserializes agent definitions from JSON back to working DSL structures.

  This module handles the reconstruction of agent definitions from their serialized
  JSON representation, including safe module resolution and function reconstruction.
  """

  alias BeamMePrompty.Agent.Dsl
  alias BeamMePrompty.Errors.DeserializationError

  def deserialize(json_string) when is_binary(json_string) do
    with {:ok, raw_data} <- Jason.decode(json_string),
         {:ok, agent_definition} <- deserialize_agent(raw_data) do
      {:ok, agent_definition}
    else
      {:error, reason} ->
        {:error, DeserializationError.exception(cause: reason)}
    end
  end

  def deserialize(input) do
    {:error, DeserializationError.exception(cause: %{message: "Invalid input", input: input})}
  end

  defp deserialize_agent(%{
         "agent" => stages,
         "memory" => memory_sources,
         "agent_config" => agent_config
       }) do
    with {:ok, deserialized_stages} <- deserialize_stages(stages),
         {:ok, deserialized_memory} <- deserialize_memory_sources(memory_sources),
         {:ok, deserialized_agent_config} <- deserialize_agent_config(agent_config) do
      {:ok,
       %{
         agent: deserialized_stages,
         memory: deserialized_memory,
         agent_config: deserialized_agent_config
       }}
    end
  end

  defp deserialize_agent(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid agent structure", input: input})}
  end

  defp deserialize_stages(stages) when is_list(stages) do
    stages
    |> Enum.reduce_while({:ok, []}, fn stage_data, {:ok, acc} ->
      case deserialize_stage(stage_data) do
        {:ok, stage} -> {:cont, {:ok, [stage | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, stages} -> {:ok, Enum.reverse(stages)}
      error -> error
    end
  end

  defp deserialize_stages(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid stages structure", input: input})}
  end

  defp deserialize_stage(%{"__struct__" => "BeamMePrompty.Agent.Dsl.Stage"} = stage_data) do
    with {:ok, name} <- deserialize_atom(stage_data["name"]),
         {:ok, depends_on} <- deserialize_depends_on(stage_data["depends_on"]),
         {:ok, llm} <- deserialize_llm(stage_data["llm"]) do
      {:ok,
       %Dsl.Stage{
         name: name,
         depends_on: depends_on,
         llm: llm,
         entrypoint: stage_data["entrypoint"] || false
       }}
    end
  end

  defp deserialize_stage(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid stage structure", input: input})}
  end

  defp deserialize_llm(nil), do: {:ok, nil}
  defp deserialize_llm([]), do: {:ok, []}

  defp deserialize_llm(llm_data) when is_list(llm_data) do
    llm_data
    |> Enum.reduce_while({:ok, []}, fn llm_item, {:ok, acc} ->
      case deserialize_llm_item(llm_item) do
        {:ok, llm} -> {:cont, {:ok, [llm | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, llms} -> {:ok, Enum.reverse(llms)}
      error -> error
    end
  end

  defp deserialize_llm(llm_data) when is_map(llm_data) do
    deserialize_llm_item(llm_data)
  end

  defp deserialize_llm(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid LLM structure", input: input})}
  end

  defp deserialize_llm_item(%{"__struct__" => "BeamMePrompty.Agent.Dsl.LLM"} = llm_data) do
    with {:ok, llm_client} <- deserialize_llm_client(llm_data["llm_client"]),
         {:ok, params} <- deserialize_llm_params(llm_data["params"]),
         {:ok, messages} <- deserialize_messages(llm_data["messages"]),
         {:ok, tools} <- deserialize_tools(llm_data["tools"]) do
      {:ok,
       %Dsl.LLM{
         model: llm_data["model"],
         llm_client: llm_client,
         params: params,
         messages: messages,
         tools: tools
       }}
    end
  end

  defp deserialize_llm_item(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid LLM item structure", input: input})}
  end

  defp deserialize_llm_client(%{
         "__type__" => "module_with_opts",
         "module" => module_str,
         "opts" => opts
       }) do
    with {:ok, module} <- resolve_module(module_str),
         {:ok, deserialized_opts} <- deserialize_keyword_list(opts) do
      {:ok, {module, deserialized_opts}}
    end
  end

  defp deserialize_llm_client(%{"__type__" => "tuple", "elements" => elements}) do
    case deserialize_tuple_elements(elements) do
      {:ok, [module, opts]} when is_atom(module) and is_list(opts) -> {:ok, {module, opts}}
      {:ok, deserialized_elements} -> {:ok, List.to_tuple(deserialized_elements)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deserialize_llm_client(module_str) when is_binary(module_str) do
    resolve_module(module_str)
  end

  defp deserialize_llm_client(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid LLM client structure", input: input}
     )}
  end

  defp deserialize_llm_params(nil), do: {:ok, nil}
  defp deserialize_llm_params([]), do: {:ok, []}

  defp deserialize_llm_params(params_data) when is_list(params_data) do
    params_data
    |> Enum.reduce_while({:ok, []}, fn param_item, {:ok, acc} ->
      case deserialize_llm_params_item(param_item) do
        {:ok, params} -> {:cont, {:ok, [params | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, params_list} -> {:ok, Enum.reverse(params_list)}
      error -> error
    end
  end

  defp deserialize_llm_params(params_data) when is_map(params_data) do
    deserialize_llm_params_item(params_data)
  end

  defp deserialize_llm_params(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid LLM params structure", input: input}
     )}
  end

  defp deserialize_llm_params_item(
         %{"__struct__" => "BeamMePrompty.Agent.Dsl.LLMParams"} = params_data
       ) do
    with {:ok, api_key} <- deserialize_api_key(params_data["api_key"]) do
      {:ok,
       %Dsl.LLMParams{
         max_tokens: params_data["max_tokens"],
         temperature: params_data["temperature"],
         top_p: params_data["top_p"],
         top_k: params_data["top_k"],
         frequency_penalty: params_data["frequency_penalty"],
         presence_penalty: params_data["presence_penalty"],
         thinking_budget: params_data["thinking_budget"],
         structured_response: params_data["structured_response"],
         api_key: api_key,
         other_params: params_data["other_params"]
       }}
    end
  end

  defp deserialize_llm_params_item(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid LLM params item structure", input: input}
     )}
  end

  defp deserialize_api_key(nil), do: {:ok, nil}
  defp deserialize_api_key(api_key) when is_binary(api_key), do: {:ok, api_key}

  defp deserialize_api_key(%{
         "__type__" => "mfa",
         "module" => module_str,
         "function" => function_str,
         "arity" => arity
       }) do
    with {:ok, module} <- resolve_function_module(module_str),
         {:ok, function} <- resolve_function_name(function_str) do
      case arity do
        0 -> {:ok, fn -> apply(module, function, []) end}
        1 -> {:ok, fn arg -> apply(module, function, [arg]) end}
        _ -> {:error, :invalid_function_reference}
      end
    end
  end

  defp deserialize_api_key(%{"__type__" => "function", "error" => _}) do
    {:error, DeserializationError.exception(cause: %{message: "Function not found"})}
  end

  defp deserialize_api_key(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid API key structure", input: input})}
  end

  defp deserialize_messages(messages) when is_list(messages) do
    messages
    |> Enum.reduce_while({:ok, []}, fn message_data, {:ok, acc} ->
      case deserialize_message(message_data) do
        {:ok, message} -> {:cont, {:ok, [message | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp deserialize_messages(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid messages structure", input: input})}
  end

  defp deserialize_message(%{"__struct__" => "BeamMePrompty.Agent.Dsl.Message"} = message_data) do
    with {:ok, role} <- deserialize_atom(message_data["role"]),
         {:ok, content} <- deserialize_content_parts(message_data["content"]) do
      {:ok,
       %Dsl.Message{
         role: role,
         content: content
       }}
    end
  end

  defp deserialize_message(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid message structure", input: input})}
  end

  defp deserialize_content_parts(parts) when is_list(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part_data, {:ok, acc} ->
      case deserialize_content_part(part_data) do
        {:ok, part} -> {:cont, {:ok, [part | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, parts} -> {:ok, Enum.reverse(parts)}
      error -> error
    end
  end

  defp deserialize_content_parts(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid content parts structure", input: input}
     )}
  end

  defp deserialize_content_part(%{"__struct__" => "BeamMePrompty.Agent.Dsl.TextPart"} = part_data) do
    {:ok,
     %Dsl.TextPart{
       type: String.to_existing_atom(part_data["type"]),
       text: part_data["text"]
     }}
  end

  defp deserialize_content_part(%{"__struct__" => "BeamMePrompty.Agent.Dsl.FilePart"} = part_data) do
    with {:ok, file_data} <- deserialize_file_data(part_data["file"]) do
      {:ok,
       %Dsl.FilePart{
         type: String.to_existing_atom(part_data["type"]),
         file: file_data
       }}
    end
  end

  defp deserialize_content_part(%{"__struct__" => "BeamMePrompty.Agent.Dsl.DataPart"} = part_data) do
    {:ok,
     %Dsl.DataPart{
       type: String.to_existing_atom(part_data["type"]),
       data: part_data["data"]
     }}
  end

  defp deserialize_content_part(
         %{"__struct__" => "BeamMePrompty.Agent.Dsl.FunctionResultPart"} = part_data
       ) do
    with {:ok, name} <- deserialize_atom(part_data["name"]) do
      {:ok,
       %Dsl.FunctionResultPart{
         id: part_data["id"],
         name: name,
         result: part_data["result"]
       }}
    end
  end

  defp deserialize_content_part(
         %{"__struct__" => "BeamMePrompty.Agent.Dsl.FunctionCallPart"} = part_data
       ) do
    {:ok,
     %Dsl.FunctionCallPart{
       function_call: part_data["function_call"]
     }}
  end

  defp deserialize_content_part(
         %{"__struct__" => "BeamMePrompty.Agent.Dsl.ThoughtPart"} = part_data
       ) do
    {:ok,
     %Dsl.ThoughtPart{
       type: String.to_existing_atom(part_data["type"]),
       thought_signature: part_data["thought_signature"]
     }}
  end

  defp deserialize_content_part(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid content part structure", input: input}
     )}
  end

  defp deserialize_file_data(file_data) when is_map(file_data) do
    decoded_file =
      file_data
      |> Enum.map(fn
        {"bytes", encoded_bytes} when is_binary(encoded_bytes) ->
          {:bytes, Base.decode64!(encoded_bytes)}

        {key, value} ->
          {String.to_existing_atom(key), value}
      end)
      |> Map.new()

    {:ok, decoded_file}
  rescue
    ArgumentError ->
      {:error, :invalid_binary_data}

    _ ->
      {:error, DeserializationError.exception(cause: %{message: "Invalid function reference"})}
  end

  defp deserialize_file_data(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid file data structure", input: input}
     )}
  end

  defp deserialize_tools(tools) when is_list(tools) do
    tools
    |> Enum.reduce_while({:ok, []}, fn tool_str, {:ok, acc} ->
      case resolve_module(tool_str) do
        {:ok, module} -> {:cont, {:ok, [module | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tools} -> {:ok, Enum.reverse(tools)}
      error -> error
    end
  end

  defp deserialize_tools(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid tools structure", input: input})}
  end

  defp deserialize_memory_sources(sources) when is_list(sources) do
    sources
    |> Enum.reduce_while({:ok, []}, fn source_data, {:ok, acc} ->
      case deserialize_memory_source(source_data) do
        {:ok, source} -> {:cont, {:ok, [source | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, sources} -> {:ok, Enum.reverse(sources)}
      error -> error
    end
  end

  defp deserialize_memory_sources(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid memory sources structure", input: input}
     )}
  end

  defp deserialize_memory_source(
         %{"__struct__" => "BeamMePrompty.Agent.Dsl.MemorySource"} = source_data
       ) do
    with {:ok, name} <- deserialize_atom(source_data["name"]),
         {:ok, module} <- resolve_module(source_data["module"]),
         {:ok, opts} <- deserialize_keyword_list(source_data["opts"]) do
      {:ok,
       %Dsl.MemorySource{
         name: name,
         description: source_data["description"],
         module: module,
         opts: opts,
         default: source_data["default"] || false
       }}
    end
  end

  defp deserialize_memory_source(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid memory source structure", input: input}
     )}
  end

  defp deserialize_atom(atom_str) when is_binary(atom_str) do
    {:ok, String.to_existing_atom(atom_str)}
  rescue
    ArgumentError ->
      {:error,
       DeserializationError.exception(cause: %{message: "Atom not found", atom: atom_str})}
  end

  defp deserialize_atom(atom) when is_atom(atom), do: {:ok, atom}

  defp deserialize_atom(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid atom structure", input: input})}
  end

  defp deserialize_depends_on(nil), do: {:ok, nil}
  defp deserialize_depends_on([]), do: {:ok, []}

  defp deserialize_depends_on(depends_on) when is_list(depends_on) do
    depends_on
    |> Enum.reduce_while({:ok, []}, fn dep, {:ok, acc} ->
      case deserialize_atom(dep) do
        {:ok, atom} -> {:cont, {:ok, [atom | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, deps} -> {:ok, Enum.reverse(deps)}
      error -> error
    end
  end

  defp deserialize_depends_on(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid depends_on structure", input: input}
     )}
  end

  defp deserialize_agent_config(agent_config) when is_map(agent_config) do
    {:ok, agent_config}
  end

  defp deserialize_agent_config(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid agent_config structure", input: input}
     )}
  end

  defp deserialize_keyword_list(nil), do: {:ok, []}
  defp deserialize_keyword_list([]), do: {:ok, []}

  defp deserialize_keyword_list(keyword_list) when is_list(keyword_list) do
    opts =
      keyword_list
      |> Enum.map(fn
        [key_str, value] when is_binary(key_str) ->
          {String.to_existing_atom(key_str), deserialize_keyword_value(value)}

        %{"__type__" => "tuple", "elements" => [key_str, value]} when is_binary(key_str) ->
          {String.to_existing_atom(key_str), deserialize_keyword_value(value)}

        _ ->
          throw(:invalid_format)
      end)

    {:ok, opts}
  rescue
    ArgumentError ->
      {:error,
       DeserializationError.exception(
         cause: %{message: "Unknown atom in keyword list", input: keyword_list}
       )}
  catch
    :invalid_format ->
      {:error,
       DeserializationError.exception(
         cause: %{message: "Invalid keyword list format", input: keyword_list}
       )}
  end

  defp deserialize_keyword_list(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid keyword list structure", input: input}
     )}
  end

  defp deserialize_keyword_value(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp deserialize_keyword_value(value), do: value

  defp deserialize_tuple_elements(elements) when is_list(elements) do
    elements
    |> Enum.reduce_while({:ok, []}, fn element, {:ok, acc} ->
      case deserialize_element(element) do
        {:ok, deserialized_element} -> {:cont, {:ok, [deserialized_element | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, elements} -> {:ok, Enum.reverse(elements)}
      error -> error
    end
  end

  defp deserialize_element(%{"__type__" => "tuple", "elements" => elements}) do
    case deserialize_tuple_elements(elements) do
      {:ok, deserialized_elements} -> {:ok, List.to_tuple(deserialized_elements)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp deserialize_element(%{"__type__" => "mfa"} = mfa_data), do: deserialize_api_key(mfa_data)

  defp deserialize_element(%{"__struct__" => _} = struct_data),
    do: deserialize_struct_element(struct_data)

  defp deserialize_element(atom_str) when is_binary(atom_str), do: deserialize_atom(atom_str)
  defp deserialize_element(other), do: {:ok, other}

  defp deserialize_struct_element(%{"__struct__" => module_str} = struct_data) do
    with {:ok, module} <- resolve_module(module_str),
         data = Map.drop(struct_data, ["__struct__"]),
         {:ok, deserialized_data} <- deserialize_map_values(data) do
      {:ok, struct!(module, deserialized_data)}
    end
  end

  defp deserialize_map_values(map) when is_map(map) do
    map
    |> Enum.reduce_while({:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case deserialize_element(v) do
        {:ok, deserialized_v} -> {:cont, {:ok, Map.put(acc, k, deserialized_v)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_module(module_str) when is_binary(module_str) do
    try do
      module = Module.concat([module_str])

      if Code.ensure_loaded?(module) do
        {:ok, module}
      else
        {:error,
         DeserializationError.exception(
           cause: %{message: "Module not loaded", module: module_str}
         )}
      end
    rescue
      ArgumentError ->
        {:error,
         DeserializationError.exception(
           cause: %{message: "Invalid module name", module: module_str}
         )}
    end
  end

  defp resolve_module(input) do
    {:error,
     DeserializationError.exception(cause: %{message: "Invalid module input", input: input})}
  end

  defp resolve_function_module(module_str) when is_binary(module_str) do
    try do
      module = Module.concat([module_str])

      if Code.ensure_loaded?(module) do
        {:ok, module}
      else
        {:error,
         DeserializationError.exception(
           cause: %{message: "Function module not loaded", module: module_str}
         )}
      end
    rescue
      ArgumentError ->
        {:error,
         DeserializationError.exception(
           cause: %{message: "Invalid function module name", module: module_str}
         )}
    end
  end

  defp resolve_function_module(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid function module input", input: input}
     )}
  end

  defp resolve_function_name(function_str) when is_binary(function_str) do
    {:ok, String.to_existing_atom(function_str)}
  rescue
    ArgumentError ->
      {:error,
       DeserializationError.exception(
         cause: %{message: "Invalid function name", function: function_str}
       )}
  end

  defp resolve_function_name(input) do
    {:error,
     DeserializationError.exception(
       cause: %{message: "Invalid function name input", input: input}
     )}
  end
end
