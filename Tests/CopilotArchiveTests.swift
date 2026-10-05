// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Compare resumed production reads with a full replay at every event boundary.
enum CopilotArchiveTests {
    static func run(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "vorss-copilot-archive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { suite.expect(false, "the Copilot archive fixture creates its folder: \(error)"); return }
        let file = folder.appending(path: "events.jsonl")
        let now = Date()
        var lines: [String] = []
        func event(_ type: String, _ data: [String: Any], agent: String? = nil) {
            var value: [String: Any] = ["type": type, "id": "event-\(lines.count)", "data": data,
                                       "timestamp": now.addingTimeInterval(Double(lines.count) - 120).timeIntervalSince1970]
            if let agent { value["agentId"] = agent }
            let bytes = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            lines.append(String(decoding: bytes, as: UTF8.self))
        }
        let model = "claude-sonnet-4.5"
        event("session.start", ["sessionId": "archive", "selectedModel": model])
        event("user.message", [:])
        event("assistant.turn_start", ["turnId": "first"])
        event("assistant.message", ["apiCallId": "root-1", "messageId": "first-response"])
        event("assistant.turn_end", ["turnId": "first"])
        event("session.shutdown", ["modelMetrics": [model: ["requests": ["count": 3],
                                                            "usage": ["inputTokens": 300_000, "outputTokens": 3_000]]]])
        event("user.message", [:])
        event("assistant.turn_start", ["turnId": "second"])
        event("assistant.message", ["apiCallId": "helper-1", "messageId": "helper-chunk"], agent: "helper")
        event("assistant.message", ["apiCallId": "root-2", "messageId": "root-chunk", "phase": "commentary"])
        event("assistant.message", ["apiCallId": "helper-1", "messageId": "helper-final", "model": model], agent: "helper")
        event("assistant.message", ["apiCallId": "root-2", "messageId": "root-final"])
        event("assistant.turn_end", ["turnId": "first"])
        event("assistant.turn_end", ["turnId": "second"])
        event("session.shutdown", ["modelMetrics": [model: ["requests": ["count": 5],
                                                            "usage": ["inputTokens": 350_000, "outputTokens": 3_500]]]])
        event("session.shutdown", ["modelMetrics": [model: ["requests": ["count": 5],
                                                            "usage": ["inputTokens": 350_000, "outputTokens": 3_500]]]])

        func write(_ lines: ArraySlice<String>) {
            try! Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8).write(to: file)
        }
        @discardableResult
        func read(_ cursor: AgentLogCursor, into store: AgentUsageStore) -> [AgentUsageEvent] {
            var events: [AgentUsageEvent] = []
            AgentLogReader.readAppended(cursor) { line in
                let entries = AgentLogParser.parseCopilot(line, state: &cursor.state, now: now)
                events += store.apply(entries, file: cursor.path, provider: .copilot, tracksTurns: true,
                                      modified: cursor.modified, now: now)
            }
            return events
        }

        write(lines[...])
        let reference = AgentUsageStore()
        let fullCursor = AgentLogCursor(path: file.path, provider: .copilot)
        read(fullCursor, into: reference)
        let expected = reference.saved
        suite.expect(reference.records.reduce(0) { $0 + $1.requests } == 5
                        && reference.records.reduce(0) { $0 + $1.tokens.input } == 350_000,
                     "the full Copilot replay has five requests and only cumulative token growth")

        for boundary in 0...lines.count {
            write(lines.prefix(boundary))
            let first = AgentUsageStore()
            let cursor = AgentLogCursor(path: file.path, provider: .copilot)
            read(cursor, into: first)
            let saved = AgentUsageArchive.Contents(providers: [.copilot], store: first.saved, cursors: [cursor.saved])
            let bytes = AgentUsageArchive.encode(saved, build: "copilot-contract")
            guard let decoded = AgentUsageArchive.decode(bytes, build: "copilot-contract") else {
                suite.expect(false, "Copilot progress decodes at boundary \(boundary)")
                continue
            }
            suite.expect(decoded == saved, "Copilot counts, aggregate prices and parser state survive boundary \(boundary)")
            let resumed = AgentUsageArchive.resume(decoded, logs: [file.path], since: .distantPast)
            guard let restored = resumed.cursors[file.path] else {
                suite.expect(false, "Copilot resumes its saved cursor at boundary \(boundary)")
                continue
            }
            // Populate cached summaries before a later chunk resolves a model.
            _ = resumed.store.snapshot(plans: [:], providers: [.copilot], now: now)
            let continuation = AgentUsageStore(saved: first.saved)
            resumed.store.reportsTransitions = true
            continuation.reportsTransitions = true
            if let handle = try? FileHandle(forWritingTo: file) {
                _ = try? handle.seekToEnd()
                let tail = lines.suffix(from: boundary)
                try? handle.write(contentsOf: Data((tail.joined(separator: "\n") + (tail.isEmpty ? "" : "\n")).utf8))
                try? handle.close()
            }
            let freshEvents = read(cursor, into: continuation)
            let resumedEvents = read(restored, into: resumed.store)
            suite.expect(resumed.store.saved == expected && restored.state == fullCursor.state,
                         "Copilot resume equals full replay at boundary \(boundary)")
            suite.expect(resumedEvents == freshEvents,
                         "Copilot completion and stale-turn handling survive boundary \(boundary)")
            let cached = resumed.store.snapshot(plans: [:], providers: [.copilot], now: now)
            let fresh = AgentUsageSummary.snapshot(records: reference.records, limits: [:], live: [], plans: [:],
                                                   providers: [.copilot], now: now)
            suite.expect(cached.periods == fresh.periods && cached.days == fresh.days,
                         "Copilot resumed model attribution and aggregate repricing agree at boundary \(boundary)")
        }
    }
}
