// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The tab row must never make the Dynamic Island page wider than its column:
/// a wider page is centered and cut on both sides, under the sidebar. SwiftUI
/// measures a row of text segments as able to shrink to the narrowest page,
/// but Settings lays the segments out at their full width, so the check is on
/// the style the row draws there.
enum NotchSettingsTabRowTests {
    static func run(_ suite: TestSuite) {
        // The narrowest page row: the Settings window's minimum width, less the
        // sidebar at its widest and the page's margins.
        let narrowestRow = CGFloat(SettingsWindowSupport.minContentWidth) - 240 - 22 * 2
        for (language, _) in LocalizationTests.languages {
            let row = NotchSettingsTabRow(tab: .constant(.layout), language: language, canOpen: true, open: {})
            let segmented = NSHostingView(rootView: row).fittingSize.width
            let narrow = NSHostingController(rootView: row)
                .sizeThatFits(in: CGSize(width: narrowestRow, height: 200)).width
            suite.expect(narrow > 0 && narrow <= narrowestRow
                            && (segmented <= narrowestRow || !drawsSegments(row, width: narrowestRow)),
                         "\(language.rawValue): the Dynamic Island tabs fit the narrowest Settings page "
                         + "(\(Int(segmented)) points as segments, \(Int(narrowestRow)) available)")
            suite.expect(drawsSegments(row, width: 2000),
                         "\(language.rawValue): the Dynamic Island tabs stay segmented where they fit")
        }
    }

    /// Whether the row draws its tabs as segments when laid out at this width.
    private static func drawsSegments(_ row: NotchSettingsTabRow, width: CGFloat) -> Bool {
        let host = NSHostingView(rootView: row)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 60)
        host.layoutSubtreeIfNeeded()
        func contains(_ view: NSView) -> Bool {
            view is NSSegmentedControl || view.subviews.contains(where: contains)
        }
        return contains(host)
    }
}
