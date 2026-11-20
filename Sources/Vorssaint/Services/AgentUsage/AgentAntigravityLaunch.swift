// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How agy started a subagent or a swarm worker. Their transcripts have no
/// `Model Selection` line. agy keeps the tool call that started each one with
/// its first message, in the conversation's `messages` folder; only the
/// conversation that made the call, its time and the model it asked for are
/// read from it.
enum AgentAntigravityLaunch {
    enum Model: Equatable {
        /// The model the starting conversation ran on at that time.
        case inherited
        case named(String)
    }

    struct Launch: Equatable {
        let parent: String
        let date: Date
        /// Nil when the call asked for a tier ("flash", "pro") that names no model.
        let model: Model?
    }

    private static let lock = NSLock()
    private static var cache: [String: (stamp: [Int64], launch: Launch?)] = [:]
    private static let maximumMessages = 500
    private static let efforts: Set<String> = ["minimal", "low", "medium", "high", "xhigh", "max"]

    /// The call that started the conversation a `transcript.jsonl` belongs to,
    /// or nil for a conversation a person started. Read again only when the
    /// `messages` folder changed.
    static func launch(forTranscript path: String) -> Launch? {
        // <session>/.system_generated/logs/transcript.jsonl
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "messages", directoryHint: .isDirectory)
        var info = stat()
        guard stat(folder.path, &info) == 0 else { return nil }
        let stamp = [Int64(info.st_mtimespec.tv_sec), Int64(info.st_mtimespec.tv_nsec)]
        if let cached = lock.withLock({ cache[folder.path] }), cached.stamp == stamp { return cached.launch }
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".json") && $0 != "read.json" }.prefix(maximumMessages)
        let launch = names.compactMap { name in
            (try? Data(contentsOf: folder.appending(path: name, directoryHint: .notDirectory))).flatMap(launch(fromMessage:))
        }.min { $0.date < $1.date }
        lock.withLock { cache[folder.path] = (stamp, launch) }
        return launch
    }

    /// The launch a message file records, or nil when the message came from
    /// anything but the call that starts a subagent or a swarm worker.
    static func launch(fromMessage data: Data) -> Launch? {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tool = (message["sourceMetadata"] as? [String: Any])?["tool"] as? [String: Any],
              let parent = tool["conversationId"] as? String, !parent.isEmpty,
              let call = tool["toolCall"] as? [String: Any], let name = call["name"] as? String,
              let date = (message["timestamp"] as? String).flatMap(AgentTimestamp.parse),
              let text = call["argumentsJson"] as? String, let json = text.data(using: .utf8),
              let arguments = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        let parentID = AgentLogParser.native(parent)
        switch name {
        case "invoke_subagent":
            let asked: String?
            if let batch = arguments["Subagents"] as? [[String: Any]] {
                // One call starts several; the one whose prompt this message carries is this conversation's.
                let models = Set(batch.map { $0["Model"] as? String ?? "inherit" })
                let content = message["content"] as? String
                asked = models.count == 1 ? models.first
                    : batch.first { $0["Prompt"] as? String == content }.map { $0["Model"] as? String ?? "inherit" }
            } else {
                asked = arguments["Model"] as? String ?? "inherit"
            }
            return Launch(parent: parentID, date: date, model: asked == "inherit" ? .inherited : nil)
        case "swarm":
            guard arguments["action"] as? String == "add" else { return nil }
            guard let asked = arguments["model"] as? String, !asked.isEmpty else {
                return Launch(parent: parentID, date: date, model: .inherited)
            }
            return Launch(parent: parentID, date: date, model: model(named: asked).map(Model.named))
        default:
            return nil
        }
    }

    /// The model a swarm worker was pinned to. The swarm names a model by its
    /// family, version and effort ("opus-5.5-max"), or by the name the model
    /// picker shows; "auto" names none.
    static func model(named name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "auto" else { return nil }
        guard !name.contains(" ") else { return AgentLogParser.native(name) }
        var parts = name.split(separator: "-").map(String.init)
        if let last = parts.last, parts.count > 1, efforts.contains(last) { parts.removeLast() }
        // The swarm leaves "claude" out of a Claude model's name; the price list says which families are Claude's.
        let claudeFamilies = Set(AgentPricing.list.claude.compactMap { $0.id.split(separator: "-").dropFirst().first })
        if let family = parts.first, claudeFamilies.contains(Substring(family)) { parts.insert("claude", at: 0) }
        return AgentLogParser.native(parts.joined(separator: "-"))
    }
}
