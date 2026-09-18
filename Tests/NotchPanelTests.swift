// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production panel class is compiled here. Creating it deferred neither
/// shows a window nor needs a running application; the sheet check orders a
/// fully transparent panel in off screen, since a sheet brings its parent in.
enum NotchPanelTests {
    static func run(expect: (Bool, String) -> Void) {
        let panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 40),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        expect(panel.accessibilitySubrole() == .unknown,
               "the island describes itself as an undescribed borderless overlay, so window managers skip it "
               + "instead of listing a ghost window of this app on the current space")
        expect(panel.accessibilityRole() == .window && panel.isAccessibilityElement(),
               "the island stays an accessible window for assistive technology")
        sheetContracts(expect: expect)
    }

    private static func sheetContracts(expect: (Bool, String) -> Void) {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let island = NotchPanel(contentRect: CGRect(x: -4000, y: -4000, width: 300, height: 120),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        island.isReleasedWhenClosed = false
        island.alphaValue = 0
        let dialog = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80),
                             styleMask: [.titled], backing: .buffered, defer: false)
        dialog.isReleasedWhenClosed = false
        dialog.alphaValue = 0
        defer { island.close(); dialog.close() }
        var response: NSApplication.ModalResponse?
        island.beginSheet(dialog) { response = $0 }
        var deadline = Date().addingTimeInterval(2)
        while island.attachedSheet == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        expect(island.attachedSheet === dialog, "a dialog attaches to the island as its sheet")
        island.orderOut(nil)
        deadline = Date().addingTimeInterval(2)
        while response == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        expect(response == .cancel && island.attachedSheet == nil && !dialog.isVisible,
               "hiding the island ends an attached sheet through its completion, so a dialog opened inside it "
               + "is never dropped silently by a lock, sleep or teardown, leaving its caller waiting")
        island.orderOut(nil)
        expect(!island.isVisible, "ordering out without a sheet stays an ordinary hide")
    }
}
