// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Placing a status item by writing "NSStatusItem Preferred Position" before
// creating it follows Ice (https://github.com/jordanbaird/Ice, GPL-3.0).

import AppKit

/// The empty, disabled status item that keeps the menu bar's status items
/// out from under the island. It belongs to the island alone: the menu bar
/// item controller never lists it, and the island's menu measurements leave
/// it out.
final class NotchMenuBarGapItem {
    private var item: NSStatusItem?
    private(set) var gap: NotchMenuBarGap?

    var windowNumber: Int {
        guard let number = item?.button?.window?.windowNumber, number > 0 else { return -1 }
        return number
    }

    /// Where the gap is drawn, for measurements to leave out; nil before
    /// macOS has placed it.
    var frame: CGRect? {
        guard let frame = item?.button?.window?.frame, frame.width > 0, frame.minY > 0 else { return nil }
        return frame
    }

    /// macOS reads a status item's position only as it appears, so a gap
    /// that has to move is created again.
    func place(_ wanted: NotchMenuBarGap) {
        hide()
        let name = NotchMenuBarGap.autosaveName
        let defaults = UserDefaults.standard
        defaults.set(Double(wanted.position), forKey: StatusItemPlacementSupport.preferredPositionKey(for: name))
        // A gap remembered as removed from the bar would never appear.
        defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
        let item = NSStatusBar.system.statusItem(withLength: wanted.length)
        item.autosaveName = name
        item.behavior = []
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.isEnabled = false
            button.setAccessibilityElement(false)
        }
        self.item = item
        gap = wanted
    }

    func hide() {
        gap = nil
        guard let item else { return }
        self.item = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
