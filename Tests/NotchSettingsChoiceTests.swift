// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The Dynamic Island page's option rows, drawn in their card at the narrowest
/// options column. A row wider than its column centers the page and cuts it on
/// both sides, and a choice that crowds its title breaks the title letter by
/// letter. SwiftUI can measure a row of segments narrower than Settings draws
/// it, so the checks read the AppKit controls the row draws.
enum NotchSettingsChoiceTests {
    static func run(_ suite: TestSuite) {
        // The Content tab's options column at the Settings window's minimum
        // width: less the sidebar at its widest, the page's margins, and the
        // list of sections with the space after it.
        let narrowest = CGFloat(SettingsWindowSupport.minContentWidth) - 240 - 22 * 2 - 196 - 16
        // Where a row's title text starts in its card, and in a row indented
        // under a switch as the AI agents card indents its menus.
        let column = 16 + settingsRowTextInset
        let indentedColumn = column + settingsRowTextInset
        for (language, _) in LocalizationTests.languages {
            let destinations = [FeatureStrings.notch(language).files, FeatureStrings.clipboard(language).title,
                                FeatureStrings.scratchpad(language).pageTitle]
            let choices = destinations.map { ($0, AnyView(Destination(language: language, title: $0))) }
                + [(FeatureStrings.notchAgents(language).limitsAs, AnyView(Limits(language: language)))]
            for (title, row) in choices {
                let overflow = problems(row, width: narrowest, textColumn: column)
                suite.expect(overflow.isEmpty, "\(language.rawValue): \(title) fits the narrowest Dynamic Island "
                             + "options column (\(Int(narrowest)) points): \(overflow.joined(separator: "; "))")
                suite.expect(drawsChoiceBesideTitle(row, width: 1000, segments: true),
                             "\(language.rawValue): \(title) keeps its segments beside the title where they fit")
            }
            let agents = FeatureStrings.notchAgents(language)
            let menus: [(String, AnyView, CGFloat)] = [
                (agents.readout, AnyView(Readout(language: language)), indentedColumn),
                (agents.finishAfter, AnyView(FinishAfter(language: language)), indentedColumn),
                (agents.limitAt, AnyView(LimitAt(language: language)), indentedColumn),
                (agents.budget, AnyView(Budget(language: language)), column),
            ]
            for (title, row, textColumn) in menus {
                let overflow = problems(row, width: narrowest, textColumn: textColumn)
                suite.expect(overflow.isEmpty, "\(language.rawValue): \(title) fits the narrowest Dynamic Island "
                             + "options column (\(Int(narrowest)) points): \(overflow.joined(separator: "; "))")
                suite.expect(drawsChoiceBesideTitle(row, width: 1000, segments: false),
                             "\(language.rawValue): \(title) keeps its menu beside the title where it fits")
            }
        }
    }

    /// How the row, in its card, fails this width: drawn past the card's
    /// content, squeezed, or crowding its title.
    private static func problems(_ row: AnyView, width: CGFloat, textColumn: CGFloat) -> [String] {
        var found = Set<String>()
        let measured = NSHostingController(rootView: SettingsCard { row })
            .sizeThatFits(in: CGSize(width: width, height: 1000)).width
        if measured > width { found.insert("the card measures \(Int(measured)) points") }
        let host = host(row, width: width)
        let fitsOneLine = host.fittingSize.width <= width
        for control in controls(in: host) {
            let frame = alignmentFrame(of: control, in: host)
            if frame.minX < 16 - 0.5 || frame.maxX > width - 16 + 0.5 {
                found.insert("a \(type(of: control)) drawn at \(Int(frame.minX))...\(Int(frame.maxX)), past the card's content")
            }
            if let segments = control as? NSSegmentedControl, control.frame.width < segments.fittingSize.width - 0.5 {
                found.insert("segments squeezed to \(Int(control.frame.width)) of \(Int(segments.fittingSize.width)) points")
            }
            // A choice drawn beside the title, rather than under it where the
            // title's text or its icon starts, squeezes the title unless the
            // row fits on one line.
            if abs(frame.minX - textColumn) > 0.5, abs(frame.minX - (textColumn - settingsRowTextInset)) > 0.5,
               !fitsOneLine {
                found.insert("a \(type(of: control)) at \(Int(frame.minX)) crowds the title")
            }
        }
        return found.sorted()
    }

    /// Whether the row draws its choice at the card's trailing edge, beside
    /// the title, when laid out at this width.
    private static func drawsChoiceBesideTitle(_ row: AnyView, width: CGFloat, segments: Bool) -> Bool {
        let host = host(row, width: width)
        return controls(in: host).contains { control in
            (control is NSSegmentedControl) == segments
                && abs(alignmentFrame(of: control, in: host).maxX - (width - 16)) <= 0.5
        }
    }

    private static func host(_ row: AnyView, width: CGFloat) -> NSHostingView<SettingsCard<AnyView>> {
        let host = NSHostingView(rootView: SettingsCard { row })
        host.frame = NSRect(x: 0, y: 0, width: width, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// The controls a row draws: segmented controls and pop-up buttons, or
    /// the focus ring macOS 26 and later leaves at a menu drawn by SwiftUI.
    /// Older versions also draw the card's background, the icon tile and each
    /// segment as views of their own; none of them is a choice.
    private static func controls(in view: NSView) -> [NSView] {
        view.subviews.flatMap { subview -> [NSView] in
            if subview is NSSegmentedControl || subview is NSPopUpButton
                || String(describing: type(of: subview)).contains("FocusRing") {
                return [subview]
            }
            return controls(in: subview)
        }
    }

    /// A control's frame in the host without the bezel some versions draw
    /// past the rect SwiftUI lines up.
    private static func alignmentFrame(of control: NSView, in host: NSView) -> CGRect {
        guard let superview = control.superview else { return .zero }
        return superview.convert(control.alignmentRect(forFrame: control.frame), to: host)
    }
}
