// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// The production observer, startup, update, finish and cancellation bodies are
/// extracted on every test build. Only scheduling, system snapshots and AX/UI
/// dependencies are replaced. Events are passed directly, never posted.
enum WindowDirectionalModifierRuntimeTests {
    static var accessibilityGranted = true

    enum ShortcutCapture { static var isCapturing = false }
    final class SessionActivity {
        static let shared = SessionActivity()
        var isActive = true
    }
    enum NSEvent { static var mouseLocation = CGPoint(x: 100, y: 400) }
    enum CGEventSource {
        static var buttons: UInt32 = 0
        static var clicks: UInt32 = 0
        static var scrolls: UInt32 = 0
        static var flags: CGEventFlags = []
        static func counterForEventType(_ state: CGEventSourceStateID, eventType: CGEventType) -> UInt32 {
            switch eventType {
            case .leftMouseDown: return clicks
            case .scrollWheel: return scrolls
            default: return 0
            }
        }
        static func buttonState(_ state: CGEventSourceStateID, button: CGMouseButton) -> Bool {
            buttons & (UInt32(1) << button.rawValue) != 0
        }
        static func flagsState(_ state: CGEventSourceStateID) -> CGEventFlags { flags }
    }
    enum WindowDirectionalModifierTapSupport {
        static var jobs: [() -> Void] = []
        static func afterCallback(_ work: @escaping () -> Void) { jobs.append(work) }
        static func drain() {
            while !jobs.isEmpty { jobs.removeFirst()() }
        }
    }
    final class Timer {
        static func scheduledTimer(withTimeInterval: TimeInterval, repeats: Bool,
                                   block: @escaping (Timer) -> Void) -> Timer { Timer() }
        func invalidate() {}
    }
    struct NSScreen { let visibleFrame = CGRect(x: -1000, y: 0, width: 2000, height: 1000) }
    struct WindowLayoutTarget {
        let serial: Int
        let frame = CGRect(x: 0, y: 0, width: 600, height: 500)
    }
    struct Placement { var rect = CGRect.zero }

    class Fixture {
        var directionalModifierHold: WindowDirectionalModifierHold? = .init(expected: [.control, .command])
        var directionalModifierButtons = WindowDirectionalModifierButtons()
        var directionalSession: WindowDirectionalSession?
        var registeredDirectionalTrigger: WindowDirectionalTrigger? = .modifiers([.control, .command])
        var directionalModifierTap: CFMachPort? = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
        var directionalTimer: Timer?
        var directionalShortcutRegistrationFailed = false
        var starts = 0
        var activeTapStarts = 0
        var reenables = 0
        var targetSerial = 0
        var placed: [WindowLayoutAction] = []
        var onLookup: (() -> Void)?
        let menuBarScreenTopY: CGFloat = 1000

        deinit {
            if let directionalModifierTap { CFMachPortInvalidate(directionalModifierTap) }
        }
        func isAnyMouseButtonPressed() -> Bool { CGEventSource.buttons != 0 }
        func startDirectionalTap() -> Bool {
            activeTapStarts += 1
            return true
        }
        func stopDirectionalTap() {}
        func tapEnable(tap: CFMachPort, enable: Bool) {
            if enable { reenables += 1 }
        }
        func focusedTarget(for action: WindowLayoutAction) -> WindowLayoutTarget? {
            targetSerial += 1
            let callback = onLookup
            onLookup = nil
            callback?()
            return WindowLayoutTarget(serial: targetSerial)
        }
        func bestScreen(for frame: CGRect) -> NSScreen? { NSScreen() }
        func showDirectionalIndicator(at pointer: CGPoint, action: WindowDirectionalAction?) { starts += 1 }
        func updateDirectionalIndicator(action: WindowDirectionalAction?) {}
        func hideDirectionalIndicator() {}
        func hideEdgeSnapPreview(immediately: Bool) {}
        func showEdgeSnapPreview(frame: CGRect) {}
        func placement(for action: WindowLayoutAction, current: CGRect, visibleFrame: CGRect) -> Placement { Placement() }
        func applyPlacement(_ action: WindowLayoutAction, to target: WindowLayoutTarget,
                            visibleFrame: CGRect, cyclesRepeatedAction: Bool) -> Bool {
            placed.append(action)
            return true
        }
        func minimize(target: WindowLayoutTarget) -> Bool { true }
        func unregisterDirectionalHotkey() {
            directionalTimer?.invalidate()
            directionalSession = nil
            directionalModifierHold = nil
            registeredDirectionalTrigger = nil
        }
    }

