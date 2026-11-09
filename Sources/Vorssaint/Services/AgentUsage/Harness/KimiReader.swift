// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Kimi Code's `agents/*/wire.jsonl`. A turn opens when the agent starts
/// answering a prompt and stays open while steps, requests and tool calls keep
/// it alive; the idle timeout closes it once it goes quiet. Prompts, replies
/// and tool output are never decoded.
struct KimiReader: AgentHarnessReader {
    var provider: AgentProvider { .kimi }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let type = AgentLogParser.firstType(line)?.name, let object = AgentLogObject(line) else { return [] }
        // Only timestamped events are activity; a session's metadata carries
        // `created_at` instead and opens nothing.
        guard let date = AgentLogParser.seconds(object.value("time")) else { return [] }
        if type == "agent.turn.started" {
            return [.turnBegan(date)]
        }
        if type == "llm.request" {
            let model = object.string("model") ?? object.string("modelAlias") ?? ""
            guard !model.isEmpty else { return [.turnActive(date)] }
            state.model = model
            return [.turnActive(date), .turnContext(model: AgentLogParser.native(model), project: state.project)]
        }
        // Every other timestamped event is activity that keeps the turn alive.
        return [.turnActive(date)]
    }
}
