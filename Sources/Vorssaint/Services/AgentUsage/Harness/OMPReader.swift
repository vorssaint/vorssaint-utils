// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads OMP session logs. OMP writes one JSON object per line, and a model
/// reply carries its own token counts and its own cost, so a reply that has
/// usage is a billed response.
///
/// The log's `type` values are a closed set in the current schema, but a
/// newer OMP may add one. An unknown type is ignored rather than treated as a
/// failure: a log the app cannot read is a log the app has nothing to say
/// about.
struct OMPReader: AgentHarnessReader {
    var provider: AgentProvider { .omp }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line),
              json["type"] as? String == "message",
              let message = json["message"] as? [String: Any] else { return [] }

        let date = AgentLogParser.timestamp(message["timestamp"])
            ?? AgentLogParser.timestamp(json["timestamp"]) ?? now
        if let model = message["model"] as? String, !model.isEmpty {
            state.model = AgentLogParser.native(model)
        }
        if let project = OMPReader.projectName(for: json) {
            state.project = project
        }
        if let session = OMPReader.sessionName(for: json), !session.isEmpty {
            state.session = AgentLogParser.native(session)
        }

        guard let usage = message["usage"] as? [String: Any] else { return [] }
        let tokens = OMPReader.tokens(usage)
        let recordedCost = (usage["cost"] as? [String: Any])?["total"] as? NSNumber
        let recorded = recordedCost?.doubleValue
        guard tokens.total > 0 || (recorded ?? 0) > 0 else { return [] }

        // The reply's own id keeps a second reading of the same line from
        // counting it twice, and a response is a response whether or not it
        // carried tokens.
        let key = "omp:\(OMPReader.replyID(for: json) ?? state.session):\(date.timeIntervalSince1970)"
        return [OMPReader.usage(tokens, recorded: recorded,
                                key: key, date: date, state: state)]
    }

    /// The tokens OMP counted for one reply. OMP reports cache reads and
    /// cache writes beside the plain input, the same split the other logs
    /// use, so the numbers need no conversion.
    static func tokens(_ usage: [String: Any]) -> AgentTokens {
        AgentTokens(input: AgentLogParser.int(usage["input"]),
                    cacheWrite: AgentLogParser.int(usage["cacheWrite"]),
                    cacheRead: AgentLogParser.int(usage["cacheRead"]),
                    output: AgentLogParser.int(usage["output"]))
    }

    /// The id of the reply itself, so a re-read of the same line is the same
    /// record.
    private static func replyID(for json: [String: Any]) -> String? {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        return id
    }

    /// The session the line belongs to. OMP names it on the session line
    /// and carries it on the replies, so the reply's own copy is used when
    /// it has one.
    private static func sessionName(for json: [String: Any]) -> String? {
        if let id = json["sessionId"] as? String, !id.isEmpty { return id }
        if let message = json["message"] as? [String: Any],
           let id = message["sessionId"] as? String, !id.isEmpty { return id }
        return nil
    }

    /// The project the session belongs to. The folder the log sits in is
    /// the working directory with its separators replaced, which is a name
    /// rather than a path, so the session's own record is preferred.
    private static func projectName(for json: [String: Any]) -> String? {
        if let cwd = json["cwd"] as? String, !cwd.isEmpty {
            return AgentLogParser.projectName(cwd)
        }
        if let message = json["message"] as? [String: Any],
           let cwd = message["cwd"] as? String, !cwd.isEmpty {
            return AgentLogParser.projectName(cwd)
        }
        return nil
    }

    private static func usage(_ tokens: AgentTokens, recorded: Double?, key: String,
                              date: Date, state: AgentLogState) -> AgentLogEntry {
        let billable = AgentBillable(tokens: tokens)
        let priced = AgentPricing.cost(billable, model: state.model)
        // A model the list does not know costs what OMP recorded. Local and
        // free models record zero, which stays an estimate so a price the
        // list learns later still applies.
        let cost: Double?
        let isReported: Bool
        if let calculated = priced.cost {
            cost = calculated
            isReported = false
        } else if let recorded {
            cost = recorded
            isReported = recorded > 0
        } else {
            cost = nil
            isReported = false
        }
        return .usage(key: key, record: AgentUsageRecord(
            provider: .omp, date: date, model: state.model, project: state.project,
            session: state.session, tokens: tokens, cost: cost, savings: priced.savings,
            reportedCost: isReported), billable: billable)
    }
}
