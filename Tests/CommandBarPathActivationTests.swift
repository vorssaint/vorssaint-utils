// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

typealias PathActivationQueryHabits = CommandBarQueryHabits

/// The generated service executes the production query observer, result
/// assembly and selection methods. Only the catalog and panel are replaced;
/// path resolution still goes through the real asynchronous file search.
enum CommandBarPathActivationTests {
    enum CommandBarQueryHabits {
        typealias PreparationCache = PathActivationQueryHabits.PreparationCache
        static let key = Data(repeating: 11, count: 32)
        static func prepare(_ query: String,
                            cache: inout PreparationCache) -> PathActivationQueryHabits.PreparedQuery {
            PathActivationQueryHabits.prepare(query, key: key, cache: &cache)
        }
        static func boost(for id: String,
                          preparedQuery: PathActivationQueryHabits.PreparedQuery,
                          store: PathActivationQueryHabits.Store,
                          now: Double) -> Int {
            PathActivationQueryHabits.boost(for: id, preparedQuery: preparedQuery, store: store, now: now)
        }
    }

    struct CommandBarEntry {
        let id: String
        let title: String
        var revealPath: String?
        var stableKey: String { id }
        var keywords: String { title }
        var countsUsage: Bool { false }
        var takesArgument: Bool { false }
        var matchTitle: String? { nil }
        var numericRange: ClosedRange<Int>? { nil }
        var isActive: Bool { false }
    }

    struct Bar { let quitFormat = "Quit %@" }
    enum FeatureStrings {
        static func commandBar(_ language: Int) -> Bar { Bar() }
    }
    enum L10n {
        static var shared: Self.Type { Self.self }
        static var language: Int { 0 }
    }
    enum AppUninstaller {
        static var shared: Self.Type { Self.self }
        static func reset() {}
    }
    enum Preferences {
        static var standard: Self.Type { Self.self }
        static func string(forKey: String) -> String? { nil }
        static func data(forKey: String) -> Data? { nil }
    }
    final class ScriptRunner {
        var isAwaiting: Bool { false }
        func cancelPending() {}
        func cachedResult(linkID: UUID, argument: String) -> String? { nil }
        func schedule(link: CommandBarLink, argument: String) {}
    }
    enum Catalog {
        static var clipboard: [CommandBarEntry] = []
        static var clipboardQueries: [String] = []
        static func answerEntry(for query: String, bar: Bar) -> CommandBarEntry? { nil }
        static func openURLEntry(for query: String, bar: Bar) -> CommandBarEntry? { nil }
        static func scriptAnswerEntry(link: CommandBarLink, result: String,
                                      bar: Bar) -> CommandBarEntry? { nil }
        static func clipboardEntries(matching query: String, bar: Bar, limit: Int = 4,
                                     paste: (CommandBarEntry) -> Void) -> [CommandBarEntry] {
            clipboardQueries.append(query)
            return clipboard
        }
        static func fileEntries(_ paths: [String], bar: Bar) -> [CommandBarEntry] {
            paths.map { CommandBarEntry(id: "file.\($0)",
                                        title: URL(fileURLWithPath: $0).lastPathComponent,
                                        revealPath: $0) }
        }
    }

    class Fixture {
        typealias CommandBarService = Service
        typealias CommandBarCatalog = Catalog
        typealias UserDefaults = Preferences
        static let chipOrder: [CommandBarSource] = []
        static let kindLimits: [(prefix: String, limit: Int)] = []
        let fileSearch = CommandBarFileSearch()
        let scriptRunner = ScriptRunner()
        var uninstallWarning: String?
        var uninstallFinderRequestID: UUID?
        var queryBeforeCompletion: String?
        var completedQuery: String?
        var mode = Mode.search
        var rows: [CommandBarEntry] = []
        var selectedIndex = 0
        var selectedID: String?
        var lastRankedQuery: String?
        var selectionWasMoved = false
        var sectionTitles: [Int: String] = [:]
        var categoryChips: [CommandBarSource] = []
        var activeCategory: CommandBarSource?
        var isTearingDown = false
        var presentationLifecycle = CommandBarPresentationLifecycle()
        var builtLanguage: Int?
        var compactMode = false
        var isPeekingHome = false
        var isCompactHome = false
        var isShowingSuggestions = false
        var awaitsAnswers = false
        var disabledCache: Set<CommandBarSource> = []
        var hiddenCache: Set<String> = []
        var fileScopeCache: [String] = []
        var fileIgnoreCache: [String] = []
        var aliasCache: [String: String] = [:]
        var pinCache: Set<String> = []
        var usageCache: [String: CommandBarUse] = [:]
        var preparedHabitQuery = CommandBarQueryHabits.PreparationCache()
        var queryHabitStore = CommandBarQueryHabitStoreCache()
        var queryMemory = CommandBarQueryMemory()
        var normalizedByID: [String: (title: String, keywords: String)] = [:]
        var selectionEntries: [CommandBarEntry] = []
        var uninstallSelectionEntries: [CommandBarEntry] = []
        var catalog: [CommandBarEntry] = []
        var appEntries: [CommandBarEntry] = []
        var macSettingsEntries: [CommandBarEntry] = []
        var windowEntries: [CommandBarEntry] = []
        var quitEntries: [CommandBarEntry] = []
        var menuEntries: [CommandBarEntry] = []
        func rebuildCatalog(index: Bool) {}
        func rebuildRunningEntries() {}
        func refreshPanelLayout() {}
        func paste(_ entry: CommandBarEntry) {}
        func categoryHasContent(_ category: CommandBarSource) -> Bool { false }
        func categoryContent(_ category: CommandBarSource, bar: Bar) -> [CommandBarEntry] { [] }
        func categoryHeading(_ category: CommandBarSource, count: Int) -> String { "" }
        func suggestionRows() -> (rows: [CommandBarEntry], titles: [Int: String]) { ([], [:]) }
        func isEnabled(_ source: CommandBarSource) -> Bool { !disabledCache.contains(source) }
    }

