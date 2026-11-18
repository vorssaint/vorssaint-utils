// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

/// The last turn read from one session's projection cache. It lives on the
/// cursor, not the cache state: DeepSeek rewrites the cache in place, so a
/// turn would otherwise look new on every read.
struct AgentDeepSeekProgress {
    var turn = 0
    var open = false
    var start: Date?
    var model = ""
    var project = ""
}

/// The DeepSeek Harness app, whose process tells whether an open cache still
/// belongs to a running turn.
enum AgentDeepSeekApp {
    static let bundleIdentifier = "com.deepseek.dsh"

    /// True when the app is running; a cache can outlive a quit.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// A testable form: whether the running bundle identifiers include ours.
    static func isRunning(_ identifiers: Set<String>) -> Bool {
        identifiers.contains(bundleIdentifier)
    }
}

/// Reads DeepSeek Harness's per-session projection cache. The app rewrites one
/// small JSON file per session under `~/.dsh/storages/session_projcache` as the
/// session runs; it holds the session's token totals, the model it last used,
/// and whether a turn is open, and no prompt, reply or tool output. The cache
/// is read whole each time it changes, so the service polls it by modification
/// date.
struct DeepSeekReader: AgentHarnessReader {
    var provider: AgentProvider { .deepseek }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line) else { return [] }
        switch json["kind"] as? String ?? "usage" {
        case "turnBegan":
            guard let date = AgentLogParser.seconds(json["date"]) else { return [] }
            return [.turnBegan(date)]
        case "turnContext":
            return [.turnContext(model: json["model"] as? String ?? "",
                                 project: AgentLogParser.projectName(json["project"] as? String ?? ""))]
        case "turnActive":
            return [.turnActive(now)]
        case "turnEnded":
            let date = AgentLogParser.seconds(json["date"])
            let duration = (json["duration"] as? NSNumber)?.doubleValue
            return [.turnEnded(date, completed: true, duration: duration.map { max(0, $0) })]
        default:
            break
        }
        guard let session = json["session"] as? String, !session.isEmpty else { return [] }
        let tokens = AgentTokens(input: AgentLogParser.int(json["input"]),
                                 cacheWrite: AgentLogParser.int(json["cacheWrite"]),
                                 cacheRead: AgentLogParser.int(json["cacheRead"]),
                                 output: AgentLogParser.int(json["output"]))
        guard tokens.total > 0 else { return [] }
        let model = AgentLogParser.native(json["model"] as? String ?? "")
        let project = AgentLogParser.projectName(json["project"] as? String ?? "")
        let date = AgentLogParser.seconds(json["createdAt"]) ?? now
        let requests = max(1, AgentLogParser.int(json["steps"]))
        // A session's totals say nothing about the size of any one prompt, so
        // they never imply a long-context request.
        let billable = AgentBillable(tokens: tokens, isAggregate: true)
        let priced = AgentPricing.cost(billable, model: model)
        let record = AgentUsageRecord(provider: .deepseek, date: date, model: model, project: project,
                                      session: session, requests: requests, tokens: tokens,
                                      cost: priced.cost, savings: priced.savings)
        return [.usage(key: "deepseek:" + session, record: record, billable: billable)]
    }
}

/// Reads one session's projection cache into small lines `DeepSeekReader`
/// parses: usage counters, plus the turn transitions that make the island's
/// timer and finish notice work. The cache is rewritten in place, so it is
/// read from its start each time; the turn progress is kept on the cursor.
enum AgentDeepSeekReader {
    /// A session cache larger than this is not a projection of counters.
    static let maximumSize = 2 << 20

    private struct Projection {
        let session: String
        let created: Date
        let modified: Date
        let project: String
        let model: String
        let tokens: AgentTokens
        let steps: Int
        let turn: Int
        let open: Bool
        let start: Date
    }

