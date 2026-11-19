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
        var keepsSurfaceOnClick = false, showsCapturePreview = false
        var windowHost: Host? = Host()
        var collapses = 0, dismissals = 0
        lazy var captureDismiss: (() -> Void)? = { [unowned self] in self.dismissals += 1 }
        func collapse() { collapses += 1 }
    }
    final class Model { var sharing = false }
    class PreviewState {
        let model = Model()
        var closes = 0
        func close() { closes += 1 }
    }

    static func run(_ suite: TestSuite) {
        func clicked(_ change: (Service) -> Void = { _ in }) -> Service {
            let service = Service()
            change(service)
            service.clickedElsewhere()
            return service
        }
        let plain = clicked()
        suite.expect(plain.collapses == 1 && plain.dismissals == 0, "a click elsewhere collapses the island")
        let preview = clicked { $0.showsCapturePreview = true }
        suite.expect(preview.dismissals == 1 && preview.collapses == 0,
                     "a click elsewhere hands a screenshot preview to its controller instead of collapsing")
        for keep: (Service) -> Void in [
            { $0.keepsSurfaceOnClick = true },
            { $0.keepsSurfaceOnClick = true; $0.showsCapturePreview = true },
            { $0.showsCapturePreview = true; $0.windowHost?.underPointer = true },
            { _ in statusItem?.overStatusItem = true },
            { $0.showsCapturePreview = true; AssistiveKeyboard.active = true },
        ] {
            let service = clicked(keep)
            statusItem?.overStatusItem = false
            AssistiveKeyboard.active = false
            suite.expect(service.collapses == 0 && service.dismissals == 0,
                         "pinning, menus, sheets, the island's own area, the status item and the assistive keyboard keep the island")
        }

        let mirror = Mirror()
        mirror.host.underPointer = true
        let copiedIsland = clicked { $0.showsCapturePreview = true; $0.mirrors[1] = mirror }
        suite.expect(copiedIsland.dismissals == 0 && copiedIsland.collapses == 0,
                     "clicking a visible island copy preserves the preview while it moves between displays")
        mirror.model.shown = false
        let hiddenCopy = clicked { $0.showsCapturePreview = true; $0.mirrors[1] = mirror }
        suite.expect(hiddenCopy.dismissals == 1,
                     "a hidden island copy does not block an outside click at its old position")
        mirror.model.shown = true
        mirror.host.underPointer = false
        let outsideCopy = clicked { $0.showsCapturePreview = true; $0.mirrors[1] = mirror }
        suite.expect(outsideCopy.dismissals == 1, "a click outside every visible island dismisses the preview")

        let controller = Preview()
        controller.model.sharing = true
        controller.dismissForClickElsewhere()
        suite.expect(controller.closes == 0, "a click elsewhere keeps a preview whose share link is still being made")
        controller.model.sharing = false
        controller.dismissForClickElsewhere()
        suite.expect(controller.closes == 1, "a click elsewhere closes an idle screenshot preview")
    }
}
