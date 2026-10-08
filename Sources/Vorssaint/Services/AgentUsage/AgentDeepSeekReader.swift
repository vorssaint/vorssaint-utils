// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads the DeepSeek Harness's session projections.
///
/// The Harness writes its session as a zstd-compressed event stream
/// (`session.v4.jsonl.zstd`), which nothing in this app can read without a
/// decompressor it deliberately does not carry. It also keeps a plain JSON
/// projection of each session under `~/.dsh/storages/session_projcache`,
/// updated as the session runs, and that is what this reads.
///
/// A projection is the current state of a session, not a log: it is rewritten
/// whole rather than appended to, so every read restarts the parser instead of
/// continuing from an offset. The parser is handed one object per session, and
/// what it counts is keyed so that reading the same state twice counts it once.
///
/// Only the small fields below are looked at. Prompts, replies, tool calls,
/// their arguments and their output never leave the file, and nothing is copied
/// into the store.
enum AgentDeepSeekReader {
    /// The folder the Harness keeps one projection per session in.
    static let sessions = ".dsh/storages/session_projcache/sessions"

    /// The projection's own version. A newer one is left alone rather than
    /// read as if it still held these fields.
    static let version = 7

    /// Reads one session's projection and hands the parser a single object of
    /// the values it needs.
    static func read(_ path: String, shouldContinue: () -> Bool = { true }, line: (Data) -> Void) {
        guard shouldContinue(), let data = FileManager.default.contents(atPath: path),
              let file = AgentLogObject(data),
              int(file.value("version")) == version,
              let record = file.object("record"),
              let identity = record.object("identity"),
              let rows = record.object("rows"),
              let usage = rows.object("tokenUsage")?.object("val"),
              let stats = rows.object("sessionStats")?.object("val") else { return }

        // The projection does not repeat the session's id inside itself; the
        // Harness names the file after it, so the file's own name is the id.
        let id = identity.string("id") ?? (path as NSString).lastPathComponent
        var payload: [String: Any] = [
            "type": "state",
            "session": id,
            "tokens": ["input": amount(usage, "totals", "uncachedInputTokens"),
                       "cacheWrite": amount(usage, "totals", "cacheWriteTokens"),
                       "cacheRead": amount(usage, "totals", "cacheReadTokens"),
                       "output": amount(usage, "totals", "outputTokens")],
            "turn": int(stats.value("lastTurn")),
            "working": working(stats),
            // The prompt's time dates the turn the person is waiting on. The
            // counters are what say whether it is still going: the projection
            // is rewritten for reasons unrelated to work, so neither its
            // arrival nor its own time is evidence of anything.
            "started": prompt(rows).timeIntervalSince1970,
            "steps": int(stats.value("steps")),
            "output": amount(usage, "totals", "outputTokens"),
            // The one thing the projection says about the loop waiting on the
            // person: an outstanding question shows up here. It carries no
            // tool names, so this is the only readable sign of it.
            "waitingForAnswer": !((rows.object("userQuestions")?.object("val")?
                .object("questions")?.value("active") as? [Any]) ?? []).isEmpty,
        ]
        if let cwd = identity.string("cwd"), !cwd.isEmpty { payload["cwd"] = cwd }
        if let model = rows.object("modelSelection")?.object("val")?.object("lastUsed")?.string("model"),
           !model.isEmpty {
            payload["model"] = model
        }
        guard shouldContinue(), let encoded = try? JSONSerialization.data(withJSONObject: payload) else { return }
        line(encoded)
    }

    /// Whether the Harness is mid-turn. It is while a step is open, and also
    /// between steps while a tool call it made has not come back yet: the loop
    /// is waiting on that call rather than finished with the turn.
    ///
    /// This says the session was mid-turn when it was last written, not that it
    /// is running this instant. A stopped Harness leaves its last step open, so
    /// a turn is only held open while the projection keeps being written; the
    /// store ends one whose file has gone quiet.
    private static func working(_ stats: AgentLogObject) -> Bool {
        // An open step is written as an object, and as null once it closes.
        if let open = stats.value("openStep"), !(open is NSNull) { return true }
        guard let pending = stats.value("pendingCalls") as? [String: Any] else { return false }
        return !pending.isEmpty
    }

    /// When the turn being answered was asked for.
    private static func prompt(_ rows: AgentLogObject) -> Date {
        guard let metadata = rows.object("sessionListMetadata")?.object("val"),
              let lastPrompt = number(metadata.value("lastPromptAt")) else { return .distantPast }
        return AgentLogParser.seconds(lastPrompt) ?? .distantPast
    }

    /// A small integer field, read through the path of the object holding it.
    private static func amount(_ object: AgentLogObject, _ path: String, _ key: String) -> Int {
        guard let holder = object.object(path) else { return 0 }
        return int(holder.value(key))
    }

    private static func int(_ value: Any?) -> Int {
        guard let value = number(value) else { return 0 }
        let double = value.doubleValue
        guard double.isFinite, double > 0 else { return 0 }
        return Int(min(double, 1e12))
    }

    /// A JSON number, and only a number. Foundation bridges JSON booleans to
    /// `NSNumber`, and `NSNumber(value: 1) is Bool` is true while
    /// `NSNumber(value: true) is Bool` is true as well, so a guard over the
    /// bridged Swift type cannot separate them. This is the check the pricing
    /// list and the Claude app reader already use.
    private static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number
    }
}