    private static func service(clipboardQuery: String) -> Service {
        Catalog.clipboard = (0..<2).map {
            CommandBarEntry(id: "clipboard.\($0)", title: clipboardQuery)
        }
        Catalog.clipboardQueries = []
        let service = Service()
        service.fileSearch.onResult = { [weak service] in service?.refreshResults() }
        return service
    }

    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-path-activation-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for name in ["report", "report ", "report\t"] {
                try Data(name.utf8).write(to: root.appendingPathComponent(name))
            }
        } catch {
            suite.expect(false, "create command bar path fixtures: \(error)")
            try? FileManager.default.removeItem(at: root)
            return
        }
        defer {
            Catalog.clipboard = []
            Catalog.clipboardQueries = []
            try? FileManager.default.removeItem(at: root)
        }

        for suffix in [" ", "\t"] {
            let path = root.appendingPathComponent("report" + suffix).path
            let host = service(clipboardQuery: path)
            defer { host.fileSearch.reset() }
            host.query = path
            wait { !host.fileSearch.isAwaiting }
            suite.expect(host.fileSearch.cachedPaths(for: path) == [path],
                         "the query observer preserves a path's trailing \(suffix.debugDescription)")
            suite.expect(host.rows.first?.revealPath == path,
                         "the exact path leads over the existing file with a trimmed name")
        }

        let path = root.appendingPathComponent("report").path
        do {
            let host = service(clipboardQuery: path)
            defer { host.fileSearch.reset() }
            host.query = path
            suite.expect(host.selectedEntry?.id == "clipboard.0" && host.fileSearch.isAwaiting,
                         "the clipboard is the default selection while path resolution waits")
            wait { !host.fileSearch.isAwaiting }
            suite.expect(host.rows.first?.revealPath == path && host.selectedEntry?.revealPath == path,
                         "a completed exact path becomes the default Return target")
        }

        for useKeyboard in [true, false] {
            let host = service(clipboardQuery: path)
            defer { host.fileSearch.reset() }
            host.query = path
            if useKeyboard { host.moveSelection(1) } else { host.select(1) }
            suite.expect(host.selectedEntry?.id == "clipboard.1",
                         "the user deliberately selects the second clipboard row")
            wait { !host.fileSearch.isAwaiting }
            suite.expect(host.rows.first?.revealPath == path && host.selectedEntry?.id == "clipboard.1",
                         "an asynchronous path does not override an explicit \(useKeyboard ? "keyboard" : "row") selection")
        }

        do {
            let host = service(clipboardQuery: path)
            defer { host.fileSearch.reset() }
            host.query = path
            wait { !host.fileSearch.isAwaiting }
            if let index = host.rows.firstIndex(where: { $0.id == "clipboard.1" }) {
                host.select(index)
            }
            suite.expect(host.selectedEntry?.id == "clipboard.1",
                         "an explicit choice is established for the original path")
            host.query = path + " "
            wait { !host.fileSearch.isAwaiting }
            suite.expect(host.selectedEntry?.revealPath == path + " ",
                         "adding trailing whitespace starts a new path query and resets the prior explicit choice")
        }

        do {
            let host = service(clipboardQuery: path)
            defer { host.fileSearch.reset() }
            host.disabledCache.insert(.files)
            host.query = path
            suite.expect(!host.fileSearch.isAwaiting && host.rows.allSatisfy { $0.revealPath == nil }
                         && host.selectedEntry?.id == "clipboard.0",
                         "a disabled Files source neither resolves nor selects a pasted path")
        }

        do {
            let host = service(clipboardQuery: path)
            defer { host.fileSearch.reset() }
            host.hiddenCache.insert("file.\(path)")
            host.query = path
            wait { !host.fileSearch.isAwaiting }
            suite.expect(host.fileSearch.cachedPaths(for: path) == [path]
                         && host.rows.allSatisfy { $0.revealPath == nil }
                         && host.selectedEntry?.id == "clipboard.0",
                         "a hidden exact file is excluded from rows and automatic selection")
        }

        do {
            let host = service(clipboardQuery: "report")
            defer { host.fileSearch.reset() }
            host.query = " \treport\t "
            suite.expect(Catalog.clipboardQueries.last == "report" && host.selectedEntry?.id == "clipboard.0",
                         "ordinary text still reaches search and ranking without surrounding whitespace")
        }
    }

    private static func wait(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }
}
