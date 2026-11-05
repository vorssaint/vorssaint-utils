// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The production Fn and debounce callbacks run together against fake HID
/// readings. No input is posted and no input source or permission is changed.
enum FnInputSourceTapTests {
    enum CGEventSource {
        static var keys: Set<CGKeyCode> = []
        static var presses: UInt32 = 0
        static func keyState(_ state: CGEventSourceStateID, key: CGKeyCode) -> Bool { keys.contains(key) }
        static func counterForEventType(_ state: CGEventSourceStateID, eventType: CGEventType) -> UInt32 {
            eventType == .keyDown ? presses : 0
        }
        static func tapEnable(tap: CFMachPort, enable: Bool) {}
    }
    enum InputSourceSelection {
        static var switches = 0
        static func selectNext() { switches += 1 }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        let isActive = true
        private let lock = NSLock()
        private var registrations: [Bool] = []
        var registrationThreads: [Bool] { lock.withLock { registrations } }
        func onChange(_ handler: @escaping (Bool) -> Void) {
            lock.withLock { registrations.append(Thread.isMainThread) }
        }
    }
    final class NSWorkspace {
        static let shared = NSWorkspace()
        static let willSleepNotification = Notification.Name("testSleep")
        let notificationCenter = Center()
        final class Center {
            func addObserver(forName: Notification.Name, object: Any?, queue: OperationQueue?,
                             using handler: @escaping (Notification) -> Void) {}
        }
    }
    final class Service {
        // Bind transports on the extended type itself: an out-of-line
        // extension must never resolve these names to the live system APIs.
        typealias CGEventSource = FnInputSourceTapTests.CGEventSource
        typealias InputSourceSelection = FnInputSourceTapTests.InputSourceSelection
        typealias SessionActivity = FnInputSourceTapTests.SessionActivity
        typealias NSWorkspace = FnInputSourceTapTests.NSWorkspace
        let eventLock = NSLock()
        let lifecycleLock = NSLock()
        var recognizer = FnInputSourceSupport.Recognizer()
        var pressedKeys = FnInputSourceSupport.PressedKeys()
        var shouldStopTapThread = false
        var tapThread: Thread? = Thread {}
        var tap: CFMachPort?
        init() { initialize() }
        func syncWithPreferences() {}
    }

    private static func fresh() -> Service {
        CGEventSource.keys = []
        CGEventSource.presses = 0
        InputSourceSelection.switches = 0
        return Service()
    }

