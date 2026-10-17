// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The collapser, the organizer's one status item. It is the control (click to show or hide)
/// and the boundary at once: whatever sits left of it gets hidden. It must be
/// in the bar before the first assertion, because an item registered while
/// icons are hidden parks off screen until they are shown again.
final class MenuBarOrganizerCollapser: NSObject {
    /// Set as Accessibility title and identifier of the button, so the
    /// inventory can tell this item from Vorssaint's other ones.
    static let accessibilityName = "VorssaintMenuBarOrganizer"

    /// The collapser as the inventory reports it, nil for a process without a
    /// bundle id (a bare binary cannot own an addressable status item).
    static var identity: MenuBarItemIdentity? {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return nil }
        return MenuBarItemIdentity(bundleID: bundleID, title: accessibilityName)
    }

    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var statusItem: NSStatusItem?

    func install(collapsed: Bool) {
        guard statusItem == nil else {
            setCollapsed(collapsed, shelfOpen: false)
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Remembered by macOS, so the boundary stays where the user put it.
        item.autosaveName = Self.accessibilityName
        item.behavior = []
        statusItem = item
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityIdentifier(Self.accessibilityName)
            button.setAccessibilityTitle(Self.accessibilityName)
            // The hidden icons sit left of the collapser on every Mac, so the
            // chevron must not mirror under a right-to-left system language.
            button.userInterfaceLayoutDirection = .leftToRight
        }
        setCollapsed(collapsed, shelfOpen: false)
    }

    func remove() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    /// Draws the icon chosen in Settings for the state and the reveal. The
    /// name it is found by stays the same whatever it looks like.
    func setCollapsed(_ collapsed: Bool, shelfOpen: Bool) {
        let defaults = UserDefaults.standard
        let icon = MenuBarOrganizerIcon.stored(defaults.string(forKey: DefaultsKey.menuBarOrganizerIcon))
        let reveal = MenuBarOrganizerReveal.stored(defaults.string(forKey: DefaultsKey.menuBarOrganizerReveal))
        let symbol = icon.symbol(collapsed: collapsed, reveal: reveal, shelfOpen: shelfOpen)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    /// The window of the collapser's button, in screen coordinates, to hang
    /// the shelf from. nil before the item is installed, and while macOS
    /// reports a frame outside any menu bar (a bar that hides itself parks
    /// the window out of sight).
    var anchorFrame: NSRect? {
        guard let frame = buttonWindow?.frame,
              StatusItemAnchorSupport.isTrustworthyStatusFrame(frame) else { return nil }
        return frame
    }

    /// The window the collapser's clicks arrive in, so the shelf can let them
    /// through to the toggle instead of treating them as a click outside.
    var buttonWindow: NSWindow? { statusItem?.button?.window }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onOpenSettings?()
        } else if NSApp.currentEvent?.modifierFlags.contains(.command) != true {
            // A ⌘-click is the start of a drag, the user's or the organizer's
            // own, and must not toggle.
            onToggle?()
        }
    }
}
