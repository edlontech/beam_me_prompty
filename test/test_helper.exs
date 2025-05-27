Mox.defmock(BeamMePrompty.FakeLlmClient, for: BeamMePrompty.LLM)
Mox.defmock(BeamMePrompty.TestTool, for: BeamMePrompty.Tool)

Logger.configure(level: :error)

ExUnit.start()
