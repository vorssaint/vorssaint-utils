// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Dynamic Island page's option rows, drawn in their card at the narrowest
/// options column. A row wider than its column centers the page and cuts it on
/// both sides, and a choice that crowds its title breaks the title letter by
/// letter. SwiftUI can measure a row of segments narrower than Settings draws
/// it, so the checks read the AppKit views the row draws.
enum NotchSettingsChoiceTests {
    static func run(_ suite: TestSuite) {
        // The Content tab's options column at the Settings window's minimum
        // width: less the sidebar at its widest, the page's margins, and the
        // list of sections with the space after it.
        let narrowest = CGFloat(SettingsWindowSupport.minContentWidth) - 240 - 22 * 2 - 196 - 16
        for (language, _) in LocalizationTests.languages {
            let destinations = [FeatureStrings.notch(language).files, FeatureStrings.clipboard(language).title,
                                FeatureStrings.scratchpad(language).pageTitle]
            let rows = destinations.map { ($0, AnyView(Destination(language: language, title: $0))) }
                + [(FeatureStrings.notchAgents(language).limitsAs, AnyView(Limits(language: language)))]
            for (title, row) in rows {
                let overflow = problems(row, width: narrowest)
                suite.expect(overflow.isEmpty, "\(language.rawValue): \(title) fits the narrowest Dynamic Island "
                             + "options column (\(Int(narrowest)) points): \(overflow.joined(separator: "; "))")
                suite.expect(drawsSegmentsBesideTitle(row, width: 1000),
                             "\(language.rawValue): \(title) keeps its segments beside the title where they fit")
            }
        }
    }

    /// How the row, in its card, fails this width: drawn past the card's
    /// content, squeezed, or crowding its title.
    private static func problems(_ row: AnyView, width: CGFloat) -> [String] {
        var found = Set<String>()
        let measured = NSHostingController(rootView: SettingsCard { row })
            .sizeThatFits(in: CGSize(width: width, height: 1000)).width
        if measured > width { found.insert("the card measures \(Int(measured)) points") }
        let host = host(row, width: width)
        let fitsOneLine = host.fittingSize.width <= width
        for view in descendants(host) {
            let frame = view.convert(view.bounds, to: host)
            if frame.minX < 16 || frame.maxX > width - 16 {
                found.insert("a choice drawn at \(Int(frame.minX))...\(Int(frame.maxX)), past the card's content")
            }
            if let segments = view as? NSSegmentedControl, frame.width < segments.fittingSize.width {
                found.insert("segments squeezed to \(Int(frame.width)) of \(Int(segments.fittingSize.width)) points")
            }
            // A choice drawn beside the title, rather than under it where the
            // title's text starts, squeezes the title unless the row fits on
            // one line.
            if abs(frame.minX - textColumn) > 0.5, !fitsOneLine {
                found.insert("a choice at \(Int(frame.minX)) crowds the title")
            }
        }
        return found.sorted()
    }

    private static func drawsSegmentsBesideTitle(_ row: AnyView, width: CGFloat) -> Bool {
        let host = host(row, width: width)
        return descendants(host).contains { view in
            view is NSSegmentedControl && abs(view.convert(view.bounds, to: host).maxX - (width - 16)) <= 0.5
        }
    }

    /// Where the row's title starts: past the card's padding and the icon.
    private static let textColumn = 16 + settingsRowTextInset

    private static func host(_ row: AnyView, width: CGFloat) -> NSHostingView<SettingsCard<AnyView>> {
        let host = NSHostingView(rootView: SettingsCard { row })
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
