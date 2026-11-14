// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Reads DeepSeek Harness's per-session projection cache. The app rewrites one
/// small JSON file per session under `~/.dsh/storages/session_projcache` as the
/// session runs; it holds the session's token totals and the model it last
/// used, and no prompt, reply or tool output. The cache is read whole each time
/// it changes, so the service polls it by modification date.
struct DeepSeekReader: AgentHarnessReader {
    var provider: AgentProvider { .deepseek }

    func parse(_ line: Data, state: inout AgentLogState, now: Date) -> [AgentLogEntry] {
        guard let json = AgentLogParser.object(line),
              let session = json["session"] as? String, !session.isEmpty else { return [] }
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

/// Reads one session's projection cache into the compact line `DeepSeekReader`
/// parses. The cache is rewritten in place, so it is read from its start each
/// time; nothing is kept from the previous read.
enum AgentDeepSeekReader {
    /// A session cache larger than this is not a projection of counters.
    static let maximumSize = 2 << 20

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
        guard let payload = payload(data, session: session, modified: modified, since: horizon) else { return }
        line(payload)
    }

    /// The counters one session's projection holds, as one compact line. Only
    /// the counter fields are read; the projection's titles and outline, which
    /// can hold text, are skipped in place and never decoded.
    static func payload(_ data: Data, session: String, modified: Date, since horizon: Date) -> Data? {
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
        guard input + cacheWrite + cacheRead + output > 0 else { return nil }
        let model = rows.object("modelSelection")?.object("val")?.object("lastUsed")?.string("model") ?? ""
        let steps = max(1, AgentLogParser.int(rows.object("sessionStats")?.object("val")?.value("steps")))
        let fields: [String: Any] = [
            "session": session,
            "createdAt": created.timeIntervalSince1970,
            "project": identity.string("cwd") ?? "",
            "model": model,
            "input": input,
            "cacheWrite": cacheWrite,
            "cacheRead": cacheRead,
            "output": output,
            "steps": steps,
        ]
        return try? JSONSerialization.data(withJSONObject: fields)
    }
}
