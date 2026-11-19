// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Placing a status item by writing "NSStatusItem Preferred Position" before
// creating it follows Ice (https://github.com/jordanbaird/Ice, GPL-3.0).

import AppKit

/// The empty, disabled status item that keeps the menu bar's status items
/// out from under the island. It only carries out what
/// `NotchMenuBarGapPlanner` decides, so every change it makes is counted.
/// It belongs to the island alone: the menu bar item controller never lists
/// it, and the island's menu measurements leave it out.
final class NotchMenuBarGapItem {
    private var item: NSStatusItem?

    var windowNumber: Int {
        guard let number = item?.button?.window?.windowNumber, number > 0 else { return -1 }
        return number
    }

    /// macOS reads a status item's position only as it appears, so the gap
    /// is created again to move. Removing and adding it in the same turn
    /// lays the menu bar out once.
    func place(_ gap: NotchMenuBarGap) {
        hide()
        let name = NotchMenuBarGap.autosaveName
        let defaults = UserDefaults.standard
        defaults.set(Double(gap.position), forKey: StatusItemPlacementSupport.preferredPositionKey(for: name))
        // A gap remembered as removed from the bar would never appear.
        defaults.removeObject(forKey: "NSStatusItem Visible \(name)")
        let item = NSStatusBar.system.statusItem(withLength: gap.length)
        item.autosaveName = name
        item.behavior = []
        if let button = item.button {
            button.title = ""
            button.image = nil
            button.isEnabled = false
            button.setAccessibilityElement(false)
        }
        self.item = item
    }

    func setLength(_ length: CGFloat) {
        item?.length = length
    }

    func hide() {
        guard let item else { return }
        self.item = nil
        NSStatusBar.system.removeStatusItem(item)
    }
}
