// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Tests discovery of local chat session activity dates for agents without logs.
enum AgentLocalActivityTests {
    static func run(_ suite: TestSuite) {
        antigravityActivity(suite)
        antigravityMultipleRoots(suite)
        defaultRoots(suite)
    }

    private static func antigravityActivity(_ suite: TestSuite) {
        suite.run("Antigravity local activity") {
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-antigravity-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            suite.expect(AgentLocalActivity.latestActivity(for: .antigravity, root: tempDir) == nil,
                         "missing directory returns nil")

            let convDir = tempDir.appending(path: "conversations")
            try? FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)

            let now = Date()
            let oldDate = now.addingTimeInterval(-7200)
            let newestDate = now.addingTimeInterval(-300)
            let lockDate = now.addingTimeInterval(-10)

            let oldFile = convDir.appending(path: "old-conv.pb")
            let newestFile = convDir.appending(path: "recent-conv.db")
            let lockFile = convDir.appending(path: "session.lock")

            try? Data("pb".utf8).write(to: oldFile)
            try? Data("db".utf8).write(to: newestFile)
            try? Data("lock".utf8).write(to: lockFile)

            try? FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldFile.path)
            try? FileManager.default.setAttributes([.modificationDate: newestDate], ofItemAtPath: newestFile.path)
            try? FileManager.default.setAttributes([.modificationDate: lockDate], ofItemAtPath: lockFile.path)

            let result = AgentLocalActivity.latestActivity(for: .antigravity, root: tempDir)
            suite.expect(result != nil, "finds antigravity activity date")
            if let result {
                suite.expect(abs(result.timeIntervalSince(newestDate)) < 2,
                             "picks newest conversation file mtime ignoring lock file")
            }

            let directResult = AgentLocalActivity.latestActivity(for: .antigravity, root: convDir)
            suite.expect(directResult != nil, "resolves when root is the conversations directory directly")
        }
    }

    private static func antigravityMultipleRoots(_ suite: TestSuite) {
        suite.run("Antigravity multiple roots with CLI and WAL") {
            let tempDir = FileManager.default.temporaryDirectory.appending(path: "test-antigravity-multi-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let cliDir = tempDir.appending(path: ".gemini/antigravity-cli/conversations")
            let ideDir = tempDir.appending(path: ".gemini/antigravity/conversations")
            try? FileManager.default.createDirectory(at: cliDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: ideDir, withIntermediateDirectories: true)

            let now = Date()
            let ideDate = now.addingTimeInterval(-86400 * 10)
            let cliDbDate = now.addingTimeInterval(-3600)
            let cliWalDate = now.addingTimeInterval(-60)

            let ideFile = ideDir.appending(path: "old-session.db")
            let cliDbFile = cliDir.appending(path: "active-session.db")
            let cliWalFile = cliDir.appending(path: "active-session.db-wal")

            try? Data("ide".utf8).write(to: ideFile)
            try? Data("clidb".utf8).write(to: cliDbFile)
            try? Data("cliwal".utf8).write(to: cliWalFile)

            try? FileManager.default.setAttributes([.modificationDate: ideDate], ofItemAtPath: ideFile.path)
            try? FileManager.default.setAttributes([.modificationDate: cliDbDate], ofItemAtPath: cliDbFile.path)
            try? FileManager.default.setAttributes([.modificationDate: cliWalDate], ofItemAtPath: cliWalFile.path)

            let roots = AgentLocalActivity.defaultRoots(for: .antigravity, home: tempDir)
            suite.expect(roots.count == 2, "antigravity has 2 default roots")

            let latest = AgentLocalActivity.latestActivity(for: .antigravity, roots: roots)
            suite.expect(latest != nil, "finds activity across roots")
            if let latest {
                suite.expect(abs(latest.timeIntervalSince(cliWalDate)) < 2,
                             "picks newest CLI .db-wal date over older IDE conversation")
            }
        }
    }

    private static func defaultRoots(_ suite: TestSuite) {
        suite.run("Default activity roots") {
            let fakeHome = URL(fileURLWithPath: "/tmp/fake-user-home")
            let cmdRoots = AgentLocalActivity.defaultRoots(for: .commandcode, home: fakeHome)
            suite.expect(cmdRoots.isEmpty, "command code has no local activity roots")

            let agyRoots = AgentLocalActivity.defaultRoots(for: .antigravity, home: fakeHome)
            suite.expect(agyRoots.map(\.path) == [
                "/tmp/fake-user-home/.gemini/antigravity-cli/conversations",
                "/tmp/fake-user-home/.gemini/antigravity/conversations"
            ], "antigravity roots include both CLI and IDE paths")

            suite.expect(AgentLocalActivity.defaultRoots(for: .claude, home: fakeHome).isEmpty,
                         "claude has no local activity roots")
        }
    }
}
