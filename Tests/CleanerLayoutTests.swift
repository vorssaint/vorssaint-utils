// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The production results layout inside a panel's native scroll host, with
/// sample rows. Compact results must not capture scrolling in another list.
enum CleanerLayoutTests {
    enum DisplayGroup: CaseIterable, Identifiable {
        case safe, optional
        var id: Self { self }
        var isSafe: Bool { self == .safe }
    }
    struct Strings {
        let cleanerNothingFound = "Nothing found"
        let cleanerSafeSection = "Safe to clean"
        let cleanerOptionalSection = "Optional, review first"
    }
    struct Localization { let s = Strings() }
    struct Cleaner { let items = Array(0..<20) }
    struct Results: View {
        typealias DisplayGroup = CleanerLayoutTests.DisplayGroup
        let compact = true
        let cleaner = Cleaner()
        let l10n = Localization()
        let expanded: Bool
        var body: some View { resultsState }
        var resultsHeader: some View { Text("Cleaner").padding(12) }
        var resultsFooter: some View { Button("Clean 1.92 GB") {}.padding(12) }
        func items(for group: DisplayGroup) -> [Int] { cleaner.items }
        func groupRow(_ group: DisplayGroup) -> some View {
            DisclosureGroup(isExpanded: .constant(expanded)) {
                ForEach(cleaner.items, id: \.self) { Text("Sample file \($0)").padding(4) }
            } label: { Text(group.isSafe ? "Caches" : "Other caches") }
        }
    }

    static func run(_ suite: TestSuite) {
        for width: CGFloat in [308, 440] {
            for expanded in [false, true] {
                let host = NSHostingView(rootView: Results(expanded: expanded).frame(width: width))
                let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
                host.translatesAutoresizingMaskIntoConstraints = false
                scroll.documentView = host
                let clip = scroll.contentView
                NSLayoutConstraint.activate([
                    host.topAnchor.constraint(equalTo: clip.topAnchor),
                    host.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                    host.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                    host.widthAnchor.constraint(equalTo: clip.widthAnchor),
                ])
                scroll.layoutSubtreeIfNeeded()
                suite.expect(!containsScrollView(host),
                             "compact Cleaner uses its host's scrolling at \(width)pt, expanded: \(expanded)")
                suite.expect(host.fittingSize.height > 0 && host.fittingSize.height.isFinite,
                             "compact results report a finite content height")
                let bottom = CGRect(x: 0, y: host.bounds.maxY - 40, width: width, height: 40)
                host.scrollToVisible(bottom)
                suite.expect(clip.documentVisibleRect.contains(bottom),
                             "the Clean footer scrolls into view, including after expanding files")
            }
        }
    }

    private static func containsScrollView(_ view: NSView) -> Bool {
        view.subviews.contains { $0 is NSScrollView || containsScrollView($0) }
    }
}
