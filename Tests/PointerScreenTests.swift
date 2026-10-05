// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production pointer-screen lookup runs against stand-in screens, so the
/// edges between displays are checked without a second monitor attached.
enum PointerScreenContract {
    final class Screen {
        typealias NSScreen = Screen
        enum NSEvent { static var mouseLocation = NSPoint.zero }
        static var screens: [Screen] = []
        static var main: Screen?
        let name: String
        let frame: NSRect
        init(_ name: String, _ frame: NSRect) {
            self.name = name
            self.frame = frame
        }
    }

    static func run(_ suite: TestSuite) {
        // A display on the right and one stacked above the primary. AppKit
        // reports a screen's top row at frame.maxY and its bottom row just
        // above frame.minY. The key window, and so `main`, stays on the primary.
        let primary = Screen("primary", NSRect(x: 0, y: 0, width: 1440, height: 900))
        let right = Screen("right", NSRect(x: 1440, y: 0, width: 1920, height: 1080))
        let above = Screen("above", NSRect(x: 0, y: 900, width: 1440, height: 900))
        Screen.screens = [primary, right, above]
        Screen.main = primary
        let cases: [(NSPoint, String, String)] = [
            (NSPoint(x: 2000, y: 1080), "right", "the top row of a secondary display belongs to it, not to the main screen"),
            (NSPoint(x: 700, y: 900), "primary", "the top row of a display with another above it stays on the lower one"),
            (NSPoint(x: 700, y: 1800), "above", "the top row of the upper display belongs to it"),
            (NSPoint(x: 700, y: 901), "above", "the bottom row of the upper display stays on it"),
            (NSPoint(x: 700, y: 1), "primary", "the bottom row of a display stays on it"),
            (NSPoint(x: 1440, y: 500), "right", "the first column of a display on the right belongs to it"),
            (NSPoint(x: 2000, y: 500), "right", "a pointer inside a display belongs to it"),
            (NSPoint(x: 5000, y: 5000), "primary", "a pointer outside every display falls back to the main screen"),
        ]
        for (pointer, expected, behavior) in cases {
            Screen.NSEvent.mouseLocation = pointer
            let found = Screen.withMouse?.name
            suite.expect(found == expected, "\(behavior), found \(found ?? "nil")")
        }
        Screen.screens = []
        Screen.main = nil
        suite.expect(Screen.withMouse == nil, "with no display at all there is nothing to show onto")
        Screen.NSEvent.mouseLocation = .zero
    }
}
