// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Selects the next enabled input source when the Fn/🌐 key is tapped on its
/// own, with no picker and no wait. Holds and chords pass through untouched,
/// and every event leaves the tap as it came. Requires Accessibility.
final class FnInputSourceService: ObservableObject {
    static let shared = FnInputSourceService()

    @Published private(set) var isRunning = false

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var recognizer = FnInputSourceSupport.Recognizer()

    /// Presses the window server counts as key or button input. A press
    /// another tap swallowed before this one still moves these counters, and
    /// so does a click, which keeps clicks out of the tap altogether.
    private static let activityTypes: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
        // The event clock stops while the Mac sleeps, so a press held across
        // sleep would read as short on wake.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.feed(.interrupted) }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.fnInputSource.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.fnInputSourceEnabled)
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    /// What macOS itself does on a press of the 🌐 key, read afresh so the
    /// settings page follows a change made in System Settings.
    static func systemAction() -> FnInputSourceSupport.SystemAction {
        let domain = UserDefaults.standard.persistentDomain(forName: FnInputSourceSupport.systemPreferencesDomain)
        return FnInputSourceSupport.systemAction(raw: domain?[FnInputSourceSupport.systemPreferenceKey])
    }

    private func feed(_ event: FnInputSourceSupport.Recognizer.Event) {
        _ = eventLock.withLock { recognizer.handle(event) }
    }

    private func start() {
        feed(.interrupted)

        // The new thread is created and assigned inside the same critical
        // section as the decision, so a stop() can never observe no thread
        // while a start is committed (see KeyboardDebounceService).
        let startState = lifecycleLock.withLock { () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Fn Input Source"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        feed(.interrupted)

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
        publishRunning(false, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock {
                shouldStopTapThread
            }
            guard !shouldStopBeforeCreatingTap else {
                let shouldRestart = clearEventTapThread()
                if shouldRestart {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
                return
            }

            // At the HID stage, ahead of every session tap: function-key
            // routing, shortcut recording and the Super key all act on keys
            // later, so a chord is seen here before any of them can take it.
            let systemDefined = CGEventMask(1) << CGEventMask(FnInputSourceSupport.systemDefinedEventTypeRawValue)
            let mask = [CGEventType.flagsChanged, .keyDown, .keyUp]
                .reduce(systemDefined) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<FnInputSourceService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            feed(.interrupted)

            let shouldStop = lifecycleLock.withLock {
                shouldStopTapThread
            }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            feed(.interrupted)
            let shouldRestart = clearEventTapThread()
            if shouldRestart {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            self.isRunning = running
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Events went by while the tap was off, so a press under way
            // cannot be trusted to be solo.
            feed(.interrupted)
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }

        let reading = FnInputSourceSupport.reading(type: type,
                                                   keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                                   flags: event.flags,
                                                   isOwnEvent: OwnKeyEvent.isPosted(event))
        let input: FnInputSourceSupport.Recognizer.Event
        switch reading {
        case .unrelated:
            return Unmanaged.passUnretained(event)
        case .otherInput:
            input = .otherInput
        case .fnDown, .fnUp:
            let timestamp = EventTimestamp.nanoseconds(of: event)
            let held = FnInputSourceSupport.otherInputHeld(flags: event.flags) {
                CGEventSource.keyState(.hidSystemState, key: $0)
            }
            let activity = Self.activityTypes.reduce(UInt64(0)) {
                $0 &+ UInt64(CGEventSource.counterForEventType(.hidSystemState, eventType: $1))
            }
            input = reading == .fnDown
                ? .fnDown(timestamp: timestamp, otherInputHeld: held, activity: activity)
                : .fnUp(timestamp: timestamp, otherInputHeld: held, activity: activity)
        }

        let completesTap = eventLock.withLock { recognizer.handle(input) }
        if completesTap {
            // Selected before the release goes on, so the key typed next
            // already lands in the new source.
            InputSourceSelection.selectNext()
        }
        return Unmanaged.passUnretained(event)
    }
}
