// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

/// Captures production tap registrations, then routes in-memory events through
/// the production handlers in Quartz order. No tap, mapping or input is posted.
enum SuperKeyTapContract {
    struct Request {
        let location: CGEventTapLocation
        let placement: CGEventTapPlacement
        let mask: CGEventMask
    }
    enum Tap {
        static var requests: [Request] = []
        static func create(tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions,
                           eventsOfInterest: CGEventMask, callback: CGEventTapCallBack,
                           userInfo: UnsafeMutableRawPointer?) -> CFMachPort? {
            requests.append(Request(location: tap, placement: place, mask: eventsOfInterest))
            return nil
        }
    }
    enum Queue {
        static var pending: [() -> Void] = []
        static var main: Queue.Type { Self.self }
        static func async(execute: @escaping () -> Void) { pending.append(execute) }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        let isActive = true
        func onChange(_ handler: @escaping (Bool) -> Void) {}
    }
    enum ShortcutCapture { static func end() {} }
    class State {
        typealias DispatchQueue = Queue
        static var shared = State()
        static var isEngaged = true
        static let mouseDownTypes: [CGEventType] = [.leftMouseDown]
        let lifecycleLock = NSLock()
        let stateLock = NSLock()
        var state = SuperKeySupport.State()
        var eventSource = SuperKeySource.capsLock
        var eventModifiers = SuperKeySupport.defaultModifiers
        var modifiers: GlobalShortcutModifiers { eventModifiers }
        var onHoldEnded: ((Bool) -> Void)?
        var tapRunLoop: CFRunLoop?
        var tapThread: Thread?
        var shouldStopTapThread = false
        var tap: CFMachPort?
        var mouseTap: CFMachPort?
        var mouseTapRefusals = 0
        var isRunning = true
        var mappingFailure: SuperKeyMappingFailure?
        var clearedMappings = 0
        var soloHolds: [Bool] = []
        func AXIsProcessTrusted() -> Bool { true }
        func syncWithPreferences() {}
        func clearEventTapThread() -> Bool { false }
        func startOnMain() {}
        func clearLeftoverMapping() { clearedMappings += 1 }
        func tapDidStart(_ tap: CFMachPort) {}
        func forgetHeldKey() { state.reset() }
        func armHeldKeyWatchdog() {}
        func cancelHeldKeyWatchdog() {}
        func repairMappingIfStale() {}
        func setCapsLock(_ enabled: Bool) {}
        func performSoloAction(longHold: Bool, repeated: Bool) { soloHolds.append(longHold) }
    }
    class RecordingState {
        typealias DispatchQueue = Queue
        static var tap: CFMachPort?
        static var runLoopSource: CFRunLoopSource?
        static var drainWatchdog: DispatchWorkItem?
        static var heldKeyCode: Int64?
        static var drainingKeyCode: Int64?
        static var superState = SuperKeySupport.State()
        static var observingSession = false
        static var handler: ((Int64, GlobalShortcutModifiers, CGEventFlags) -> Void)?
        static func AXIsProcessTrusted() -> Bool { true }
        static func tearDown() {}
        static func armDrainWatchdog() {}
    }
    struct Pipeline {
        struct Filter {
            let name: String
            let request: Request
            let handle: (CGEvent) -> CGEvent?
        }
        var filters: [Filter] = []

        mutating func install(_ name: String, _ request: Request,
                              handle: @escaping (CGEvent) -> CGEvent?) {
            filters.removeAll { $0.name == name }
            // HID precedes session; head insertion precedes older filters only
            // at the same location. Reinstalling models a daemon restart.
            let index = filters.firstIndex {
                $0.request.location.rawValue > request.location.rawValue
                    || ($0.request.location == request.location && request.placement == .headInsertEventTap)
            } ?? filters.count
            filters.insert(Filter(name: name, request: request, handle: handle), at: index)
        }

        @discardableResult
        func send(_ event: CGEvent) -> CGEvent? {
            var current = event
            for filter in filters where filter.request.mask & (1 << event.type.rawValue) != 0 {
                guard let next = filter.handle(current) else { return nil }
                current = next
            }
            return current
        }
    }

