defmodule BeamMePrompty.DAG.Executor.InMemory do
  @moduledoc """
  Default in-memory DAG executor for BeamMePrompty agents.
  Executes agent stages in topological order, maintaining stage results
  in memory and handling sequential execution without parallelism or external persistence.
  """
  use BeamMePrompty.DAG

  @impl true
  def execute(dag, initial_context, node_executor) do
    case DAG.validate(dag) do
      :ok ->
        execute_topological(dag, initial_context, node_executor, %{})

      error ->
        error
    end
  end

  defp execute_topological(dag, initial_context, execute_fn, results) do
    ready_nodes = find_ready_nodes(dag, results)

    if Enum.empty?(ready_nodes) do
      if map_size(results) == map_size(dag.nodes) do
        {:ok, results}
      else
        {:error, "Not all nodes could be executed. Possible unreachable nodes."}
      end
    else
      new_results =
        Enum.reduce_while(ready_nodes, results, fn node_name, acc_results ->
          node = Map.get(dag.nodes, node_name)

          node_context = Map.merge(initial_context, %{dependency_results: acc_results})

          case execute_node(node, node_context, execute_fn) do
            {:ok, result} ->
              {:cont, Map.put(acc_results, node_name, result)}

            {:error, reason} ->
              {:halt, {:error, "Error executing node #{node_name}: #{inspect(reason)}"}}
          end
        end)

      case new_results do
        {:error, _} = error -> error
        _ -> execute_topological(dag, initial_context, execute_fn, new_results)
      end
    end
  end

  defp find_ready_nodes(dag, results) do
    executed_nodes = Map.keys(results) |> MapSet.new()

    Enum.filter(Map.keys(dag.nodes), fn node ->
      if MapSet.member?(executed_nodes, node) do
        false
      else
        node_config = Map.get(dag.nodes, node)
        dependencies = node_config.depends_on || []

        Enum.all?(dependencies, fn dep -> Map.has_key?(results, dep) end)
      end
    end)
  end
end
