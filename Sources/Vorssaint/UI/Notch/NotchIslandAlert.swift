// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Opens a question above the island without attaching a sheet that moves and
/// reskins its borderless surface. The island gets the keyboard back afterwards.
enum NotchIslandAlert {
    static func run(_ alert: NSAlert, above island: NSWindow?) -> NSApplication.ModalResponse {
        var observers: [NSObjectProtocol] = []
        if let island, island.isVisible {
            // AppKit resets the modal level when it activates the app or makes
            // the alert key. Raise it once running and after each reset.
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
        // A collapsed island declines key status, so only an open one takes it.
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}
