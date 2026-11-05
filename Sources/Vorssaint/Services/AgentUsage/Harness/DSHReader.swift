// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the usage feed the DeepSeek Harness plugin writes, one JSONL file
/// per session. Every line names its own kind, so a file cut short, copied or
/// started mid-session still reads: metadata is adopted where it appears and
/// the responses it holds are counted either way.
struct DSHReader: AgentHarnessReader {
    var provider: AgentProvider { .dsh }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let envelope = AgentLogObject(line), let type = envelope.string("type") else { return [] }
        let date = AgentLogParser.timestamp(envelope.value("ts")) ?? now
        switch type {
        case "session":
            adopt(envelope, into: &state)
            return []
        case "turn":
            // A subagent's work belongs to the run it serves, so only the
            // session a person started shows turns as work in progress.
            guard !state.dshSubagent, let phase = envelope.string("phase") else { return [] }
            switch phase {
            case "start": return [.turnBegan(date)]
            case "end": return [.turnEnded(date, completed: envelope.value("completed") as? Bool == true, duration: nil)]
            default: return []
            }
        case "usage":
            return usage(envelope, date: date, state: state)
        default:
            return []
        }
    }

    private func adopt(_ envelope: AgentLogObject, into state: inout AgentLogState) {
        if let session = envelope.string("session"), !session.isEmpty {
            state.session = AgentLogParser.native(session)
        }
        if let cwd = envelope.string("cwd"), !cwd.isEmpty {
            state.project = AgentLogParser.projectName(cwd)
        }
        // The header is repeated whenever the plugin restarts on a running
        // session, so the parent it names now is the one that counts.
        state.dshSubagent = !(envelope.string("parent") ?? "").isEmpty
    }

    private func usage(_ envelope: AgentLogObject, date: Date, state: AgentLogState) -> [AgentLogEntry] {
        guard let model = envelope.string("model"), !model.isEmpty else { return [] }
        let counts = envelope.object("tokens")
        let tokens = AgentTokens(input: count(counts, "input"), cacheWrite: count(counts, "cacheWrite"),
                                 cacheRead: count(counts, "cacheRead"), output: count(counts, "output"),
                                 reasoning: count(counts, "reasoning"))
        let cost = reportedCost(envelope.value("cost"))
        let request = envelope.string("request") ?? ""
        // The response id is unique across the session; a line that lacks one
        // is still told apart by where it sits in the session.
        let key: String
        if request.isEmpty {
            let turn = AgentLogParser.int(envelope.value("turn"))
            let step = AgentLogParser.int(envelope.value("step"))
            key = "dsh:\(state.session):\(turn):\(step):\(date.timeIntervalSince1970)"
        } else {
            key = "dsh:\(request)"
        }
        return [.usage(key: key, record: AgentUsageRecord(
            provider: .dsh, date: date, model: AgentLogParser.native(model), project: state.project,
            session: state.session, tokens: tokens, cost: cost, savings: 0, reportedCost: cost != nil),
                       billable: AgentBillable(tokens: tokens))]
    }

    private func count(_ counts: AgentLogObject?, _ field: String) -> Int {
        AgentLogParser.int(counts?.value(field))
    }

    /// The price the plugin billed. It is the only one the feed has: a model
    /// can route through a provider the price list knows nothing about. A
    /// damaged figure reads as unknown rather than as a charge.
    private func reportedCost(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let cost = number.doubleValue
        return cost.isFinite && cost >= 0 ? cost : nil
    }
}
