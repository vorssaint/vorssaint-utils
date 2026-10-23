// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The pure decisions of the selection bar: which mouse gestures select text,
/// which selection is current, which actions to offer and where the bar goes.
enum SelectionBarSupport {
    /// A press that moves less than this is a click, not a drag.
    static let dragThreshold: CGFloat = 4
    /// A selection farther than this from the release point is an old one,
    /// left over in a field the click did not change.
    static let staleTolerance: CGFloat = 60
    /// A selection longer than this is a document, not a phrase.
    static let maximumLength = 20_000
    /// A selection taller than this spans many lines. The bar then follows the
    /// pointer, not the top or bottom of the whole block.
    static let tallSelectionHeight: CGFloat = 48

    /// True for the gestures that open the bar: a drag, or a double or triple
    /// click when `includesClicks` is true. A single click only moves the caret.
    static func isSelectionGesture(clickCount: Int, down: CGPoint?, up: CGPoint,
                                   includesClicks: Bool = true) -> Bool {
        if clickCount >= 2, includesClicks { return true }
        guard let down else { return false }
        return hypot(up.x - down.x, up.y - down.y) > dragThreshold
    }

    /// Some apps give an empty or absurd rectangle for the selection. The bar
    /// ignores those.
    static func isUsable(_ rect: CGRect?) -> Bool {
        guard let rect, rect.width > 0, rect.height > 0 else { return false }
        return rect.width < 20_000 && rect.height < 20_000
    }

    /// True when the press or the release point is on or near the selection.
    /// A drag past the end of a line releases far from the text, but it
    /// starts on the text. When the app gives no geometry, the selection is
    /// accepted.
    static func isCurrent(release: CGPoint, press: CGPoint? = nil, selection: CGRect?) -> Bool {
        guard let selection, isUsable(selection) else { return true }
        let near = selection.insetBy(dx: -staleTolerance, dy: -staleTolerance)
        return near.contains(release) || press.map(near.contains) == true
    }

    /// The command bar rows the selection bar does not show. The bar has its
    /// own copy, which keeps formatting, and search opens a different window.
    static let excludedEntryIDs: Set<String> = ["selection.copy", "selection.search"]
    /// The rows that type over the selection. They only make sense where the
    /// text can be edited: on a web page, typed letters can trigger shortcuts.
    static let typingEntryIDs: Set<String> = ["selection.upper", "selection.lower", "selection.titleCase"]

    /// Every tool the bar can show, in bar order. Each one still appears only
    /// when it applies to the selection.
    static let actionIDs = ["copy", "selection.cleanLink", "selection.upper", "selection.lower",
                            "selection.titleCase", "selection.shelf", "selection.count"]

    /// True when the bar has tools for the trimmed selection `text`. A
    /// selection the size of a document gets no bar.
    static func shows(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maximumLength
    }

    /// The tools the person keeps on the bar. The ENABLED set is stored, so a
    /// tool added in a later version starts off until it is chosen. Unknown
    /// ids from an older or newer version are dropped.
    static func enabledActionIDs(_ stored: [String]?) -> Set<String> {
        Set(stored ?? actionIDs).intersection(actionIDs)
    }

    static func offers(_ entryID: String, isEditable: Bool) -> Bool {
        if excludedEntryIDs.contains(entryID) { return false }
        if typingEntryIDs.contains(entryID) { return isEditable }
        return true
    }

    /// Where the bar goes: above the selection, else below it, else at the
    /// pointer. It is centred on the pointer and kept inside `visible`.
    static func frame(size: CGSize,
                      selection: CGRect?,
                      pointer: CGPoint,
                      visible: CGRect,
                      gap: CGFloat = 8,
                      inset: CGFloat = 8) -> CGRect {
        var anchor = CGRect(x: pointer.x, y: pointer.y - 10, width: 0, height: 20)
        if let selection, isUsable(selection), selection.height <= tallSelectionHeight {
            anchor = selection
        }
        let minX = visible.minX + inset
        let maxX = max(minX, visible.maxX - inset - size.width)
        let x = min(max(pointer.x - size.width / 2, minX), maxX)

        let minY = visible.minY + inset
        let maxY = max(minY, visible.maxY - inset - size.height)
        let above = anchor.maxY + gap
        let below = anchor.minY - gap - size.height
        let y: CGFloat
        if above <= maxY {
            y = above
        } else if below >= minY {
            y = below
        } else {
            y = min(max(pointer.y + gap, minY), maxY)
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
