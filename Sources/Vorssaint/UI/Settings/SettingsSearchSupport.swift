// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure filtering for the Settings sidebar search field, so the matching
/// rules (case, accents, word prefixes) are covered by the unit harness.
enum SettingsSearchSupport {
    /// Case-, diacritic- and width-insensitive containment: "métr" finds
    /// "Metrics", "moni" finds "Monitor". A blank query matches everything.
    /// Keywords let a page match by what lives inside it ("lid" finds
    /// Energy, "quick panel" finds Quick tools), not just by its name.
    static func matches(query: String, title: String, keywords: [String] = []) -> Bool {
        let folded = fold(query)
        guard !folded.isEmpty else { return true }
        if fold(title).contains(folded) { return true }
        return keywords.contains { fold($0).contains(folded) }
    }

    /// Keeps only the sections that still have items for the query, so an
    /// empty section never renders just its header.
    static func filteredIndices(query: String,
                                sections: [[String]]) -> [[Int]] {
        sections.map { titles in
            titles.indices.filter { matches(query: query, title: titles[$0]) }
        }
    }

    private static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Content sizing for the resizable Settings window: tall enough by default
/// to show the whole sidebar without scrolling, and a size the user chose is
/// restored as is. Kept pure so the unit harness pins the rules.
enum SettingsWindowSupport {
    /// The layout's design size; the window can only grow from here.
    static let minContentWidth: Double = 772
    static let minContentHeight: Double = 528
    /// Tall default so every sidebar entry is visible on regular screens.
    static let preferredContentHeight: Double = 838

    /// A saved size wins when it is at least the minimum (0 means unset);
    /// otherwise the tall default, capped to the screen's available height.
    static func initialContentSize(savedWidth: Double, savedHeight: Double,
                                   availableHeight: Double) -> (width: Double, height: Double) {
        if savedWidth >= minContentWidth, savedHeight >= minContentHeight {
            return (savedWidth, savedHeight)
        }
        let height = min(preferredContentHeight, max(availableHeight, minContentHeight))
        return (minContentWidth, height)
    }
}
