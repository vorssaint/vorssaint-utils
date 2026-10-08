// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

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

    /// The Harness app, the only thing that writes the projections.
    static let bundle = "com.deepseek.dsh"

    /// Whether the Harness is running. A turn it was in the middle of when it
    /// quit stays marked open in the projection, so this is what ends it.
    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

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
            "open": open(rows, stats),
            // The prompt's time dates the turn the person is waiting on. The
            // counters are what say whether it is still going: the projection
            // is rewritten for reasons unrelated to work, so neither its
            // arrival nor its own time is evidence of anything.
            "started": prompt(rows).timeIntervalSince1970,
            "steps": int(stats.value("steps")),
            "output": amount(usage, "totals", "outputTokens"),
            // The event the turn's bookkeeping last moved at. It advances as
            // each step begins and ends, and only then.
            "seq": int(rows.object("turnBoundary")?.value("seq")),
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

    /// Whether the Harness has a turn open. It records the event a turn
    /// began at and clears it when the turn is over, finished or stopped, so
    /// this holds through the gaps between steps, when no step is open and no
    /// tool call is outstanding, and is false the moment the turn ends.
    ///
    /// It says the turn was open when the projection was last written, not
    /// that the Harness is running this instant: one quit mid-turn leaves it
    /// set. The parser opens a turn only on progress, never on this alone.
    private static func open(_ rows: AgentLogObject, _ stats: AgentLogObject) -> Bool {
        if let boundary = rows.object("turnBoundary")?.object("val") {
            guard let start = boundary.value("openTurnStartSeq") else { return false }
            return !(start is NSNull)
        }
        // Without the turn's own record, an open step or a tool call still
        // out is the nearest sign, though both lapse between steps.
        if let step = stats.value("openStep"), !(step is NSNull) { return true }
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