    static func key(_ code: Int64, down: Bool = true, flags: CGEventFlags = [],
                    timestamp: UInt64 = mach_absolute_time()) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
        event.flags = flags
        event.timestamp = timestamp
        return event
    }

    static func run(_ suite: TestSuite) {
        Tap.requests = []
        State.isEngaged = true
        let service = SuperKeyService()
        service.runEventTap()
        Queue.pending.forEach { $0() }
        Queue.pending = []
        suite.expect(Tap.requests.count == 1 && !service.isRunning && !State.isEngaged && service.clearedMappings == 1
                     && service.mappingFailure == .keyboardTapRefused,
                     "a refused keyboard tap stops the key and reports why, found \(String(describing: service.mappingFailure))")
        guard let request = Tap.requests.first else { return }
        defer {
            Tap.requests = []
            Queue.pending = []
            State.shared = State()
            State.isEngaged = false
            RecordingState.handler = nil
            RecordingState.superState.reset()
            RecordingState.heldKeyCode = nil
            RecordingState.drainingKeyCode = nil
            RecordingState.observingSession = false
        }
        let trigger = SuperKeySupport.triggerKeyCode
        let consumer = Request(location: .cgSessionEventTap, placement: .headInsertEventTap,
                               mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        let rawFilter = Request(location: .cghidEventTap, placement: .headInsertEventTap, mask: consumer.mask)

        for consumerStartsLast in [false, true] {
            let remapper = SuperKeyService()
            remapper.eventModifiers = [.control, .command]
            var seen: [(Int64, CGEventFlags)] = []
            var rawSeen: [(Int64, CGEventFlags)] = []
            var pipeline = Pipeline()
            let record: (CGEvent) -> CGEvent? = { event in
                seen.append((event.getIntegerValueField(.keyboardEventKeycode), event.flags))
                return event
            }
            let recordRaw: (CGEvent) -> CGEvent? = { event in
                rawSeen.append((event.getIntegerValueField(.keyboardEventKeycode), event.flags))
                return event
            }
            if !consumerStartsLast {
                pipeline.install("raw", rawFilter, handle: recordRaw)
                pipeline.install("consumer", consumer, handle: record)
            }
            pipeline.install("super", request) { remapper.handle(type: $0.type, event: $0)?.takeUnretainedValue() }
            if consumerStartsLast {
                pipeline.install("raw", rawFilter, handle: recordRaw)
                pipeline.install("consumer", consumer, handle: record)
            }
            for restarted in [false, true] {
                if restarted { pipeline.install("consumer", consumer, handle: record) }
                seen = []
                rawSeen = []
                pipeline.send(key(trigger))
                pipeline.send(key(8, flags: .maskAlternate))
                pipeline.send(key(8, down: false, flags: .maskAlternate))
                pipeline.send(key(trigger, down: false))
                pipeline.send(key(9, flags: .maskShift))
                let expected = remapper.eventModifiers.cgFlags.union(.maskAlternate)
                suite.expect(seen.map { $0.0 } == [8, 8, 9]
                        && seen.map { $0.1 } == [expected, expected, .maskShift]
                        && !remapper.state.isHeld && remapper.soloHolds.isEmpty,
                             "session shortcuts see both halves with chosen and physical modifiers, never F18, "
                             + "and release preserves ordinary typing (consumer last: \(consumerStartsLast), restart: \(restarted))")
                suite.expect(rawSeen.map { $0.0 } == [trigger, 8, 8, trigger, 9]
                        && rawSeen.map { $0.1 } == [[], .maskAlternate, .maskAlternate, [], .maskShift],
                             "HID head filters such as keyboard debounce retain the original keys and flags "
                             + "in either startup order (filter last: \(consumerStartsLast))")
            }
        }

        // A field still owns the trigger ahead of the remapper, including solo
        // presses that would otherwise switch layouts or post Escape.
        State.shared = service
        State.isEngaged = true
        service.eventModifiers = [.control, .option, .command]
        var captured: [(Int64, GlobalShortcutModifiers)] = []
        let capture: (Int64, GlobalShortcutModifiers, CGEventFlags) -> Void = { code, modifiers, _ in
            captured.append((code, modifiers))
        }
        _ = ShortcutRecordingTap.begin(capture)
        guard let recordingRequest = Tap.requests.last, Tap.requests.count == 2 else {
            suite.expect(false, "the recorder requests a keyboard tap")
            return
        }
        ShortcutRecordingTap.handler = capture
        var recording = Pipeline()
        recording.install("super", request) { service.handle(type: $0.type, event: $0)?.takeUnretainedValue() }
        recording.install("recorder", recordingRequest) { ShortcutRecordingTap.handle(type: $0.type, event: $0)?.takeUnretainedValue() }
        var leaked = 0
        recording.install("consumer", consumer) { event in leaked += 1; return event }
        recording.install("super", request) { service.handle(type: $0.type, event: $0)?.takeUnretainedValue() }
        recording.send(key(trigger))
        recording.send(key(12, flags: .maskShift))
        recording.send(key(12, down: false, flags: .maskShift))
        recording.send(key(trigger, down: false))
        recording.send(key(trigger))
        recording.send(key(trigger, down: false))
        recording.send(key(0, flags: .maskCommand))
        recording.send(key(0, down: false, flags: .maskCommand))
        suite.expect(captured.map { $0.0 } == [12, 0]
                && captured.map { $0.1 } == [.validMask, .command]
                && leaked == 0 && service.soloHolds.isEmpty && !service.state.isHeld,
                     "recording owns Super key chords and solo taps after a remapper restart, preserves ordinary shortcuts, "
                     + "and leaks no keys to a later session listener")

        // HID hardware carries mach ticks; synthetic events carry nanoseconds.
        // Both must keep the same 500 ms tap/hold boundary on Apple Silicon.
        let timebase = EventTimestamp.machTimebase
        let now = mach_absolute_time()
        let timestampKinds = request.location == .cghidEventTap ? [true, false] : [false]
        for hardware in timestampKinds {
            for duration in [UInt64(300_000_000), 700_000_000] {
                let remapper = SuperKeyService()
                let startTicks = now - 1_000_000_000 * timebase.denom / timebase.numer
                let endTicks = startTicks + duration * timebase.denom / timebase.numer
                let start = hardware ? startTicks : EventTimestamp.nanoseconds(ticks: startTicks, timebase: timebase)
                let end = hardware ? endTicks : EventTimestamp.nanoseconds(ticks: endTicks, timebase: timebase)
                _ = remapper.handle(type: .keyDown, event: key(trigger, timestamp: start))
                _ = remapper.handle(type: .keyUp, event: key(trigger, down: false, timestamp: end))
                suite.expect(remapper.soloHolds == [duration > 500_000_000],
                             "solo tap/hold timing survives the HID stage (hardware: \(hardware), ns: \(duration))")
            }
        }
    }
}
