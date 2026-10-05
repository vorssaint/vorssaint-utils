// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AgentMeterSessionTests {
    static func run(_ suite: TestSuite) {
        discovery(suite)
    }

    private static func discovery(_ suite: TestSuite) {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "vorss-agent-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let work = home.appending(path: ".claude-work/projects")
        let empty = home.appending(path: ".codex-empty")
        let transcript = home.appending(path: ".cursor/projects/demo/agent-transcripts/abc/abc.jsonl")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: transcript.path, contents: Data("{}\n".utf8))

        let roots = AgentLogRoot.all(home: home)
        let claudeWork = roots.filter { $0.account == AgentAccount(provider: .claude, slug: "work") }
        suite.expect(claudeWork.count == 1 && claudeWork[0].url.path == work.path,
                     "a .claude-work folder with projects is its own Claude account")
        suite.expect(!roots.contains { $0.account.slug == "empty" },
                     "an extra Codex folder without sessions is not an account")
        suite.expect(roots.contains { $0.provider == .cursor && $0.account.slug.isEmpty },
                     "Cursor transcripts are a discovered root")
        let found = AgentLogReader.discover(roots.filter { $0.provider == .cursor }, since: .distantPast)
        suite.expect(found.map(\.path) == [transcript.path] && found.first?.provider == .cursor,
                     "discovery returns the Cursor transcript and not the rest of the project tree")
    }
}
