// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CursorAgentDiscoveryTests {
    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appending(path: "vorss-cursor-discovery-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: temp) }
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            // An ancestor called "projects" is legitimate, e.g. in a mounted home.
            let home = AgentLogRoot.canonical(temp).appending(path: "projects/demo")
            let encoded = home.path.split(separator: "/").joined(separator: "-")
            let root = AgentLogRoot(provider: .cursor, url: home.appending(path: ".cursor/projects"))
            let transcripts = root.url.appending(path: "\(encoded)-work-client/agent-transcripts")
            try fm.createDirectory(at: transcripts, withIntermediateDirectories: true)
            suite.expect(AgentLogRoot.all(home: home).contains { $0.provider == .cursor && $0.url.path == root.url.path },
                         "Cursor discovery starts in the current home's .cursor/projects")
            let emptyWindow = root.url.appending(path: "empty-window/agent-transcripts/chat.jsonl")
            suite.expect(AgentLogParser.cursorProject(from: emptyWindow.path) == "empty-window",
                         "a workspace slug without an encoded home keeps its name")
            let tools = transcripts.deletingLastPathComponent().appending(path: "agent-tools")
            try fm.createDirectory(at: tools, withIntermediateDirectories: true)
            let toolOutput = tools.appending(path: "tool.jsonl")
            try Data().write(to: toolOutput)
            suite.expect(!root.accepts(toolOutput.path), "a Cursor tool file is ignored by the file watcher")
            try fm.createDirectory(at: home.appending(path: "work"), withIntermediateDirectories: true)
            try fm.createDirectory(at: home.appending(path: "work-client"), withIntermediateDirectories: true)
            let flat = transcripts.appending(path: "abc.jsonl")
            let nested = transcripts.appending(path: "abc/abc.jsonl")
            try Data().write(to: flat)
            try fm.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: root.url.appending(path: "index.txt"))
            let access = CursorTranscriptAccess(root: root.url)
            let files = CursorTranscriptFiles(path: flat.path)
            suite.expect(files.preferred(in: access)?.path == flat.path,
                         "a session folder with no matching file leaves the flat transcript active")
            let otherRoot = home.appending(path: "another-profile/projects")
            try fm.createDirectory(at: otherRoot, withIntermediateDirectories: true)
            suite.expect(files.preferred(in: CursorTranscriptAccess(root: otherRoot)) == nil,
                         "a different profile only selects transcripts from its own root")
            func discovered() -> [String] {
                AgentLogReader.discover([root], since: .distantPast).map(\.path)
            }
            suite.expect(root.accepts(flat.path) && discovered() == [flat.path],
                         "flat Cursor transcripts are discovered and admitted on file events")
            suite.expect(AgentLogParser.cursorProject(from: flat.path) == "work-client",
                         "an existing hyphenated workspace wins over a nonexistent nested path")
            try fm.removeItem(at: home.appending(path: "work-client"))
            try fm.createDirectory(at: home.appending(path: "work/client"), withIntermediateDirectories: true)
            suite.expect(AgentLogParser.cursorProject(from: nested.path) == "client",
                         "a genuinely nested workspace still yields its last folder")

            let date = Date()
            let store = AgentUsageStore()
            var cursors = [flat.path: AgentLogCursor(path: flat.path, provider: .cursor)]
            let entries: [AgentLogEntry] = [.turnBegan(date), .turnContext(model: "", project: "client")]
            store.apply(entries, file: flat.path, provider: .cursor, tracksTurns: true, modified: date)
            try Data().write(to: nested)
            suite.expect(root.accepts(nested.path) && discovered() == [nested.path],
                         "coexisting flat and nested Cursor files produce only the nested session")
            let oldEvent = files.select(root: root.url, cursors: &cursors, store: store)
            suite.expect(oldEvent.path == nested.path && oldEvent.changed && cursors.isEmpty &&
                         store.records.isEmpty && store.live.isEmpty,
                         "an event for the old flat copy switches files and retracts its live turn")
            cursors[nested.path] = AgentLogCursor(path: nested.path, provider: .cursor)
            store.apply(entries, file: nested.path, provider: .cursor, tracksTurns: true, modified: date)
            let duplicate = files.select(root: root.url, cursors: &cursors, store: store)
            suite.expect(duplicate.path == nested.path && !duplicate.changed &&
                         store.records.isEmpty && store.live.count == 1,
                         "later events on the flat copy leave the current turn intact")
            try fm.removeItem(at: nested)
            let removed = CursorTranscriptFiles(path: nested.path).select(root: root.url, cursors: &cursors, store: store)
            suite.expect(removed.path == flat.path && removed.changed && discovered() == [flat.path] &&
                         cursors.isEmpty && store.live.isEmpty && store.records.isEmpty,
                         "deleting the preferred file falls back to the surviving flat transcript")
            suite.expect(!root.accepts(transcripts.appending(path: "abc/subagents/child.jsonl").path) &&
                         !root.accepts(transcripts.appending(path: "abc/other.jsonl").path),
                         "a nested subagent or an unrelated file does not become a Cursor session")
            try linkedPaths(suite, temp: AgentLogRoot.canonical(temp))
        } catch {
            suite.expect(false, "could not prepare Cursor transcripts: \(error)")
        }
    }

    private static func linkedPaths(_ suite: TestSuite, temp: URL) throws {
        let fm = FileManager.default
        let home = temp.appending(path: "linked-profile")
        let config = home.appending(path: ".cursor")
        let storage = temp.appending(path: "transcript-storage")
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: config.appending(path: "projects"), withDestinationURL: storage)
        guard let root = AgentLogRoot.all(home: home, providers: [.cursor]).first else {
            suite.expect(false, "the configured Cursor projects directory has a log root")
            return
        }
        let project = storage.appending(path: "workspace")
        let transcripts = project.appending(path: "agent-transcripts")
        let session = transcripts.appending(path: "chat")
        let nested = session.appending(path: "chat.jsonl")
        let flat = transcripts.appending(path: "chat.jsonl")
        try fm.createDirectory(at: session, withIntermediateDirectories: true)
        try Data().write(to: nested)
        let files = CursorTranscriptFiles(path: nested.path)
        func discovered() -> [String] {
            AgentLogReader.discover([root], since: .distantPast).map(\.path)
        }
        suite.expect(root.url.path == storage.path && discovered() == [nested.path],
                     "a configured projects alias is followed once to the canonical root and reads a regular transcript")

        let store = AgentUsageStore()
        let parked = storage.appending(path: ".fixture")
        for component in [project, transcripts, session, nested] {
            var cursors = [nested.path: AgentLogCursor(path: nested.path, provider: .cursor)]
            // Keep the same empty fixture inside the root. Only the kind of
            // path at this level changes between these sequential checks.
            try fm.moveItem(at: component, to: parked)
            try fm.createSymbolicLink(at: component, withDestinationURL: parked)
            let rejected = files.select(root: root.url, cursors: &cursors, store: store)
            suite.expect(discovered().isEmpty && rejected.path == nil && rejected.changed && cursors.isEmpty,
                         "a link at \(component.lastPathComponent) is skipped by discovery and drops the stale cursor")
            if component == session {
                try Data().write(to: flat)
                let fallback = files.select(root: root.url, cursors: &cursors, store: store)
                suite.expect(discovered() == [flat.path] && fallback.path == flat.path,
                             "a rejected nested session leaves the independent regular flat transcript available")
                try fm.removeItem(at: flat)
            }
            try fm.removeItem(at: component)
            try fm.moveItem(at: parked, to: component)
        }
        suite.expect(discovered() == [nested.path], "restoring the regular transcript makes it discoverable again")
    }
}
