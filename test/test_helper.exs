Mox.defmock(BeamMePrompty.FakeLlmClient, for: BeamMePrompty.LLM)
Mox.defmock(BeamMePrompty.TestTool, for: BeamMePrompty.Tool)

Mimic.copy(BeamMePrompty.Agent.Internals.StateManager)
Mimic.copy(BeamMePrompty.Errors.ExecutionError)
Mimic.copy(BeamMePrompty.Errors)
Mimic.copy(BeamMePrompty.Telemetry)
Mimic.copy(BeamMePrompty.Agent.Stage.MessageManager)
Mimic.copy(BeamMePrompty.Agent.Stage.AgentCallbacks)
Mimic.copy(BeamMePrompty.WhatDoesTheFoxSayTool)
Mimic.copy(BeamMePrompty.LLM)
Mimic.copy(BeamMePrompty.Agent.Stage.Config)
Mimic.copy(BeamMePrompty.Agent.Stage.LLMProcessor)
Mimic.copy(BeamMePrompty.Validator)
Mimic.copy(BeamMePrompty.Agent.Stage.ToolExecutor)

Logger.configure(level: :info)

ExUnit.start()