    @discardableResult
    private static func send(_ host: Host, _ type: CGEventType,
                             flags: GlobalShortcutModifiers = [],
                             point: CGPoint = CGPoint(x: 200, y: 600),
                             button: Int64 = 0) -> Bool {
        guard let event = CGEvent(source: nil) else { return false }
        event.flags = flags.cgFlags
        event.location = point
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return host.observeDirectionalModifierEvent(type: type, event: event)?.takeUnretainedValue() === event
    }

    private static func press(_ host: Host) {
        send(host, .flagsChanged, flags: .control)
        send(host, .flagsChanged, flags: [.control, .command])
    }
    private static func release(_ host: Host, point: CGPoint = CGPoint(x: 200, y: 600)) {
        send(host, .flagsChanged, flags: .control, point: point)
        send(host, .flagsChanged, point: point)
    }
    private static func start(_ host: Host) {
        press(host)
        WindowDirectionalModifierTapSupport.drain()
    }

    static func run(_ suite: TestSuite) {
        defer {
            WindowDirectionalModifierTapSupport.jobs.removeAll()
            CGEventSource.buttons = 0
            CGEventSource.clicks = 0
            CGEventSource.scrolls = 0
            CGEventSource.flags = []
            NSEvent.mouseLocation = CGPoint(x: 100, y: 400)
            accessibilityGranted = true
            ShortcutCapture.isCapturing = false
            SessionActivity.shared.isActive = true
        }
        let first = Host()
        start(first)
        suite.expect(first.starts == 1 && first.activeTapStarts == 0,
                     "modifier startup uses its existing passive tap and creates no filtering tap")
        let oldOwner = first.directionalSession?.modifierOwnership
        release(first)
        press(first)
        WindowDirectionalModifierTapSupport.drain()
        suite.expect(first.starts == 2 && first.directionalSession?.target.serial == 2
                && first.directionalSession?.modifierOwnership != oldOwner && first.placed.isEmpty,
                     "a late release retires its old session before a fresh chord starts")
        first.cancelDirectionalGesture()

        for keyCancellation in [false, true] {
            let host = Host()
            start(host)
            if keyCancellation {
                send(host, .keyDown, flags: [.control, .command])
            } else {
                send(host, .flagsChanged, flags: [.control, .command, .shift])
            }
            release(host)
            press(host)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.starts == 2 && host.directionalSession?.target.serial == 2
                    && host.placed.isEmpty,
                         "late key or extra-modifier cancellation cleans only the retired session")
            host.cancelDirectionalGesture()
        }

        // The physical click or scroll already finished before the chord callback.
        // Test both queue schedules, with startup still pending or already running.
        for startBeforePointerCallback in [false, true] {
            for pointerType in [CGEventType.leftMouseDown, .scrollWheel] {
                CGEventSource.clicks = 1
                CGEventSource.scrolls = 1
                let host = Host()
                press(host)
                if startBeforePointerCallback { WindowDirectionalModifierTapSupport.drain() }
                suite.expect(send(host, pointerType, flags: [.control, .command]),
                             "the passive cancellation event stays available to its application")
                if pointerType == .leftMouseDown {
                    send(host, .leftMouseUp, flags: [.control, .command])
                }
                release(host)
                WindowDirectionalModifierTapSupport.drain()
                suite.expect(host.directionalSession == nil && host.placed.isEmpty,
                             "completed pointer input before the snapshot still cancels before release")
            }
        }

