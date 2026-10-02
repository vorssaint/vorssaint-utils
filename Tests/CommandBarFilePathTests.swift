// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarFilePathTests {
    static func run(_ suite: TestSuite) {
        suite.expect(CommandBarFileSearchSupport.explicitPath(
            for: "~/Library/Application Support/应用/config.json", homeDirectory: "/Users/test")
            == "/Users/test/Library/Application Support/应用/config.json",
            "explicit paths expand home and preserve spaces and Chinese names")
        suite.expect(CommandBarFileSearchSupport.explicitPath(
            for: "/tmp/$HOME/$(echo test)*.txt", homeDirectory: "/Users/test")
            == "/tmp/$HOME/$(echo test)*.txt",
            "explicit paths do not expand shell variables, commands or wildcards")
        for query in ["report.txt", "../report.txt", "~someone/report.txt", "file:///tmp/a", "/tmp/a\0b"] {
            suite.expect(CommandBarFileSearchSupport.explicitPath(
                for: query, homeDirectory: "/Users/test") == nil,
                "only absolute paths and current-user home paths are resolved: \(query)")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-path-tests-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Library/Application Support/应用")
        let file = folder.appendingPathComponent("记录 2026.txt")
        let hidden = folder.appendingPathComponent(".settings")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: file)
            try Data().write(to: hidden)
        } catch {
            suite.expect(false, "create explicit-path fixtures: \(error)")
            try? FileManager.default.removeItem(at: root)
            return
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let search = CommandBarFileSearch()
        defer { search.reset() }
        var published: [String] = []
        func resolve(_ query: String) -> [String]? {
            search.onResult = { published.append(query) }
            // No configured scopes; discovery exclusions also cover the fixture.
            search.schedule(query: query, scopes: [], patterns: ["*.txt", "Library"])
            wait { search.cachedPaths(for: query) != nil }
            return search.cachedPaths(for: query)
        }
        suite.expect(resolve(file.path) == [file.path],
            "a full path outside search scopes returns the existing file")
        suite.expect(resolve(folder.path) == [folder.path],
            "a full directory path is offered without searching its children")
        suite.expect(resolve(hidden.path) == [hidden.path],
            "an explicitly requested hidden file is offered without discovery")
        suite.expect(resolve("~/") == [NSHomeDirectory() + "/"],
            "home shorthand resolves through the production asynchronous lookup")
        suite.expect(resolve("/") == ["/"],
            "the root path bypasses the two-character filename search minimum")
        suite.expect(resolve(folder.appendingPathComponent("missing.txt").path) == [],
            "a nonexistent full path produces no file row")
        suite.expect(published.count == 6,
            "each completed path lookup publishes once")

        search.reset()
        published = []
        search.onResult = { published.append("unexpected") }
        search.schedule(query: file.path, scopes: [], patterns: [])
        search.reset()
        // Let the cancelled debounce pass; it must not repopulate the next session.
        RunLoop.main.run(until: Date().addingTimeInterval(CommandBarFileSearch.debounce * 2))
        suite.expect(search.cachedPaths(for: file.path) == nil && published.isEmpty,
            "closing the bar cancels a queued explicit-path lookup")

        search.schedule(query: file.path, scopes: [], patterns: [])
        suite.expect(resolve(folder.path) == [folder.path]
            && search.cachedPaths(for: file.path) == nil && published == [folder.path],
            "typing a new path supersedes the old pending lookup")
    }

    private static func wait(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
}
