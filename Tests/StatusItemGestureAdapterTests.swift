// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Production adapter methods are compiled verbatim by generate_sources.py.
/// Only OS inputs, the controller and the permission/tap boundary are doubled;
/// event routing, permission subscriptions and the release timer are real.
enum StatusItemGestureAdapterTests {
    final class Permissions {
        static let shared = Permissions()
        @Published var accessibility = false
        var requests = 0
        func requestAccessibility() { requests += 1 }
    }

    static func AXIsProcessTrusted() -> Bool { Permissions.shared.accessibility }

    struct NSEvent {
        static var pressedMouseButtons = 0
        static var mouseLocation = CGPoint(x: 120, y: 300)
        var type: AppKit.NSEvent.EventType = .leftMouseUp
        var timestamp: TimeInterval
        var keyCode: UInt16 = 0
        var modifierFlags: AppKit.NSEvent.ModifierFlags = []
    }

    struct NSScreen {
        static let screens = [NSScreen()]
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    }

    struct ProcessInfo {
        static var processInfo = ProcessInfo()
        var systemUptime: TimeInterval = 0
    }

    final class Owner {
        var onDelayedLeftClick: ((NSPoint) -> Void)?
        var onQuickAction: ((StatusItemQuickAction) -> Void)?
    }

    class Fixture {
        static let releaseWatchInterval: TimeInterval = 0.04
        var owner: Owner? = Owner()
        var gesture = StatusItemGesture()
        var settings = StatusItemGesture.Settings(middle: .keepAwake, hold: .screenshot)
        var timer: Timer?
        var generation = 0
        var observedLeftDown: TimeInterval?
        var observedLeftUp: TimeInterval?
        var middleTap: Bool?
        var requestedAccessibilityForMiddle = false
        var accessibilityObserver: AnyCancellable?
        var frame: CGRect? = CGRect(x: 105, y: 288, width: 30, height: 24)
        var installations = 0
        var removals = 0
        var results: [StatusItemGesture.Result] = []

        init() {
            owner?.onDelayedLeftClick = { [weak self] in self?.results.append(.single($0)) }
            owner?.onQuickAction = { [weak self] in self?.results.append(.quick($0)) }
        }

