Application.ensure_all_started(:postgrex)

BeamMePrompty.TestRepo.start_link()

Mox.defmock(BeamMePrompty.MockMemory, for: BeamMePrompty.Agent.Memory)

Mimic.copy(BeamMePrompty.LLM.GoogleGemini, type_check: true)
Mimic.copy(BeamMePrompty.FakeLlmClient, type_check: true)
Mimic.copy(BeamMePrompty.Agent.Stage.ToolExecutor, type_check: true)
Mimic.copy(BeamMePrompty.TestTool, type_check: true)
Mimic.copy(BeamMePrompty.Agent.Internals.StateManager, type_check: true)

Logger.configure(level: :info)

ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(BeamMePrompty.TestRepo, :manual)
