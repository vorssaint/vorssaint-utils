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
    final class Queue {
        static let main = Queue()
        var pending: [() -> Void] = []
        func async(execute: @escaping () -> Void) { pending.append(execute) }
        func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }
    enum Clock {
        static var processInfo: Self.Type { Self.self }
        static var systemUptime: TimeInterval = 100
    }
    final class EventSystemClient {}
    final class Keyboard {
        weak var client: EventSystemClient?
        static let superMapping = [["HIDKeyboardModifierMappingSrc": NSNumber(value: SuperKeySource.capsLock.usage),
                                    "HIDKeyboardModifierMappingDst": NSNumber(value: SuperKeySupport.triggerUsage)]]
        var mapping: [[String: NSNumber]]?
        var lockOn = false
        var lockReadable = true
        var deviceWrites: [Bool] = []

        init(mapped: Bool) { mapping = mapped ? Self.superMapping : nil }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        let isActive = true
        func onChange(_ handler: @escaping (Bool) -> Void) {}
    }
    enum ShortcutCapture { static func end() {} }
    class State {
        typealias DispatchQueue = Queue
        typealias ProcessInfo = Clock
        static var shared = State()
        static var isEngaged = true
        static let mouseDownTypes: [CGEventType] = [.leftMouseDown]
        let lifecycleLock = NSLock()
        let stateLock = NSLock()
        var state = SuperKeySupport.State()
        var eventSource = SuperKeySource.capsLock
        var source: SuperKeySource { eventSource }
        var soloAction = SuperKeySoloAction.inputSource
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
        let mappingQueue = Queue()
        var mappingGeneration: UInt = 0
        var rawCapsLockCount: UInt = 0
        var soloCapsLockWrite: (generation: UInt, count: UInt, on: Bool)?
        var lastMappingAt = Clock.systemUptime
        let mappingRepairInterval: TimeInterval = 3
        var repairs = 0
        var keyboards: [Keyboard] = []
        typealias IOHIDServiceClient = Keyboard
        let kHIDPage_GenericDesktop = 1
        let kHIDUsage_GD_Keyboard = 6
        var releasedClientAccesses = 0
        var propertyReads: [String] = []
        var lockReadable = true
        var lockWritable = true
        var soloWrites: [Bool] = []
        static var inputSourceChanges = 0
        func AXIsProcessTrusted() -> Bool { true }
        func syncWithPreferences() {}
        func clearEventTapThread() -> Bool { false }
        func startOnMain() {}
        func clearLeftoverMapping() { clearedMappings += 1 }
        func tapDidStart(_ tap: CFMachPort) {}
        func forgetHeldKey() { state.reset() }
        func armHeldKeyWatchdog() {}
        func cancelHeldKeyWatchdog() {}
        func observeWake() {}
        func confirmMapping(for tap: CFMachPort, generation: UInt, publishingRunState: Bool) {
            lastMappingAt = Clock.systemUptime
            mappingQueue.async {
                self.repairs += 1
                for keyboard in self.keyboards where keyboard.mapping == nil {
                    keyboard.mapping = Keyboard.superMapping
                }
            }
        }
        func IOHIDEventSystemClientCreateSimpleClient(_ allocator: CFAllocator?) -> EventSystemClient {
            EventSystemClient()
        }
        func IOHIDEventSystemClientCopyServices(_ client: EventSystemClient) -> AnyObject? {
            for keyboard in keyboards { keyboard.client = client }
            return keyboards as NSArray
        }
        func IOHIDServiceClientConformsTo(_ keyboard: Keyboard, _ page: UInt32, _ usage: UInt32) -> Int {
            if keyboard.client == nil { releasedClientAccesses += 1 }
            return 1
        }
        func IOHIDServiceClientCopyProperty(_ keyboard: Keyboard, _ key: CFString) -> AnyObject? {
            if keyboard.client == nil { releasedClientAccesses += 1 }
            propertyReads.append(key as String)
            if key as String == SuperKeySupport.userMappingProperty { return keyboard.mapping as NSArray? }
            guard key as String == "HIDCapsLockState", keyboard.lockReadable else { return nil }
            return NSNumber(value: keyboard.lockOn)
        }
        func IOHIDServiceClientSetProperty(_ keyboard: Keyboard, _ key: CFString, _ value: CFBoolean) -> Bool {
            if keyboard.client == nil { releasedClientAccesses += 1 }
            guard key as String == "HIDCapsLockState" else { return false }
            keyboard.lockOn = CFBooleanGetValue(value)
            keyboard.deviceWrites.append(keyboard.lockOn)
            return true
        }
        func capsLockIsOn() -> Bool? { lockReadable ? keyboards.contains { $0.lockOn } : nil }
        @discardableResult func setCapsLock(_ on: Bool) -> Bool {
            guard lockWritable else { return false }
            soloWrites.append(on)
            for keyboard in keyboards { keyboard.lockOn = on }
            return true
        }
        // Production receives keys on its dedicated tap thread.
        func runOnMainIfNeeded(_ work: @escaping () -> Void) { Queue.main.async(execute: work) }
        static func postKey(_ code: CGKeyCode) -> Bool { true }
        static func selectNextInputSource() { inputSourceChanges += 1 }
    }
    class RecordingState {
        typealias DispatchQueue = Queue
        static var tap: CFMachPort?
        static var runLoopSource: CFRunLoopSource?
        static var drainWatchdog: DispatchWorkItem?
        static var heldKeyCode: Int64?
        static var drainingKeyCode: Int64?
        static var superState = SuperKeySupport.State()
        static var superKeyTap: CFMachPort?
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
        let cleanup = SuperKeyService()
        let native = Keyboard(mapped: false)
        native.lockOn = true
        cleanup.keyboards = [native]
        cleanup.clearUnmappedCapsLock(reportedOn: false)
        suite.expect(cleanup.propertyReads == [SuperKeySupport.userMappingProperty, "HIDCapsLockState"]
                     && native.deviceWrites == [false] && cleanup.releasedClientAccesses == 0
                     && native.client == nil,
                     "Caps Lock cleanup keeps the HID client alive through keyboard selection, property reads and reset, then releases it")
        Tap.requests = []
        State.isEngaged = true
        let service = SuperKeyService()
        service.runEventTap()
        Queue.main.drain()
        suite.expect(Tap.requests.count == 1 && !service.isRunning && !State.isEngaged && service.clearedMappings == 1
                     && service.mappingFailure == .keyboardTapRefused,
                     "a refused keyboard tap stops the key and reports why, found \(String(describing: service.mappingFailure))")
        guard let request = Tap.requests.first else { return }
        defer {
            Tap.requests = []
            Queue.main.pending = []
            State.shared = State()
            State.isEngaged = false
            State.inputSourceChanges = 0
            Clock.systemUptime = 100
            RecordingState.handler = nil
            RecordingState.superState.reset()
            RecordingState.superKeyTap = nil
            RecordingState.heldKeyCode = nil
            RecordingState.drainingKeyCode = nil
            RecordingState.observingSession = false
        }
        let trigger = SuperKeySupport.triggerKeyCode
        let consumer = Request(location: .cgSessionEventTap, placement: .headInsertEventTap,
                               mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        let rawFilter = Request(location: .cghidEventTap, placement: .headInsertEventTap, mask: consumer.mask)
        State.inputSourceChanges = 0

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
                        && !remapper.state.isHeld && State.inputSourceChanges == 0 && remapper.soloWrites.isEmpty,
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
        guard let keyboardPort = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil) else {
            suite.expect(false, "the recorder fixture can allocate a local port")
            return
        }
        defer { CFMachPortInvalidate(keyboardPort) }
        service.tap = keyboardPort
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
                && leaked == 0 && State.inputSourceChanges == 0 && service.soloWrites.isEmpty && !service.state.isHeld,
                     "recording owns Super key chords and solo taps after a remapper restart, preserves ordinary shortcuts, "
                     + "and leaks no keys to a later session listener")

        // The kernel can already be sending F18 while readback is pending.
        captured = []
        State.isEngaged = false
        recording.send(key(trigger))
        recording.send(key(1))
        recording.send(key(1, down: false))
        recording.send(key(trigger, down: false))
        suite.expect(captured.map { $0.0 } == [1] && captured.first?.1 == service.eventModifiers,
                     "recording a chord before mapping confirmation captures the modifiers and never F18")

        recording.send(key(trigger))
        guard let replacementPort = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil) else {
            suite.expect(false, "the recorder fixture can replace a local port")
            return
        }
        defer { CFMachPortInvalidate(replacementPort) }
        service.tap = replacementPort
        recording.send(key(2))
        recording.send(key(2, down: false))
        suite.expect(captured.last?.0 == 2 && captured.last?.1 == [],
                     "a replacement tap cannot inherit a held trigger whose release was lost")
        service.shouldStopTapThread = true
        recording.send(key(trigger))
        recording.send(key(trigger, down: false))
        suite.expect(captured.last?.0 == trigger && captured.last?.1 == [],
                     "F18 remains recordable once the Super Key stops")
        service.shouldStopTapThread = false
        CFMachPortInvalidate(replacementPort)
        captured = []
        recording.send(key(trigger))
        recording.send(key(trigger, down: false))
        suite.expect(captured.map { $0.0 } == [trigger],
                     "a disabled tap does not reserve F18")
        service.tap = nil

        // HID hardware carries mach ticks; synthetic events carry nanoseconds.
        // Both must keep the same 500 ms tap/hold boundary on Apple Silicon.
        let timebase = EventTimestamp.machTimebase
        let now = mach_absolute_time()
        let timestampKinds = request.location == .cghidEventTap ? [true, false] : [false]
        for hardware in timestampKinds {
            for duration in [UInt64(300_000_000), 700_000_000] {
                let remapper = SuperKeyService()
                remapper.tap = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
                State.inputSourceChanges = 0
                let startTicks = now - 1_000_000_000 * timebase.denom / timebase.numer
                let endTicks = startTicks + duration * timebase.denom / timebase.numer
                let start = hardware ? startTicks : EventTimestamp.nanoseconds(ticks: startTicks, timebase: timebase)
                let end = hardware ? endTicks : EventTimestamp.nanoseconds(ticks: endTicks, timebase: timebase)
                _ = remapper.handle(type: .keyDown, event: key(trigger, timestamp: start))
                _ = remapper.handle(type: .keyUp, event: key(trigger, down: false, timestamp: end))
                Queue.main.drain()
                let longHold = duration > 500_000_000
                suite.expect(remapper.soloWrites == (longHold ? [true] : [])
                        && State.inputSourceChanges == (longHold ? 0 : 1),
                             "solo tap/hold timing survives the HID stage (hardware: \(hardware), ns: \(duration))")
            }
        }
        checkCapsLock(suite, request: request)
    }

    private static func checkCapsLock(_ suite: TestSuite, request: Request) {
        let service = SuperKeyService()
        service.soloAction = .capsLock
        guard let port = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil) else {
            suite.expect(false, "a local port represents the live tap in the Caps Lock contract")
            return
        }
        defer { CFMachPortInvalidate(port) }
        service.tap = port
        let first = Keyboard(mapped: true)
        let second = Keyboard(mapped: true)
        service.keyboards = [first, second]
        var pipeline = Pipeline()
        pipeline.install("super", request) { service.handle(type: $0.type, event: $0)?.takeUnretainedValue() }
        let trigger = SuperKeySupport.triggerKeyCode
        func flagsChanged(_ source: SuperKeySource, _ flags: CGEventFlags) -> CGEvent? {
            let raw = key(source.keyCode, flags: flags)
            raw.type = .flagsChanged
            return pipeline.send(raw)
        }
        func tapAlone(flags: CGEventFlags = []) {
            pipeline.send(key(trigger, flags: flags))
            pipeline.send(key(trigger, down: false, flags: flags))
        }

        tapAlone()
        Queue.main.drain()
        let echo = flagsChanged(.capsLock, .maskAlphaShift)
        Clock.systemUptime += 1
        service.mappingQueue.drain()
        service.finishStart()
        suite.expect(echo == nil && first.lockOn && second.lockOn && service.soloWrites == [true]
                && first.deviceWrites.isEmpty && second.deviceWrites.isEmpty,
               "a delayed lock notification and a late mapping confirmation preserve the solo tap on both keyboards")

        // The other ordering: a raw notification runs between F18 down and up.
        pipeline.send(key(trigger, flags: .maskAlphaShift))
        _ = flagsChanged(.capsLock, .maskAlphaShift)
        service.mappingQueue.drain()
        pipeline.send(key(trigger, down: false, flags: .maskAlphaShift))
        Queue.main.drain()
        _ = flagsChanged(.capsLock, [])
        service.mappingQueue.drain()
        suite.expect(!first.lockOn && !second.lockOn && service.soloWrites == [true, false],
                     "the second solo tap turns capitals off with a raw event before release and another after it")

        tapAlone()
        Queue.main.drain()
        let native = Keyboard(mapped: false)
        native.lockOn = true
        native.lockReadable = false
        service.keyboards.append(native)
        _ = flagsChanged(.capsLock, [])
        service.mappingQueue.drain()
        suite.expect(native.deviceWrites == [false] && native.mapping == nil && first.lockOn && second.lockOn
                && service.repairs == 0 && service.soloWrites == [true, false, true],
               "an unmapped keyboard still gets its own reset when the lock read fails and remapping is throttled")
        Clock.systemUptime += service.mappingRepairInterval
        native.lockOn = true
        _ = flagsChanged(.capsLock, .maskAlphaShift)
        service.mappingQueue.drain()
        suite.expect(native.deviceWrites == [false, false] && native.mapping != nil && service.repairs == 1
                && first.deviceWrites.isEmpty && second.deviceWrites.isEmpty,
               "a raw press on a new keyboard is neutralized before its mapping is installed")

        service.eventSource = .rightCommand
        service.lockReadable = false
        tapAlone(flags: .maskAlphaShift)
        Queue.main.drain()
        let passes = flagsChanged(.capsLock, .maskAlphaShift)
        _ = flagsChanged(.rightCommand, .maskAlphaShift)
        service.mappingQueue.drain()
        suite.expect(passes != nil && service.soloWrites == [true, false, true, false]
                && first.deviceWrites.isEmpty && native.deviceWrites == [false, false],
               "a right Command solo tap can toggle capitals from the event flags and its raw key leaves the lock alone")

        service.eventSource = .capsLock
        native.mapping = nil
        native.lockOn = true
        _ = flagsChanged(.capsLock, .maskAlphaShift)
        tapAlone()
        service.mappingGeneration += 1
        Queue.main.drain()
        service.mappingQueue.drain()
        suite.expect(native.lockOn && service.soloWrites == [true, false, true, false]
                && native.deviceWrites == [false, false],
               "queued solo and raw Caps Lock work cannot change the keyboard after that tap has stopped")

        native.lockOn = false
        service.lockReadable = true
        tapAlone()
        tapAlone()
        native.lockOn = true
        _ = flagsChanged(.capsLock, .maskAlphaShift)
        Queue.main.drain()
        service.mappingQueue.drain()
        suite.expect(service.soloWrites.suffix(2) == [true, false] && !first.lockOn
                && !second.lockOn && !native.lockOn,
               "two queued solo releases toggle in order even if a later native key turns the lock on before main runs")

        service.mappingGeneration += 1
        first.lockOn = true
        service.lockWritable = false
        let previousWrites = service.soloWrites
        tapAlone(flags: .maskAlphaShift)
        Queue.main.drain()
        service.lockWritable = true
        service.finishStart()
        suite.expect(!first.lockOn && service.soloWrites == previousWrites + [false],
                     "a failed solo write on a new tap cannot suppress its initial reset")
    }
}