        deinit { timer?.invalidate() }
        func mainButtonFrame() -> NSRect? { frame }
        func log(_ message: String) {}
        func installMiddleTap() { middleTap = true; installations += 1 }
        func tearDownMiddleTap() {
            if middleTap != nil { removals += 1 }
            middleTap = nil
        }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSEvent.pressedMouseButtons = 0
            NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
            Permissions.shared.accessibility = false
            Permissions.shared.requests = 0
        }
        testMissingDown(suite)
        testMiddleRelease(suite)
        testPermissionChanges(suite)
    }

    private static func testMissingDown(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for duration in [0.1, 1.0] {
            let host = Host()
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            suite.expect(host.buttonClick(NSEvent(timestamp: 10)),
                         "the adapter claims a valid press even when the monitor missed down")
            suite.expect(host.gesture.watchesForRelease && host.timer?.isValid == true,
                         "the missing-down fallback starts the real release watcher")
            suite.expect(host.results.isEmpty, "a held physical button emits nothing yet")
            ProcessInfo.processInfo.systemUptime = 10 + duration
            host.timer?.fire()
            suite.expect(host.results.isEmpty, "even a long press waits for release")
            NSEvent.pressedMouseButtons = 0
            host.timer?.fire()
            let expected: StatusItemGesture.Result = duration < 0.5 ? .single(point) : .quick(.screenshot)
            suite.expect(host.results == [expected],
                         "the adapter delivers exactly one short-click or hold after a missed down")
            suite.expect(host.timer == nil && !host.gesture.isActive,
                         "the release watcher stops when the fallback press ends")
            host.observeRelease()
            suite.expect(host.results == [expected], "a repeated release cannot emit twice")
        }

        let released = Host()
        suite.expect(released.buttonClick(NSEvent(timestamp: 20))
                     && released.results == [.single(point)],
                     "a missing-down action delivered after release still opens the panel")
        for frame in [nil, CGRect.zero, CGRect(x: 500, y: 500, width: 30, height: 24)] {
            let host = Host()
            host.frame = frame
            NSEvent.pressedMouseButtons = 1
            suite.expect(!host.buttonClick(NSEvent(timestamp: 30))
                         && host.timer == nil && !host.gesture.isActive,
                         "unplaceable presses remain unclaimed for the normal click path")
        }

        let observed = Host()
        NSEvent.pressedMouseButtons = 1
        observed.observe(NSEvent(type: .leftMouseDown, timestamp: 40))
        _ = observed.buttonClick(NSEvent(timestamp: 40.4))
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 40.6
        observed.timer?.fire()
        suite.expect(observed.results == [.quick(.screenshot)],
                     "the button fallback does not reset a press the monitor already started")
    }

    private static func middleEvent(_ type: CGEventType, x positionX: CGFloat, button: Int64 = 2) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                            mouseCursorPosition: CGPoint(x: positionX, y: 500), mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return event
    }

    private static func testMiddleRelease(_ suite: TestSuite) {
        let host = Host()
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        suite.expect(host.gesture.isActive, "an inside middle down reaches the adapter")
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 150))
        suite.expect(!host.gesture.isActive && host.results.isEmpty,
                     "an outside middle release cancels its pending press")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 150))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(host.results.isEmpty && !host.gesture.isActive,
                     "outside down then inside up cannot complete an old middle gesture")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(host.results == [.quick(.keepAwake)], "a fresh middle click still fires exactly once")

        host.results = []
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        host.frame = nil
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(!host.gesture.isActive && host.results.isEmpty,
                     "losing the icon frame before release also cancels the press")
    }

    private static func testPermissionChanges(_ suite: TestSuite) {
        Permissions.shared.accessibility = false
        Permissions.shared.requests = 0
        let host = Host()
        host.watchAccessibility()
        let assigned = host.settings
        host.settings = .init(hold: .screenshot)
        host.sync(settings: assigned)
        suite.expect(host.middleTap == nil && Permissions.shared.requests == 1,
                     "assigning middle-click without permission asks once and installs no tap")
        Permissions.shared.accessibility = true
        suite.expect(host.middleTap != nil && host.installations == 1,
                     "granting permission installs the tap without reassigning the action")
        Permissions.shared.accessibility = true
        host.sync(settings: host.settings)
        suite.expect(host.installations == 1, "unchanged settings or grants never duplicate a tap")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        Permissions.shared.accessibility = false
        suite.expect(host.middleTap == nil && host.removals == 1 && !host.gesture.isActive,
                     "revocation removes the tap and clears an in-flight middle press")
        suite.expect(Permissions.shared.requests == 1, "revocation does not repeat the permission prompt")
        Permissions.shared.accessibility = true
        suite.expect(host.installations == 2, "regranting permission restores the tap")
        host.sync(settings: .init(hold: .screenshot))
        Permissions.shared.accessibility = false
        Permissions.shared.accessibility = true
        suite.expect(host.middleTap == nil && host.installations == 2,
                     "hold-only settings never install a middle tap on permission changes")

        Permissions.shared.requests = 0
        let alreadyGranted = Host()
        alreadyGranted.watchAccessibility()
        alreadyGranted.sync(settings: alreadyGranted.settings)
        Permissions.shared.accessibility = false
        suite.expect(alreadyGranted.middleTap == nil && Permissions.shared.requests == 0,
                     "revoking a preexisting grant tears down quietly, without a new prompt")
        alreadyGranted.sync(settings: alreadyGranted.settings)
        alreadyGranted.sync(settings: alreadyGranted.settings)
        suite.expect(alreadyGranted.middleTap == nil && Permissions.shared.requests == 0,
                     "unrelated settings changes after revocation do not reopen the permission guide")
        Permissions.shared.accessibility = true
        suite.expect(alreadyGranted.middleTap != nil && alreadyGranted.installations == 2,
                     "regranting a preexisting permission restores the tap without a prompt")
        alreadyGranted.tearDownMiddleTap()
        alreadyGranted.sync(settings: alreadyGranted.settings)
        suite.expect(alreadyGranted.middleTap != nil && alreadyGranted.installations == 3
                     && Permissions.shared.requests == 0,
                     "unchanged settings still retry a missing tap silently when permission is available")
    }
}
