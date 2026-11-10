// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads Mistral Vibe's session totals from `~/.vibe/logs/session`.
///
/// Vibe 3 keeps each session in `unified/<id>/`. Its `CURRENT` names the
/// generation folder whose `projection-state.json` holds the session's
/// running token totals, and `meta.json` beside it the times and working
/// folder; Vibe replaces each file whole. Older sessions keep one `meta.json`
/// in a `session_*` folder, with the totals under `stats`. Only the session's
/// identifier, times, working folder and token totals are decoded; the
/// transcript, journal and chunks are never opened.
struct VibeReader: AgentHarnessReader {
    static let metadata = "meta.json"
    static let current = "CURRENT"

    var provider: AgentProvider { .vibe }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let meta = AgentLogParser.object(line),
              let session = meta["session_id"] as? String, !session.isEmpty,
              // A session with no readable time is skipped rather than
              // counted on the day it happens to be read.
              let date = Self.date(meta["end_time"]) ?? AgentLogParser.seconds(meta["updatedAt"])
                ?? Self.date(meta["start_time"]) else { return [] }
        // In both layouts Vibe's input count includes what came from the cache.
        let tokens: AgentTokens
        if let stats = meta["stats"] as? [String: Any] {
            tokens = AgentLogParser.codexTokens(["input_tokens": stats["session_prompt_tokens"] as Any,
                                                 "cached_input_tokens": stats["session_cached_tokens"] as Any,
                                                 "output_tokens": stats["session_completion_tokens"] as Any])
        } else if let usage = meta["tokenUsage"] as? [String: Any] {
            tokens = AgentLogParser.codexTokens(["input_tokens": usage["inputTokens"] as Any,
                                                 "cached_input_tokens": usage["cachedInputTokens"] as Any,
                                                 "output_tokens": usage["outputTokens"] as Any])
        } else {
            return []
        }
        state.session = AgentLogParser.native(session)
        let environment = meta["environment"] as? [String: Any]
        if let folder = (environment?["working_directory"] ?? meta["cwd"] ?? meta["origin_directory"]) as? String,
           !folder.isEmpty {
            state.project = AgentLogParser.projectName(folder)
        }
        guard tokens.total > 0 else { return [] }
        // The totals cover the whole session and grow with each save; one key
        // per session keeps the largest reading. The files name no model, so
        // no list price applies.
        return [.usage(key: "vibe:\(state.session)", record: AgentUsageRecord(
            provider: .vibe, date: date, model: "", project: state.project, session: state.session,
            tokens: tokens, cost: nil, savings: 0), billable: AgentBillable(tokens: tokens, isAggregate: true))]
    }

    /// One object for `parse` from a unified session's `CURRENT`: the
    /// session's identifier, times and folder from its `meta.json`, which a
    /// new session may not have written yet, with `tokenUsage` and
    /// `updatedAt` from the generation `CURRENT` names. Nil while that
    /// generation cannot be read, as when a newer one has just replaced it.
    static func unifiedSession(current: Data, folder: URL) -> Data? {
        guard let pointer = AgentLogParser.object(current),
              let generation = pointer["generation"] as? String,
              // Vibe names generations with sixteen digits; anything else
              // could lead out of the session folder.
              generation.count == 16, generation.allSatisfy({ $0.isASCII && $0.isNumber }),
              let projection = try? Data(contentsOf: folder.appending(path: "generations/\(generation)/projection-state.json"),
                                         options: .mappedIfSafe),
              projection.count <= AgentLogReader.maximumLine,
              let snapshot = AgentLogParser.object(projection)?["snapshot"] as? [String: Any],
              let session = snapshot["session"] as? [String: Any] else { return nil }
        let meta = (try? Data(contentsOf: folder.appending(path: metadata))).flatMap(AgentLogParser.object) ?? [:]
        var object: [String: Any] = ["session_id": meta["session_id"] ?? pointer["session_id"] ?? ""]
        for key in ["start_time", "end_time", "origin_directory"] { object[key] = meta[key] }
        if let folder = (meta["environment"] as? [String: Any])?["working_directory"] {
            object["environment"] = ["working_directory": folder]
        }
        object["tokenUsage"] = session["tokenUsage"]
        object["updatedAt"] = session["updatedAt"]
        return try? JSONSerialization.data(withJSONObject: object)
    }

    /// ISO 8601 times; one written without a zone is local time.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        if let date = AgentLogParser.timestamp(text) { return date }
        guard let utc = AgentLogParser.timestamp(text + "Z") else { return nil }
        return utc.addingTimeInterval(-TimeInterval(TimeZone.current.secondsFromGMT(for: utc)))
    }
}
