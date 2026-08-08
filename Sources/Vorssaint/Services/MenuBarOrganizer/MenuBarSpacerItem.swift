// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

@MainActor
final class MenuBarSpacerItem: NSObject {
    private(set) var statusItem: NSStatusItem
    private let autosaveName: String

    var windowID: CGWindowID? {
        statusItem.button?.window.map { CGWindowID($0.windowNumber) }
    }

    init(index: Int, width: CGFloat) {
        autosaveName = "Vorssaint.MenuBarOrganizer.Spacer.\(index)"
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
        if defaults.object(forKey: positionKey) == nil {
            defaults.set(10 + Double(index), forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: width)
        super.init()
        statusItem.autosaveName = autosaveName
        statusItem.behavior = []
        statusItem.isVisible = true
        statusItem.button?.toolTip = "Menu bar spacer"
    }

    deinit {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let cached = UserDefaults.standard.object(forKey: key)
        NSStatusBar.system.removeStatusItem(statusItem)
        if let cached { UserDefaults.standard.set(cached, forKey: key) }
    }

    func update(width: CGFloat) {
        statusItem.length = width
        statusItem.isVisible = true
    }

    func removePreservingPosition() {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        let cached = UserDefaults.standard.object(forKey: key)
        statusItem.isVisible = false
        if let cached { UserDefaults.standard.set(cached, forKey: key) }
    }
}
