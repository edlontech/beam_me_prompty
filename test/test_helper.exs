Mox.defmock(BeamMePrompty.FakeLlmClient, for: BeamMePrompty.LLM)
Mox.defmock(BeamMePrompty.TestTool, for: BeamMePrompty.Tool)

Mimic.copy(BeamMePrompty.Agent.Internals.StateManager)
Mimic.copy(BeamMePrompty.Errors.ExecutionError)
Mimic.copy(BeamMePrompty.Errors)

Logger.configure(level: :info)

ExUnit.start()
