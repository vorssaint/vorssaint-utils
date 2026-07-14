// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import CoreGraphics
import Foundation

/// Suppresses accidental duplicate physical key presses inside a short window.
/// Auto-repeat from a held key is left untouched so normal key-repeat behavior
/// keeps working.
final class KeyboardDebounceService: ObservableObject {
    static let shared = KeyboardDebounceService()

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
    private var state = KeyboardDebounceState()
    private var config = KeyboardDebounceConfig(enabled: false,
                                                globalWindowMs: Defaults.defaultKeyboardDebounceWindowMs,
                                                keyWindows: [:])

    private init() {}

    func syncWithPreferences() {
        let nextConfig = KeyboardDebounceConfig(
            enabled: AppFeature.keyboardDebounce.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.keyboardDebounceEnabled),
            globalWindowMs: Defaults.sanitizedKeyboardDebounceWindow(
                UserDefaults.standard.integer(forKey: DefaultsKey.keyboardDebounceWindowMs)
            ),
            keyWindows: KeyboardDebounceConfig.decodeKeyWindows(
                UserDefaults.standard.string(forKey: DefaultsKey.keyboardDebounceKeyWindows) ?? ""
            )
        )
        eventLock.withLock {
            config = nextConfig
        }

        if nextConfig.enabled, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    private func start() {
        eventLock.withLock {
            state.reset()
        }

        // The new thread is created and assigned to tapThread inside the same
        // critical section as the decision: a stop() must never observe
        // tapThread == nil while a start is committed, or it would reset
        // shouldStopTapThread and let the new thread enable a tap whose
        // "running" publish is then dropped as stale — a live tap with the
        // feature showing disabled.
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
            thread.name = "Vorssaint Keyboard Debounce"
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
        eventLock.withLock {
            state.reset()
        }

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
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

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<KeyboardDebounceService>.fromOpaque(userInfo).takeUnretainedValue()
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
            eventLock.withLock {
                state.reset()
            }

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
            eventLock.withLock {
                state.reset()
            }
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
            let currentTap = lifecycleLock.withLock {
                tap
            }
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let timestamp = UInt64(event.timestamp)
        let eventKind: KeyboardDebounceState.EventKind = type == .keyDown ? .keyDown : .keyUp
        let shouldSuppress = eventLock.withLock {
            state.shouldSuppress(keyCode: keyCode,
                                 isAutoRepeat: isRepeat,
                                 event: eventKind,
                                 timestampNanoseconds: timestamp,
                                 config: config)
        }
        if shouldSuppress {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

