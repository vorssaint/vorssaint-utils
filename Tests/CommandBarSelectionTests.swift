// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Builds production selection rows and records their actions instead of
/// posting keys, reading accessibility or changing the clipboard.
enum CommandBarSelectionTests {
    struct CommandBarEntry {
        enum Icon { case symbol(String) }
        enum Trouble { case needsPermission }
        let id: String
        let title: String
        let subtitle: String
        var keywords = ""
        let icon: Icon
        var trouble: Trouble? = nil
        var answerValue: String? = nil
        var countsUsage = true
        var keepsBarOpen = false
        let run: (Int?) -> Void
    }
    struct CommandBarFeatureStrings {
        let kindSelection = "selection"
        let selectionCopy = "copy"
        let selectionSearch = "search"
        let selectionUpper = "upper"
        let selectionLower = "lower"
        let selectionTitleCase = "title"
        let selectionShelf = "shelf"
        let selectionCount = "count"
        let selectionCountFormat = "%d words, %d characters"
        let actionCleanURL = "clean"
    }
    enum AppFeature {
        case urlCleaner, shelf
        var isAvailable: Bool { false }
    }
    struct URLCleanerService {
        struct Cleaned { let url: String; let removed: [String] }
        static let shared = Self()
        func clean(_ text: String) -> Cleaned? { nil }
        func copy(_ text: String) {}
    }
    struct L10n {
        static let shared = Self()
        let s = Strings()
        struct Strings {
            let urlCleanerName = "cleaner"
            let urlCleanerCleaned = "cleaned"
            let urlCleanerRemovedFormat = "%@"
            let shelfName = "shelf"
        }
    }
    struct Permissions {
        static let shared = Self()
        let accessibility = true
    }
    struct UserDefaults {
        static let standard = Self()
        func bool(forKey key: String) -> Bool { false }
    }
    enum DefaultsKey { static let shelfEnabled = "fixture" }
    enum QuickToolHUD { static func show(icon: String, message: String) {} }
    class Fixture {
        static var typed: [String] = []
        static var copied: [String] = []
        static func typeAtCursor(_ text: String) { typed.append(text) }
        static func copyAnswer(_ text: String) { copied.append(text) }
        static func keepOnShelf(_ text: String) {}
    }

    static func run(_ suite: TestSuite) {
        let strings = CommandBarFeatureStrings()
        defer { Catalog.typed = []; Catalog.copied = [] }
        var searched: [String] = []
        let selected = " \tHello world\n"
        let rows = Catalog.selectionEntries("Hello world", exactly: selected, bar: strings,
                                             useInSearch: { searched.append($0) })
        rows.first { $0.id == "selection.upper" }?.run(nil)
        suite.expect(Catalog.typed == [selected.localizedUppercase],
                     "case changes preserve surrounding spaces and the selected line break")
        rows.first { $0.id == "selection.copy" }?.run(nil)
        rows.first { $0.id == "selection.search" }?.run(nil)
        suite.expect(Catalog.copied == ["Hello world"] && searched == ["Hello world"],
                     "copy and search continue to use the trimmed selection")

        let caseIDs: Set<String> = ["selection.upper", "selection.lower", "selection.titleCase"]
        for count in [4_999, 5_000, 100_000] {
            let exact = String(repeating: " ", count: count) + "a"
            let bounded = Catalog.selectionEntries("a", exactly: exact, bar: strings, useInSearch: { _ in })
            suite.expect(bounded.contains { caseIDs.contains($0.id) } == (exact.count <= 5_000),
                         "the replacement limit includes all \(count) surrounding spaces")
            if exact.count <= 5_000 {
                bounded.first { $0.id == "selection.upper" }?.run(nil)
                suite.expect(Catalog.typed.last == exact.localizedUppercase,
                             "a selection at the insertion limit retains every character")
            }
            suite.expect(bounded.contains { $0.id == "selection.copy" }
                         && bounded.contains { $0.id == "selection.search" },
                         "long exact selections retain actions that do not type over them")
        }
        let markers = Catalog.selectionEntries("hello", exactly: "hello", typesOver: false,
                                                bar: strings, useInSearch: { _ in })
        suite.expect(!markers.contains { caseIDs.contains($0.id) }
                     && markers.contains { $0.id == "selection.copy" },
                     "text marker selections offer read actions without unsafe case replacement")
        let fallback = Catalog.selectionEntries("hello", bar: strings, useInSearch: { _ in })
        fallback.first { $0.id == "selection.upper" }?.run(nil)
        suite.expect(Catalog.typed.last == "HELLO",
                     "callers without an exact selection keep the original case behavior")
        suite.expect(Catalog.selectionEntries("", bar: strings, useInSearch: { _ in }).isEmpty,
                     "empty selections do not produce rows")
    }
}
