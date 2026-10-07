// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A question asked from inside the island. A SwiftUI alert hangs from the
/// island as a sheet, which moves and reskins the borderless surface, so the
/// question opens on its own above the island, which gets the keyboard back
/// afterwards.
enum NotchIslandAlert {
    static func run(_ alert: NSAlert, service: NotchService = .shared) -> NSApplication.ModalResponse {
        let island = service.presentationWindow
        var observers: [NSObjectProtocol] = []
        if let island {
            // The modal session puts the alert at the modal panel level, below
            // the island, and puts it back there when it activates the app or
            // makes the alert key. Raise it once running and after each of those.
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let raise: (Notification) -> Void = { _ in alert.window.level = level }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { alert.window.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        // A closed island declines key status, so this only returns to an open one.
        if let island, island.isVisible { island.makeKey() }
        return response
    }

    /// One field above the buttons, the caret already in it. Nil unless the
    /// first button was the answer, so a cancelled question changes nothing.
    static func askForName(title: String, message: String?, value: String, prompt: String,
                           save: String, cancel: String, service: NotchService = .shared) -> String? {
        let field = NSTextField(string: value)
        field.placeholderString = prompt
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        let alert = NSAlert()
        alert.messageText = title
        if let message { alert.informativeText = message }
        alert.accessoryView = field
        alert.addButton(withTitle: save)
        alert.addButton(withTitle: cancel)
        alert.window.initialFirstResponder = field
        guard run(alert, service: service) == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