        // A mouse button was held at the physical chord press but had already
        // been released by the time the main thread could service these callbacks.
        for (down, up, button) in [(CGEventType.leftMouseDown, CGEventType.leftMouseUp, Int64(0)),
                                   (.rightMouseDown, .rightMouseUp, 1),
                                   (.otherMouseDown, .otherMouseUp, 4)] {
            let host = Host()
            send(host, down, button: button)
            press(host)
            send(host, up, flags: [.control, .command], button: button)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.starts == 0 && !host.directionalModifierButtons.isPressed,
                         "button history rejects a chord pressed during an already-completed drag")
            release(host)
            press(host)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.starts == 1,
                         "a new chord works after the drag and all modifiers have ended")
            host.cancelDirectionalGesture()
        }
        CGEventSource.buttons = 1 << 5
        let seeded = WindowDirectionalModifierButtons.current()
        suite.expect(seeded.isPressed && seeded.mask == 1 << 5,
                     "registration preserves a button that was already held")
        CGEventSource.buttons = 0

        for releaseDuringLookup in [false, true] {
            let host = Host()
            host.onLookup = {
                if releaseDuringLookup { release(host) }
                else { send(host, .keyDown, flags: [.control, .command]) }
            }
            start(host)
            suite.expect(host.starts == 0 && host.directionalSession == nil,
                         "nested input during target lookup invalidates startup before a session exists")
            release(host)
            press(host)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.starts == 1,
                         "discarding a stale lookup preserves the next fresh chord")
            host.cancelDirectionalGesture()
        }

        let replaced = Host()
        press(replaced)
        replaced.directionalModifierHold = .init(expected: [.control, .command])
        press(replaced)
        WindowDirectionalModifierTapSupport.drain()
        suite.expect(replaced.starts == 1 && replaced.targetSerial == 1,
                     "a queued callback cannot borrow a replacement registration's generation")
        replaced.cancelDirectionalGesture()

        let east = Host()
        NSEvent.mouseLocation = CGPoint(x: 100, y: 400)
        start(east)
        release(east, point: CGPoint(x: 200, y: 600))
        NSEvent.mouseLocation = CGPoint(x: 0, y: 400)
        WindowDirectionalModifierTapSupport.drain()
        suite.expect(east.placed == [.rightHalf],
                     "the captured release position wins over later movement of the pointer")

        for (releasePoint, expected) in [(CGPoint(x: -200, y: 500), WindowLayoutAction.topHalf),
                                         (CGPoint(x: -200, y: 900), .bottomHalf)] {
            NSEvent.mouseLocation = CGPoint(x: -200, y: 300)
            let host = Host()
            start(host)
            release(host, point: releasePoint)
            NSEvent.mouseLocation = CGPoint(x: 500, y: 500)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.placed == [expected],
                         "release conversion uses the menu-bar display origin for negative-coordinate displays")
        }
        let noSelection = Host()
        NSEvent.mouseLocation = CGPoint(x: 100, y: 400)
        start(noSelection)
        release(noSelection, point: CGPoint(x: 100, y: 600))
        NSEvent.mouseLocation = CGPoint(x: 700, y: 400)
        WindowDirectionalModifierTapSupport.drain()
        suite.expect(noSelection.placed.isEmpty,
                     "movement after an unselected release cannot invent a placement")

        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let host = Host()
            CGEventSource.flags = GlobalShortcutModifiers([.control, .command]).cgFlags
            start(host)
            send(host, type)
            CGEventSource.flags = []
            WindowDirectionalModifierTapSupport.drain()
            press(host)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.reenables == 1 && host.starts == 2,
                         "recovery notices releases missed while disabled and accepts the first fresh chord")
            host.cancelDirectionalGesture()
        }
        for permissionLost in [false, true] {
            let host = Host()
            start(host)
            accessibilityGranted = !permissionLost
            SessionActivity.shared.isActive = permissionLost
            send(host, .tapDisabledByTimeout)
            WindowDirectionalModifierTapSupport.drain()
            suite.expect(host.reenables == 0 && host.registeredDirectionalTrigger == nil
                    && host.directionalSession == nil,
                         "a disabled tap never restarts after losing its session or Accessibility")
            accessibilityGranted = true
            SessionActivity.shared.isActive = true
        }

        let pendingKey = Host()
        press(pendingKey)
        send(pendingKey, .keyDown, flags: [.control, .command])
        release(pendingKey)
        WindowDirectionalModifierTapSupport.drain()
        suite.expect(pendingKey.starts == 0 && pendingKey.placed.isEmpty,
                     "an ordinary shortcut still cancels queued modifier startup")

        let keyTrigger = Host()
        keyTrigger.directionalModifierHold = nil
        keyTrigger.registeredDirectionalTrigger = .key(.windowDirectionalDefault)
        keyTrigger.beginDirectionalGesture()
        keyTrigger.directionalSession?.action = .maximize
        keyTrigger.finishDirectionalGesture()
        suite.expect(keyTrigger.activeTapStarts == 1 && keyTrigger.placed == [.maximize],
                     "the existing key trigger retains its filtering tap and manual override")
    }
}