    private static func event(_ type: CGEventType, key: CGKeyCode = 0,
                              milliseconds: UInt64, own: Bool = false) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown)!
        event.type = type
        event.flags = []
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventSourceUserData, value: own ? OwnKeyEvent.quitProtectionMarker : 0)
        let timebase = EventTimestamp.machTimebase
        event.timestamp = milliseconds * 1_000_000 * timebase.denom / timebase.numer
        return event
    }

    private static func fn(_ service: Service, at start: UInt64 = 130) {
        let down = event(.flagsChanged, key: 63, milliseconds: start)
        down.flags = .maskSecondaryFn
        _ = service.handle(type: .flagsChanged, event: down)
        let up = event(.flagsChanged, key: 63, milliseconds: start + 50)
        up.flags = []
        _ = service.handle(type: .flagsChanged, event: up)
    }

    static func run(_ suite: TestSuite) {
        final class CallbackResult { var passed: [Bool] = [] }
        let callbackResult = CallbackResult()
        let coldDebounce = KeyboardDebounceTapTests.Service()
        let callbackFinished = DispatchSemaphore(value: 0)
        Thread {
            for (type, time): (CGEventType, UInt64) in [(.keyDown, 100), (.keyUp, 110),
                                                       (.keyDown, 120), (.keyUp, 130)] {
                callbackResult.passed.append(
                    coldDebounce.handle(type: type, event: event(type, milliseconds: time)) != nil)
            }
            callbackFinished.signal()
        }.start()
        suite.expect(callbackFinished.wait(timeout: .now() + 5) == .success,
                     "debounce can drop keys without waiting for the main thread")
        suite.expect(callbackResult.passed == [true, true, false, true],
                     "the background callback suppresses a rapid physical press but preserves releases")
        suite.expect(SessionActivity.shared.registrationThreads.isEmpty,
                     "suppressed keys with Fn uninitialized do not register any session observer")

        for debounceFirst in [true, false] {
            let fnService = fresh()
            let debounce = KeyboardDebounceTapTests.Service()
            debounce.config = KeyboardDebounceConfig(enabled: true, globalWindowMs: 500, keyWindows: [:])
            func key(_ down: Bool, at time: UInt64) -> Bool {
                if down {
                    CGEventSource.keys.insert(0)
                    CGEventSource.presses &+= 1
                } else {
                    CGEventSource.keys.remove(0)
                }
                let input = event(down ? .keyDown : .keyUp, milliseconds: time)
                if !debounceFirst { _ = fnService.handle(type: input.type, event: input) }
                let passed = debounce.handle(type: input.type, event: input) != nil
                if debounceFirst && passed { _ = fnService.handle(type: input.type, event: input) }
                return passed
            }
            suite.expect(key(true, at: 100) && key(false, at: 110),
                         "the initial physical press passes debounce (debounce first: \(debounceFirst))")
            suite.expect(!key(true, at: 120), "debounce suppresses the rapid second key down")
            fn(fnService)
            suite.expect(InputSourceSelection.switches == 0,
                         "a held key hidden by debounce prevents a solo Fn switch in either tap order")
            _ = key(false, at: 200)
            fn(fnService, at: 330)
            suite.expect(InputSourceSelection.switches == 1,
                         "the suppressed release clears the held key and the next solo tap switches once")
        }

        let phantom = fresh()
        CGEventSource.keys = [57, 127]
        fn(phantom)
        suite.expect(InputSourceSelection.switches == 1, "phantom Caps Lock and 127 do not block the real handler")

        let syntheticRelease = fresh()
        CGEventSource.keys = [0]
        CGEventSource.presses = 1
        _ = syntheticRelease.handle(type: .keyDown, event: event(.keyDown, milliseconds: 100))
        _ = syntheticRelease.handle(type: .keyUp, event: event(.keyUp, milliseconds: 110, own: true))
        fn(syntheticRelease)
        suite.expect(InputSourceSelection.switches == 0,
                     "an app-posted release cannot hide a physical key still held before Fn")
        CGEventSource.keys = []
        _ = syntheticRelease.handle(type: .keyUp, event: event(.keyUp, milliseconds: 200))
        fn(syntheticRelease, at: 330)
        suite.expect(InputSourceSelection.switches == 1, "a real release restores normal solo taps")

        let interrupted = fresh()
        let down = event(.flagsChanged, key: 63, milliseconds: 130)
        down.flags = .maskSecondaryFn
        _ = interrupted.handle(type: .flagsChanged, event: down)
        interrupted.feed(.interrupted)
        _ = interrupted.handle(type: .flagsChanged, event: event(.flagsChanged, key: 63, milliseconds: 180))
        suite.expect(InputSourceSelection.switches == 0, "the real feed path cancels a tap after interruption")
        fn(interrupted, at: 330)
        suite.expect(InputSourceSelection.switches == 1, "a fresh tap works after the interrupted press")

        let stopped = fresh()
        stopped.shouldStopTapThread = true
        Service.observeFilteredKeyIfRunning(type: .keyDown, event: event(.keyDown, milliseconds: 100))
        suite.expect(stopped.pressedKeys.codes.isEmpty, "debounce cannot feed a stopping Fn service")
        stopped.shouldStopTapThread = false
        stopped.tapThread = nil
        Service.observeFilteredKeyIfRunning(type: .keyDown, event: event(.keyDown, milliseconds: 110))
        suite.expect(stopped.pressedKeys.codes.isEmpty, "debounce cannot feed an inactive Fn service")
        suite.expect(SessionActivity.shared.registrationThreads.allSatisfy { $0 },
                     "Fn session observers are registered only by main-thread initialization")
    }
}
