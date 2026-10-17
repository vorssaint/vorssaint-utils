// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Where Kiro CLI keeps its sessions under `~/.kiro/sessions`, and the lines
/// its files give `KiroReader` beyond its own event logs:
///
/// - `<workspace>/sess_<id>/messages.jsonl` is an append-only event log. Its
///   workspace folder and model are only in `session.json` beside it, so a
///   line describing them comes first whenever the log is read from its start.
/// - `cli/<id>.json`, from older chat sessions, is one JSON document Kiro
///   rewrites after every turn. Each turn summary in it is handed over as a
///   line of its own whenever the file changes; their keys repeat, so
///   reading it again counts nothing twice.
enum AgentKiroLog {
    static let sessionType = "kiro.session"
    static let legacyTurnType = "kiro.legacy_turn"
    static let legacyFolder = "cli"
    static let eventLog = "messages.jsonl"
    /// The document holds the whole conversation, tool output included; far
    /// beyond the largest seen, it is left unread rather than held in memory.
    static let maximumSnapshot = 256 << 20

    /// The two shapes of path a Kiro session leaves, relative to its root.
    static func accepts(_ relative: Substring) -> Bool {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty, !first.hasPrefix(".") else { return false }
        if parts.count == 2, first == legacyFolder {
            return parts[1].hasSuffix(".json") && !parts[1].hasPrefix(".")
        }
        return parts.count == 3 && first != legacyFolder && parts[1].hasPrefix("sess_") && parts[2] == eventLog
    }

    static func isSnapshot(_ path: String) -> Bool {
        path.hasSuffix(".json") && (path as NSString).deletingLastPathComponent.hasSuffix("/" + legacyFolder)
    }

    /// Kiro also keeps search indexes, tool output and locks beside the
    /// sessions; only the folders a session's files can be in are listed.
    static func logs(in root: URL) -> [URL] {
        let manager = FileManager.default
        func children(_ url: URL) -> [URL] {
            (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                              options: [.skipsHiddenFiles])) ?? []
        }
        var found: [URL] = []
        for folder in children(root) {
            if folder.lastPathComponent == legacyFolder {
                found += children(folder).filter { $0.pathExtension == "json" }
            } else {
                found += children(folder).filter { $0.lastPathComponent.hasPrefix("sess_") }
                    .map { $0.appending(path: eventLog) }
            }
        }
        return found
    }

    /// The session an event log belongs to, as `session.json` beside it
    /// describes it. The folder names the session when that file is missing.
    static func header(for log: String) -> Data {
        let folder = (log as NSString).deletingLastPathComponent
        var line: [String: Any] = ["type": sessionType, "session": (folder as NSString).lastPathComponent]
        let path = (folder as NSString).appendingPathComponent("session.json")
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path),
           (attributes[.size] as? NSNumber)?.intValue ?? .max < 1 << 20,
           let data = FileManager.default.contents(atPath: path),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let id = json["id"] as? String, !id.isEmpty { line["session"] = id }
            let folders = (json["workspacePaths"] as? [String] ?? []) + (json["rootPaths"] as? [String] ?? [])
            if let workspace = folders.first(where: { !$0.isEmpty }) { line["workspace"] = workspace }
            if let model = json["modelId"] as? String, !model.isEmpty { line["model"] = model }
        }
        return (try? JSONSerialization.data(withJSONObject: line)) ?? Data()
    }

    /// Hands over each finished turn of an older session's document, once
    /// it changed since the last reading. A document caught mid-write does
    /// not parse and is read again with the next change.
    static func readSnapshot(_ cursor: AgentLogCursor, shouldContinue: () -> Bool, line: (Data) -> Void) {
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        cursor.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        if identity == cursor.identity, size == cursor.offset, cursor.holdsWhatWasRead { return }
        guard size <= UInt64(maximumSnapshot), shouldContinue() else { return }
        let lines: [Data]? = autoreleasepool {
            guard let data = FileManager.default.contents(atPath: cursor.path),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            cursor.offset = UInt64(data.count)
            return turns(json)
        }
        guard let lines else { return }
        cursor.identity = identity
        for turn in lines where shouldContinue() { line(turn) }
        cursor.fingerprintRead()
    }

    /// Only finished turns: their summary is final once it has an end.
    private static func turns(_ json: [String: Any]) -> [Data] {
        guard let session = json["session_id"] as? String, !session.isEmpty,
              let state = json["session_state"] as? [String: Any],
              let metadata = state["conversation_metadata"] as? [String: Any],
              let turns = metadata["user_turn_metadatas"] as? [[String: Any]] else { return [] }
        let cwd = json["cwd"] as? String ?? ""
        return turns.compactMap { turn in
            guard let end = turn["end_timestamp"] as? String, !end.isEmpty else { return nil }
            let credits = (turn["metering_usage"] as? [[String: Any]] ?? []).reduce(0.0) { sum, usage in
                guard (usage["unit"] as? String)?.lowercased() == "credit",
                      let value = (usage["value"] as? NSNumber)?.doubleValue, value.isFinite, value > 0
                else { return sum }
                return sum + value
            }
            let line: [String: Any] = [
                "type": legacyTurnType, "session": session, "cwd": cwd, "end": end,
                "model": turn["model"] as? String ?? "", "credits": credits,
                "requests": AgentLogParser.int(turn["total_request_count"]),
            ]
            return try? JSONSerialization.data(withJSONObject: line)
        }
    }
}