    static func read(_ cursor: AgentLogCursor, since horizon: Date,
                     shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue() else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        if identity != cursor.identity || size != cursor.offset { cursor.startOver(identity: identity) }
        cursor.modified = modified
        guard size > 0, size <= UInt64(maximumSize),
              let data = try? Data(contentsOf: URL(fileURLWithPath: cursor.path)) else { return }
        cursor.offset = size
        cursor.fingerprintRead()
        let session = ((cursor.path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let projection = projection(data, session: session, modified: modified, since: horizon) else { return }

        let previous = cursor.deepSeek
        // A new turn can start before the cache is ever seen closed, as with a
        // queued prompt. Close the turn the cursor knew before opening the new
        // one, so every completion still gets its notice.
        let end = projection.open ? projection.start : projection.modified
        if previous.open && (!projection.open || projection.turn != previous.turn) {
            let start = previous.start ?? projection.start
            let duration = max(0, end.timeIntervalSince(start))
            if let payload = turnPayload(kind: "turnEnded", date: end, duration: duration) { line(payload) }
        }
        if projection.open {
            if let payload = turnPayload(kind: "turnBegan", date: projection.start) { line(payload) }
            if let payload = turnPayload(kind: "turnContext", model: projection.model, project: projection.project) {
                line(payload)
            }
            if let payload = turnPayload(kind: "turnActive") { line(payload) }
        }
        if let payload = usagePayload(projection) { line(payload) }
        cursor.deepSeek = AgentDeepSeekProgress(turn: projection.turn, open: projection.open,
                                                start: projection.start, model: projection.model,
                                                project: projection.project)
    }

    /// The usage line `DeepSeekReader` parses. Kept for the cache contract.
    static func payload(_ data: Data, session: String, modified: Date, since horizon: Date) -> Data? {
        guard let projection = projection(data, session: session, modified: modified, since: horizon) else { return nil }
        return usagePayload(projection)
    }

    /// The counters and live turn state one session's projection holds. Only
    /// those fields are read; titles and the turn outline, which can hold text,
    /// are skipped in place and never decoded.
    private static func projection(_ data: Data, session: String, modified: Date, since horizon: Date) -> Projection? {
        guard let object = AgentLogObject(data),
              let record = object.object("record"),
              let identity = record.object("identity"),
              let rows = record.object("rows"),
              let totals = rows.object("tokenUsage")?.object("val")?.object("totals") else { return nil }
        let created = AgentLogParser.seconds(identity.value("createdAt")) ?? modified
        guard created >= horizon else { return nil }
        let input = AgentLogParser.int(totals.value("uncachedInputTokens") ?? totals.value("inputTokens"))
        let cacheWrite = AgentLogParser.int(totals.value("cacheWriteTokens"))
        let cacheRead = AgentLogParser.int(totals.value("cacheReadTokens"))
        let output = AgentLogParser.int(totals.value("outputTokens"))
        let stats = rows.object("sessionStats")?.object("val")
        let steps = max(1, AgentLogParser.int(stats?.value("steps")))
        let model = rows.object("modelSelection")?.object("val")?.object("lastUsed")?.string("model") ?? ""
        let openStep = stats?.object("openStep")
        let boundary = rows.object("turnBoundary")?.object("val")
        let approval = rows.object("approvalState")?.object("val")
        let openSequence = AgentLogParser.int(boundary?.value("openTurnStartSeq"))
        let approvalOpen = AgentLogParser.int(approval?.value("turnOpen")) != 0
        let open = openSequence > 0 || approvalOpen || openStep != nil
        let turn = max(AgentLogParser.int(stats?.value("lastTurn")),
                       AgentLogParser.int(boundary?.value("lastTurn")))
        let prompt = AgentLogParser.seconds(rows.object("sessionListMetadata")?.object("val")?.value("lastPromptAt"))
        let stepStart = AgentLogParser.seconds(openStep?.value("startTime"))
        let start = prompt ?? stepStart ?? AgentLogParser.seconds(identity.value("createdAt")) ?? modified
        let project = identity.string("cwd") ?? rows.string("workingDirectory") ?? ""
        return Projection(session: session, created: created, modified: modified, project: project,
                          model: model, tokens: AgentTokens(input: input, cacheWrite: cacheWrite,
                                                            cacheRead: cacheRead, output: output),
                          steps: steps, turn: turn, open: open, start: start)
    }

    private static func usagePayload(_ projection: Projection) -> Data? {
        guard projection.tokens.total > 0 else { return nil }
        let fields: [String: Any] = [
            "kind": "usage",
            "session": projection.session,
            "createdAt": projection.created.timeIntervalSince1970,
            "project": projection.project,
            "model": projection.model,
            "input": projection.tokens.input,
            "cacheWrite": projection.tokens.cacheWrite,
            "cacheRead": projection.tokens.cacheRead,
            "output": projection.tokens.output,
            "steps": projection.steps,
        ]
        return try? JSONSerialization.data(withJSONObject: fields)
    }

    private static func turnPayload(kind: String, date: Date? = nil, duration: TimeInterval? = nil,
                                    model: String? = nil, project: String? = nil) -> Data? {
        var fields: [String: Any] = ["kind": kind]
        if let date { fields["date"] = date.timeIntervalSince1970 }
        if let duration { fields["duration"] = max(0, duration) }
        if let model { fields["model"] = model }
        if let project { fields["project"] = project }
        return try? JSONSerialization.data(withJSONObject: fields)
    }
}
