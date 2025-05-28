Mox.defmock(BeamMePrompty.FakeLlmClient, for: BeamMePrompty.LLM)
Mox.defmock(BeamMePrompty.TestTool, for: BeamMePrompty.Tool)

Mimic.copy(BeamMePrompty.Agent.Internals.StateManager)
Mimic.copy(BeamMePrompty.Errors.ExecutionError)
Mimic.copy(BeamMePrompty.Errors)
Mimic.copy(BeamMePrompty.Telemetry)
Mimic.copy(BeamMePrompty.Agent.Stage.MessageManager)
Mimic.copy(BeamMePrompty.Agent.Stage.AgentCallbacks)
Mimic.copy(BeamMePrompty.WhatDoesTheFoxSayTool)

Logger.configure(level: :info)

ExUnit.start()
