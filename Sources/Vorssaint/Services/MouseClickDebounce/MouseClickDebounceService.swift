// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Filters a complete accidental click immediately after a healthy click.
/// Healthy Down and Up events are never delayed. A suppressed bounce Down owns
/// exactly one suppressed Up, while every Up belonging to an accepted Down is
/// passed through, so lifecycle resets cannot leave a button stuck. This safe
/// boundary filters complete extra clicks; it does not delay an Up to repair
/// contact noise in the middle of a click being held.
final class MouseClickDebounceService {
    static let shared = MouseClickDebounceService()

    private static let ownProcessID = Int64(getpid())

    private static let eventMask: CGEventMask = [
        CGEventType.leftMouseDown,
        .leftMouseDragged,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseDragged,
        .rightMouseUp,
        .otherMouseDown,
        .otherMouseDragged,
        .otherMouseUp,
    ].reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }

    private let eventLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    private var sleepObservers: [NSObjectProtocol] = []
    private var state = MouseClickDebounceState()
    private var config = MouseClickDebounceConfig(
        enabled: false,
        windowMilliseconds: Defaults.defaultMouseClickDebounceWindowMs
    )

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.mouseClickDebounce.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.mouseClickDebounceEnabled)
        let shouldRun = SessionActivitySupport.tapShouldRun(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        )
        let nextConfig = MouseClickDebounceConfig(
            enabled: shouldRun,
            windowMilliseconds: Defaults.sanitizedMouseClickDebounceWindow(
                UserDefaults.standard.integer(forKey: DefaultsKey.mouseClickDebounceWindowMs)
            )
        )
        eventLock.withLock {
            config = nextConfig
            state.reset()
        }

        if shouldRun {
            installSleepObservers()
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    private func start() {
        let thread: Thread? = lifecycleLock.withLock {
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                }
                return nil
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let thread = Thread { [weak self] in
                self?.runEventTap()
            }
            thread.name = "Vorssaint Mouse Click Debounce"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop() {
        removeSleepObservers()
        eventLock.withLock {
            state.reset()
        }
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap)
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
        }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }
            let shouldStopBeforeCreatingTap = lifecycleLock.withLock {
                shouldStopTapThread
            }
            guard !shouldStopBeforeCreatingTap else {
                finishEventTapThread()
                return
            }

            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<MouseClickDebounceService>
                        .fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                finishEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            eventLock.withLock {
                state.reset()
            }
            finishEventTapThread()
        }
    }

    private func finishEventTapThread() {
        let restart = clearEventTapThread()
        guard restart.shouldRestart else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                restart.generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            self.syncWithPreferences()
        }
    }

    private func clearEventTapThread() -> (shouldRestart: Bool, generation: UInt) {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            let generation = lifecycleGeneration
            tap = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return (shouldRestart, generation)
        }
    }

    private func installSleepObservers() {
        guard sleepObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.eventLock.withLock {
                    self.state.reset()
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.suspend()
                self.syncWithPreferences()
            },
        ]
    }

    private func removeSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in sleepObservers {
            center.removeObserver(observer)
        }
        sleepObservers.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            eventLock.withLock {
                state.reset()
            }
            let stopping = lifecycleLock.withLock { shouldStopTapThread }
            let shouldRearm = eventLock.withLock { config.enabled }
                && SessionActivity.shared.isActive
                && AXIsProcessTrusted()
                && !stopping
            let currentTap = lifecycleLock.withLock { tap }
            if shouldRearm, let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else {
                let recoveryGeneration = lifecycleLock.withLock { lifecycleGeneration }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let isCurrent = self.lifecycleLock.withLock {
                        recoveryGeneration == self.lifecycleGeneration
                    }
                    guard isCurrent else { return }
                    self.stop()
                    self.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard event.getIntegerValueField(.eventSourceUnixProcessID) != Self.ownProcessID,
              let input = MouseClickDebounceInput.resolve(
                type: type,
                buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber)
              ) else {
            return Unmanaged.passUnretained(event)
        }

        let shouldSuppress = eventLock.withLock {
            state.shouldSuppress(
                button: input.button,
                event: input.event,
                timestampNanoseconds: UInt64(event.timestamp),
                config: config
            )
        }
        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }
}
