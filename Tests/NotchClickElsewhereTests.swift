// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production click-elsewhere routing with controlled state, never posted input.
enum NotchClickElsewhereTests {
    enum NSEvent { static var mouseLocation = CGPoint.zero }
    final class AppDelegate {
        var overStatusItem = false
        func isOverStatusItem(_ point: CGPoint) -> Bool { overStatusItem }
    }
    enum NSApp { static var delegate: Any? = AppDelegate() }
    static var statusItem: AppDelegate? { NSApp.delegate as? AppDelegate }
    enum AssistiveKeyboard {
        static var active = false
        static func ownsCocoaPoint(_ point: CGPoint) -> Bool { active }
    }
    final class Host {
        var underPointer = false
        func contains(_ point: CGPoint) -> Bool { underPointer }
    }
    final class Mirror {
        final class Model { var shown = true }
        let model = Model(), host = Host()
    }
    class State {
        var mirrors: [Int: Mirror] = [:]
        var keepsSurfaceOnClick = false
        var windowHost: Host? = Host()
        var collapses = 0
        func collapse() { collapses += 1 }
    }

    static func run(_ suite: TestSuite) {
        func clicked(_ change: (Service) -> Void = { _ in }) -> Service {
            let service = Service()
            change(service)
            service.clickedElsewhere()
            return service
        }
        let plain = clicked()
        suite.expect(plain.collapses == 1, "a click elsewhere collapses the island")
        for keep: (Service) -> Void in [
            { $0.keepsSurfaceOnClick = true },
            { $0.windowHost?.underPointer = true },
            { _ in statusItem?.overStatusItem = true },
            { _ in AssistiveKeyboard.active = true },
        ] {
            let service = clicked(keep)
            statusItem?.overStatusItem = false
            AssistiveKeyboard.active = false
            suite.expect(service.collapses == 0,
                         "pinning, menus, sheets, the island's own area, the status item and the assistive keyboard keep the island")
        }

        let mirror = Mirror()
        mirror.host.underPointer = true
        let copiedIsland = clicked { $0.mirrors[1] = mirror }
        suite.expect(copiedIsland.collapses == 0, "clicking a visible island copy keeps the island open")
        mirror.model.shown = false
        let hiddenCopy = clicked { $0.mirrors[1] = mirror }
        suite.expect(hiddenCopy.collapses == 1,
                     "a hidden island copy does not block an outside click at its old position")
        mirror.model.shown = true
        mirror.host.underPointer = false
        let outsideCopy = clicked { $0.mirrors[1] = mirror }
        suite.expect(outsideCopy.collapses == 1, "a click outside every visible island collapses it")
    }
}
