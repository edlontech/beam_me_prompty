defmodule BeamMePrompty.DAG do
  @moduledoc """
  Directed Acyclic Graph (DAG) implementation for agent execution.

  This module provides functionality to:
  1. Build a DAG from agent stage definitions
  2. Validate the DAG (check for cycles)
  3. Execute the DAG using a specified executor

  The DAG module defines a behaviour that executors must implement.
  """
  @moduledoc section: :agent_core_and_lifecycle

  @type dag_node :: %{
          name: String.t(),
          depends_on: list(String.t()) | nil,
          config: map()
        }

  @type dag :: %{
          nodes: %{required(String.t()) => dag_node()},
          edges: %{required(String.t()) => list(String.t())},
          roots: list(String.t())
        }

  @doc """
  Builds a DAG from agent stages.

  Returns a map with:
  - :nodes - Map of stage names to their full configuration
  - :edges - Map of stage names to lists of dependent stage names
  - :roots - List of stage names with no dependencies
  """
  @spec build(list(node())) :: dag()
  def build(stages) do
    dag = %{
      nodes: %{},
      edges: %{},
      roots: []
    }

    # First pass: collect all nodes
    dag =
      Enum.reduce(stages, dag, fn stage, acc ->
        stage_name = stage.name

        # Add node to the nodes map
        nodes = Map.put(acc.nodes, stage_name, stage)

        # Initialize empty edges for this node
        edges = Map.put(acc.edges, stage_name, [])

        %{acc | nodes: nodes, edges: edges}
      end)

    # Second pass: build edges and identify roots
    dag =
      Enum.reduce(stages, dag, fn stage, acc ->
        stage_name = stage.name
        depends_on = stage.depends_on || []

        # For each dependency, add this stage as an edge
        edges =
          Enum.reduce(depends_on, acc.edges, fn dep, edges_acc ->
            deps = Map.get(edges_acc, dep, [])
            Map.put(edges_acc, dep, [stage_name | deps])
          end)

        %{acc | edges: edges}
      end)

    # Identify root nodes (those with no dependencies)
    roots =
      Enum.filter(stages, fn stage ->
        Enum.empty?(stage.depends_on || [])
      end)
      |> Enum.map(& &1.name)

    %{dag | roots: roots}
  end

  @doc """
  Finds nodes that are ready to be executed.

  A node is ready if:
  1. It has not been executed yet
  2. All its dependencies have been executed (are in results)

  Returns a list of node names.
  """
  @spec find_ready_nodes(dag(), %{required(String.t()) => any()}) :: list(String.t())
  def find_ready_nodes(dag, results) do
    executed_nodes = Map.keys(results) |> MapSet.new()

    Enum.filter(Map.keys(dag.nodes), fn node ->
      if MapSet.member?(executed_nodes, node) do
        false
      else
        node_config = Map.get(dag.nodes, node)
        dependencies = node_config.depends_on || []

        # credo:disable-for-next-line
        Enum.all?(dependencies, fn dep -> Map.has_key?(results, dep) end)
      end
    end)
  end

  @doc """
  Validates that the DAG has no cycles.

  Returns :ok if valid, {:error, reason} otherwise.
  """
  @spec validate(dag()) :: :ok | {:error, String.t()}
  def validate(dag) do
    visited = MapSet.new()
    temp_visited = MapSet.new()

    result =
      Enum.reduce_while(Map.keys(dag.nodes), :ok, fn node, _acc ->
        if MapSet.member?(visited, node) do
          {:cont, :ok}
        else
          # credo:disable-for-next-line
          case has_cycle?(dag, node, visited, temp_visited) do
            {:ok, new_visited} -> {:cont, {:ok, new_visited}}
            {:error, _} = error -> {:halt, error}
          end
        end
      end)

    case result do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp has_cycle?(dag, node, visited, temp_visited) do
    if MapSet.member?(temp_visited, node) do
      {:error,
       BeamMePrompty.Errors.Framework.exception(cause: "Cycle detected involving node #{node}")}
    else
      if MapSet.member?(visited, node) do
        {:ok, visited}
      else
        temp_visited = MapSet.put(temp_visited, node)
        dependencies = Map.get(dag.edges, node, [])

        result =
          Enum.reduce_while(dependencies, {:ok, visited}, fn dep, {:ok, acc_visited} ->
            # credo:disable-for-next-line
            case has_cycle?(dag, dep, acc_visited, temp_visited) do
              {:ok, new_visited} -> {:cont, {:ok, new_visited}}
              {:error, _} = error -> {:halt, error}
            end
          end)

        case result do
          {:ok, new_visited} ->
            new_visited = MapSet.put(new_visited, node)
            {:ok, new_visited}

          error ->
            error
        end
      end
    end
  end
end
