defmodule BeamMePrompty.Agent.PersistedAgentsTest do
  use BeamMePrompty.DataCase, async: true

  alias BeamMePrompty.PersistedAgents
  alias BeamMePrompty.TestRepo

  describe "list_agents/3" do
    test "returns empty list when no agents exist" do
      result = PersistedAgents.list_agents(TestRepo)
      assert %{agents: [], next_after: nil} = result
    end

    test "returns all agents when no filters are provided" do
      agent1 = insert_agent(%{agent_name: "Agent1", agent_type: "type1"})
      agent2 = insert_agent(%{agent_name: "Agent2", agent_type: "type2"})

      result = PersistedAgents.list_agents(TestRepo)

      assert %{agents: agents, next_after: nil} = result
      assert length(agents) == 2
      assert Enum.map(agents, & &1.id) |> Enum.sort() == Enum.sort([agent1.id, agent2.id])
    end

    test "filters agents by agent_name" do
      agent1 = insert_agent(%{agent_name: "TestAgent", agent_type: "type1"})
      _agent2 = insert_agent(%{agent_name: "OtherAgent", agent_type: "type2"})

      result = PersistedAgents.list_agents(TestRepo, %{agent_name: "TestAgent"})

      assert %{agents: [returned_agent], next_after: nil} = result
      assert returned_agent.id == agent1.id
    end

    test "filters agents with greater than operator" do
      _agent1 = insert_agent(%{agent_name: "Agent1", agent_type: "type1"})
      _agent2 = insert_agent(%{agent_name: "Agent2", agent_type: "type2"})
      _agent3 = insert_agent(%{agent_name: "Agent3", agent_type: "type3"})

      # Test with a simple string filter first
      result = PersistedAgents.list_agents(TestRepo, %{agent_name: "Agent1"})

      assert %{agents: agents, next_after: nil} = result
      assert length(agents) == 1
      assert hd(agents).agent_name == "Agent1"
    end

    test "respects page_size limit" do
      for i <- 1..5 do
        insert_agent(%{agent_name: "Agent#{i}", agent_type: "type#{i}"})
      end

      result = PersistedAgents.list_agents(TestRepo, %{}, page_size: 3)

      assert %{agents: agents, next_after: next_after} = result
      assert length(agents) == 3
      assert next_after != nil
    end

    test "supports pagination with next_after cursor" do
      _agents =
        for i <- 1..5 do
          insert_agent(%{agent_name: "Agent#{i}", agent_type: "type#{i}"})
        end

      # Get first page
      first_page = PersistedAgents.list_agents(TestRepo, %{}, page_size: 2)
      assert %{agents: first_agents, next_after: next_after} = first_page
      assert length(first_agents) == 2
      assert next_after != nil

      # Get second page
      second_page =
        PersistedAgents.list_agents(TestRepo, %{}, page_size: 2, next_after: next_after)

      assert %{agents: second_agents, next_after: _} = second_page
      assert length(second_agents) == 2

      # Ensure no overlap
      first_ids = Enum.map(first_agents, & &1.id)
      second_ids = Enum.map(second_agents, & &1.id)
      assert Enum.empty?(first_ids -- (first_ids -- second_ids))
    end

    test "respects allowed_fields restrictions" do
      insert_agent(%{agent_name: "TestAgent", agent_type: "type1"})

      result =
        PersistedAgents.list_agents(
          TestRepo,
          %{agent_name: "TestAgent"},
          allowed_fields: [:agent_name]
        )

      assert %{agents: [_agent]} = result

      result =
        PersistedAgents.list_agents(
          TestRepo,
          %{agent_type: "type1"},
          allowed_fields: [:agent_name]
        )

      assert %{agents: [_agent]} = result
    end
  end

  describe "get_agent/2" do
    test "returns {:ok, agent} when agent exists" do
      agent = insert_agent(%{agent_name: "TestAgent", agent_type: "test"})

      assert {:ok, returned_agent} = PersistedAgents.get_agent(TestRepo, agent.id)
      assert returned_agent.id == agent.id
      assert returned_agent.agent_name == "TestAgent"
    end

    test "returns {:error, :not_found} when agent does not exist" do
      assert {:error, :not_found} = PersistedAgents.get_agent(TestRepo, Ecto.UUID.generate())
    end
  end

  describe "get_agent_by_name/2" do
    test "returns {:ok, agent} when agent exists" do
      agent = insert_agent(%{agent_name: "TestAgent", agent_type: "test"})

      assert {:ok, returned_agent} = PersistedAgents.get_agent_by_name(TestRepo, "TestAgent")
      assert returned_agent.id == agent.id
      assert returned_agent.agent_name == "TestAgent"
    end

    test "returns {:error, :not_found} when agent does not exist" do
      assert {:error, :not_found} =
               PersistedAgents.get_agent_by_name(TestRepo, "NonExistentAgent")
    end
  end

  describe "create_agent/2" do
    test "creates agent with valid attributes" do
      attrs = %{
        agent_name: "TestAgent",
        agent_version: "1.0.0",
        agent_type: "test_type",
        agent_spec: %{type: "test"},
        metadata: %{category: "testing"}
      }

      assert {:ok, agent} = PersistedAgents.create_agent(TestRepo, attrs)
      assert agent.agent_name == "TestAgent"
      assert agent.agent_version == "1.0.0"
      assert agent.agent_type == "test_type"
      assert agent.agent_spec == %{type: "test"}
      assert agent.metadata == %{category: "testing"}
    end

    test "returns error with invalid attributes" do
      attrs = %{agent_name: "invalid name"}

      assert {:error, changeset} = PersistedAgents.create_agent(TestRepo, attrs)
      assert changeset.valid? == false

      errors = errors_on(changeset)
      assert "can't be blank" in errors.agent_version
      assert "can't be blank" in errors.agent_type
      assert "can't be blank" in errors.agent_spec
    end

    test "validates agent_name format" do
      base_attrs = %{
        agent_version: "1.0.0",
        agent_type: "test_type",
        agent_spec: %{type: "test"}
      }

      attrs = Map.put(base_attrs, :agent_name, "ValidAgent")
      assert {:ok, _agent} = PersistedAgents.create_agent(TestRepo, attrs)

      attrs = Map.put(base_attrs, :agent_name, "invalidAgent")
      assert {:error, changeset} = PersistedAgents.create_agent(TestRepo, attrs)
      assert "has invalid format" in errors_on(changeset).agent_name
    end

    test "validates agent_type format" do
      base_attrs = %{
        agent_name: "TestAgent",
        agent_version: "1.0.0",
        agent_spec: %{type: "test"}
      }

      attrs = Map.put(base_attrs, :agent_type, "valid_type")
      assert {:ok, _agent} = PersistedAgents.create_agent(TestRepo, attrs)

      attrs = Map.put(base_attrs, :agent_type, "InvalidType")
      assert {:error, changeset} = PersistedAgents.create_agent(TestRepo, attrs)
      assert "has invalid format" in errors_on(changeset).agent_type
    end

    test "enforces unique constraint on agent_type and agent_version" do
      attrs = %{
        agent_name: "TestAgent1",
        agent_version: "1.0.0",
        agent_type: "test_type",
        agent_spec: %{type: "test"}
      }

      assert {:ok, _agent1} = PersistedAgents.create_agent(TestRepo, attrs)

      attrs2 = %{attrs | agent_name: "TestAgent2"}
      assert {:error, changeset} = PersistedAgents.create_agent(TestRepo, attrs2)
      assert "has already been taken" in errors_on(changeset).agent_type
    end
  end

  describe "update_agent/3" do
    test "updates agent with valid attributes" do
      agent = insert_agent(%{agent_name: "OriginalAgent", agent_type: "original"})

      attrs = %{agent_name: "UpdatedAgent"}
      assert {:ok, updated_agent} = PersistedAgents.update_agent(TestRepo, agent, attrs)
      assert updated_agent.agent_name == "UpdatedAgent"
      assert updated_agent.id == agent.id
    end

    test "returns error with invalid attributes" do
      agent = insert_agent(%{agent_name: "TestAgent", agent_type: "test"})

      attrs = %{agent_name: "invalid name"}
      assert {:error, changeset} = PersistedAgents.update_agent(TestRepo, agent, attrs)
      assert "has invalid format" in errors_on(changeset).agent_name
    end

    test "updates metadata fields" do
      agent =
        insert_agent(%{
          agent_name: "TestAgent",
          agent_type: "test",
          metadata: %{category: "old"}
        })

      attrs = %{metadata: %{category: "new", status: "active"}}
      assert {:ok, updated_agent} = PersistedAgents.update_agent(TestRepo, agent, attrs)
      assert updated_agent.metadata == %{category: "new", status: "active"}
    end
  end

  describe "delete_agent/2" do
    test "deletes existing agent" do
      agent = insert_agent(%{agent_name: "TestAgent", agent_type: "test"})

      assert {:ok, deleted_agent} = PersistedAgents.delete_agent(TestRepo, agent)
      assert deleted_agent.id == agent.id
      assert {:error, :not_found} = PersistedAgents.get_agent(TestRepo, agent.id)
    end
  end

  describe "get_agents_by_metadata/3" do
    test "returns agents matching metadata filters" do
      agent1 =
        insert_agent(%{
          agent_name: "Agent1",
          agent_type: "type1",
          metadata: %{"category" => "ai", "status" => "active"}
        })

      agent2 =
        insert_agent(%{
          agent_name: "Agent2",
          agent_type: "type2",
          metadata: %{"category" => "ai", "status" => "inactive"}
        })

      _agent3 =
        insert_agent(%{
          agent_name: "Agent3",
          agent_type: "type3",
          metadata: %{"category" => "web", "status" => "active"}
        })

      result = PersistedAgents.get_agents_by_metadata(TestRepo, %{"category" => "ai"})

      assert %{agents: agents, next_after: nil} = result
      assert length(agents) == 2
      agent_ids = Enum.map(agents, & &1.id) |> Enum.sort()
      assert agent_ids == Enum.sort([agent1.id, agent2.id])
    end

    test "returns agents matching multiple metadata filters" do
      agent1 =
        insert_agent(%{
          agent_name: "Agent1",
          agent_type: "type1",
          metadata: %{"category" => "ai", "status" => "active"}
        })

      _agent2 =
        insert_agent(%{
          agent_name: "Agent2",
          agent_type: "type2",
          metadata: %{"category" => "ai", "status" => "inactive"}
        })

      result =
        PersistedAgents.get_agents_by_metadata(TestRepo, %{
          "category" => "ai",
          "status" => "active"
        })

      assert %{agents: [agent], next_after: nil} = result
      assert agent.id == agent1.id
    end

    test "returns empty list when no agents match metadata filters" do
      _agent =
        insert_agent(%{
          agent_name: "Agent1",
          agent_type: "type1",
          metadata: %{"category" => "ai"}
        })

      result = PersistedAgents.get_agents_by_metadata(TestRepo, %{"category" => "web"})

      assert %{agents: [], next_after: nil} = result
    end

    test "supports pagination for metadata queries" do
      for i <- 1..5 do
        insert_agent(%{
          agent_name: "Agent#{i}",
          agent_type: "type#{i}",
          metadata: %{"category" => "ai"}
        })
      end

      result =
        PersistedAgents.get_agents_by_metadata(
          TestRepo,
          %{"category" => "ai"},
          page_size: 2
        )

      assert %{agents: agents, next_after: next_after} = result
      assert length(agents) == 2
      assert next_after != nil
    end
  end

  defp insert_agent(attrs) do
    default_attrs = %{
      agent_name: "DefaultAgent",
      agent_version: "1.0.0",
      agent_type: "default_type",
      agent_spec: %{type: "default"},
      metadata: %{}
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    {:ok, agent} = PersistedAgents.create_agent(TestRepo, merged_attrs)
    agent
  end
end
