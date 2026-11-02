// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Tells a mouse gesture that leaves text selected (a drag, a double click or a
/// triple click) from an ordinary click. Fed the left button's events in order,
/// it keeps no reference to the pointer or to any app: the service does the
/// reading, this only decides when a selection has just been made.
struct CopyOnSelectGesture {
    /// How far the pointer must travel with the button down to count as a drag.
    /// A click that wobbles a pixel or two selects nothing.
    static let dragDistance: CGFloat = 4

    private var pressLocation: CGPoint?
    private var dragged = false

    mutating func press(at location: CGPoint) {
        pressLocation = location
        dragged = false
    }

    mutating func drag(to location: CGPoint) {
        guard let start = pressLocation, !dragged else { return }
        dragged = abs(location.x - start.x) > Self.dragDistance
            || abs(location.y - start.y) > Self.dragDistance
    }

    /// True when releasing the button finished a gesture that selects text.
    /// A release with no press seen, such as one that began before the monitor
    /// started, is never a selection. The release's own location counts as the
    /// last step of a drag, in case no drag event was delivered.
    mutating func release(at location: CGPoint, clickCount: Int) -> Bool {
        drag(to: location)
        defer {
            pressLocation = nil
            dragged = false
        }
        guard pressLocation != nil else { return false }
        return dragged || clickCount >= 2
    }
}

enum CopyOnSelectSupport {
    /// Whether to send Command-C for a finished gesture: when reading found no
    /// text, and the text cursor showed at some point in it. A selection can
    /// start in a margin and end past a line, but it crosses text on the way,
    /// while a drag on a scroll bar, a tab, a divider or a file never shows it.
    static func shouldSendCopyShortcut(readText: String?, sawTextCursor: Bool) -> Bool {
        sawTextCursor && (readText?.isEmpty ?? true)
    }

    /// Whether text read after a gesture is a selection just made, rather than
    /// an older one still standing while the gesture did something else, such as
    /// dragging a scroll bar. Text already copied counts only when the text
    /// cursor showed. Not every app draws the standard one, so a different text
    /// is taken as new whatever the cursor showed.
    static func isNewSelection(_ text: String, lastCopied: String?, sawTextCursor: Bool) -> Bool {
        sawTextCursor || text != lastCopied
    }

    /// Whether the selection should replace what the pasteboard holds. Text that
    /// is only whitespace is left alone, since a double click on a gap selects
    /// the gap, and text the pasteboard already holds is not written again, so
    /// it does not bump the change count or add a history entry.
    static func shouldCopy(selected: String, pasteboardText: String?) -> Bool {
        guard selected.contains(where: { !$0.isWhitespace }) else { return false }
        return selected != pasteboardText
    }
}
