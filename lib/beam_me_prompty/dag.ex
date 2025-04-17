defmodule BeamMePrompty.DAG do
  @moduledoc """
  Directed Acyclic Graph (DAG) implementation for pipeline execution.

  This module provides functionality to:
  1. Build a DAG from pipeline stage definitions
  2. Validate the DAG (check for cycles)
  3. Execute the DAG using a specified executor

  The DAG module defines a behaviour that executors must implement.
  """

  @doc """
  Provides a convenient way to implement the DAG behaviour.

  When used, it:
  - Declares the module as implementing the BeamMePrompty.DAG behaviour
  - Imports helper functions from BeamMePrompty.DAG
  - Provides default implementations for callbacks that can be overridden

  Example:
      defmodule MyCustomExecutor do
        use BeamMePrompty.DAG
        
        @impl true
        def execute(dag, input, node_executor) do
          # Custom implementation
        end
      end
  """
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour BeamMePrompty.DAG

      alias BeamMePrompty.DAG

      import BeamMePrompty.DAG, only: [build: 1, validate: 1]

      @impl true
      def execute_node(node, input, executor_fn) do
        executor_fn.(node, input)
      end

      defoverridable execute_node: 3
    end
  end

  @doc """
  Callback for executing a DAG.

  Takes:
  - dag: The DAG structure
  - input: The initial input data
  - node_executor: Function to execute a single node

  Returns {:ok, results} or {:error, reason}
  """
  @callback execute(dag :: map(), initial_context :: map(), node_executor :: function()) ::
              {:ok, map()} | {:error, any()}

  @doc """
  Callback for executing a single node in the DAG.

  Takes:
  - node: The node configuration
  - input: The input data for this node
  - executor_fn: Function to execute the node logic

  Returns {:ok, result} or {:error, reason}
  """
  @callback execute_node(node :: map(), input :: map(), executor_fn :: function()) ::
              {:ok, any()} | {:error, any()}

  @doc """
  Builds a DAG from pipeline stages.

  Returns a map with:
  - :nodes - Map of stage names to their full configuration
  - :edges - Map of stage names to lists of dependent stage names
  - :roots - List of stage names with no dependencies
  """
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
  Validates that the DAG has no cycles.

  Returns :ok if valid, {:error, reason} otherwise.
  """
  def validate(dag) do
    visited = MapSet.new()
    temp_visited = MapSet.new()

    result =
      Enum.reduce_while(Map.keys(dag.nodes), :ok, fn node, _acc ->
        if MapSet.member?(visited, node) do
          {:cont, :ok}
        else
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
      {:error, "Cycle detected involving node #{node}"}
    else
      if MapSet.member?(visited, node) do
        {:ok, visited}
      else
        temp_visited = MapSet.put(temp_visited, node)
        dependencies = Map.get(dag.edges, node, [])

        result =
          Enum.reduce_while(dependencies, {:ok, visited}, fn dep, {:ok, acc_visited} ->
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

  @doc """
  Executes the DAG using the specified executor.

  Takes:
  - dag: The DAG structure
  - input: The initial input data
  - execute_fn: Function to execute a single node (fn node, context -> {:ok, result} | {:error, reason} end)
  - executor: The executor module to use (defaults to BeamMePrompty.DAG.Executor.InMemory)

  Returns {:ok, results} or {:error, reason}
  """
  def execute(dag, initial_context, execute_fn, executor \\ BeamMePrompty.DAG.Executor.InMemory) do
    executor.execute(dag, initial_context, execute_fn)
  end
end
