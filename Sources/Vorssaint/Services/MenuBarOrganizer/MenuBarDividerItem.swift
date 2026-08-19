// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

@MainActor
final class MenuBarDividerItem: NSObject {
    enum Kind: String {
        case control
        case hidden
        case alwaysHidden

        var autosaveName: String { "Vorssaint.MenuBarOrganizer.\(rawValue)" }
    }

    let kind: Kind
    private(set) var statusItem: NSStatusItem
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    var windowID: CGWindowID? {
        statusItem.button?.window.map { CGWindowID($0.windowNumber) }
    }

    var frame: CGRect? { statusItem.button?.window?.frame }

    init(kind: Kind) {
        self.kind = kind
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(kind.autosaveName)"
        if defaults.object(forKey: positionKey) == nil {
            let position: Double = switch kind {
            case .control: 0
            case .hidden: 1
            case .alwaysHidden: 2
            }
            defaults.set(position, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: kind == .control ? NSStatusItem.squareLength : 1)
        super.init()
        statusItem.autosaveName = kind.autosaveName
        // Keep the dividers movable, but do not let an accidental Command-drag
        // off the bar terminate the whole app.
        statusItem.behavior = []
        statusItem.isVisible = true
        configureButton()
    }

    deinit {
        let key = "NSStatusItem Preferred Position \(kind.autosaveName)"
        let cached = UserDefaults.standard.object(forKey: key)
        NSStatusBar.system.removeStatusItem(statusItem)
        if let cached { UserDefaults.standard.set(cached, forKey: key) }
    }

    func setCollapsed(_ collapsed: Bool, markerVisible: Bool, collapsedLength: CGFloat) {
        guard kind != .control else { return }
        let length: CGFloat = collapsed ? collapsedLength : (markerVisible ? NSStatusItem.squareLength : 1)
        statusItem.length = length
        guard let button = statusItem.button else { return }
        button.image = markerVisible ? NSImage(systemSymbolName: kind == .hidden ? "chevron.left" : "lock.fill",
                                               accessibilityDescription: nil) : nil
        button.toolTip = kind == .hidden ? "Hidden menu bar section" : "Always-hidden menu bar section"
    }

    func expandForRemoval() {
        statusItem.isVisible = true
        guard kind != .control else { return }
        statusItem.length = 1
        statusItem.button?.image = nil
    }

    func removePreservingPosition() {
        let key = "NSStatusItem Preferred Position \(kind.autosaveName)"
        let cached = UserDefaults.standard.object(forKey: key)
        statusItem.isVisible = false
        if let cached { UserDefaults.standard.set(cached, forKey: key) }
    }

    func restore() {
        statusItem.isVisible = true
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.identifier = NSUserInterfaceItemIdentifier(kind.autosaveName)
        button.setAccessibilityIdentifier(kind.autosaveName)
        if kind == .control {
            // The managed items sit to this control's left, so the icon also
            // communicates the direction in which a click reveals them.
            button.image = NSImage(systemSymbolName: "chevron.left",
                                   accessibilityDescription: "Menu bar organizer")
            button.toolTip = "Menu bar organizer"
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }
}
