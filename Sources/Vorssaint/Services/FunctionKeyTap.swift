// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// The one session keystroke tap every F-row feature answers through. The
/// brightness keys ran it alone first (`BrightnessService`); the per-app
/// Fn-Lock (issue #1227) needs the same events and must see them first, so
/// the tap became shared and each feature registers a listener.
///
/// Listeners run in priority order, lowest first, and each receives the
/// event the previous one returned: the Fn-Lock (priority 0) translates a
/// media keycode before the brightness keys (10) and the brightness media
/// keys (20) can act on it, so a listed app's F2 reaches the app instead of
/// stepping a display. The first listener to return nil consumes the key
/// for everyone after it and for the system.
///
/// The tap watches key-down, key-up and the NX system-defined media form,
/// because the F row arrives in either shape depending on the key and the
/// keyboard (brightness as a plain press on some keyboards and as an NX id
/// on others; volume and transport as NX ids). The window server holds
/// every keystroke until the tap answers, so the tap owns a dedicated
/// thread and every listener answers without touching the main thread.
final class FunctionKeyTap {
    struct Listener {
        let name: String
        /// Lower runs first. The Fn-Lock must see a media keycode before
        /// the brightness features can consume it.
        let priority: Int
        /// Runs on the tap thread. Receives the event as the previous
        /// listener returned it; nil consumes it.
        let route: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    }

    static let shared = FunctionKeyTap()

    /// Guards the listener list, the tap lifecycle and the suspended flag:
    /// written on the main thread, read from the tap thread.
    private let tapLock = NSLock()
    /// Sorted by priority at every mutation, so the tap thread chains them
    /// without sorting per event. Swift arrays are copy-on-write, so the
    /// per-event read under the lock is one retain, not a copy.
    private var listeners: [Listener] = []
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var shouldStopThread = false
    private var pendingRestart = false
    /// True while a permission reset owns the taps: the tap is torn down
    /// and no event is answered by this app until the reset is over.
    private var suspended = false

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.sync() }
    }

    // MARK: - Listeners (main thread)

    /// Registers or replaces the listener named `name` and brings the tap
    /// up or down to match. MUST run on the main thread.
    func addListener(named name: String, priority: Int,
                     route: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) {
        precondition(Thread.isMainThread)
        let listener = Listener(name: name, priority: priority, route: route)
        tapLock.withLock {
            listeners.removeAll { $0.name == name }
            listeners.append(listener)
            listeners.sort { $0.priority == $1.priority
                ? $0.name < $1.name : $0.priority < $1.priority }
        }
        sync()
    }

    /// Removes the listener named `name` and brings the tap down when no
    /// listener is left. MUST run on the main thread.
    func removeListener(named name: String) {
        precondition(Thread.isMainThread)
        tapLock.withLock { listeners.removeAll { $0.name == name } }
        sync()
    }

    /// Installs the tap when a listener wants it and the session allows
    /// answering, removes it otherwise. Idempotent; safe to call from any
    /// preference sync. MUST run on the main thread.
    func sync() {
        precondition(Thread.isMainThread)
        let wanted = tapLock.withLock { () -> Bool in
            guard !suspended, !listeners.isEmpty else { return false }
            return true
        } && SessionActivitySupport.tapShouldRun(
            featureWanted: true,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive)
        if wanted { installTap() } else { removeTap() }
    }

    // MARK: - Permission resets (main thread)

    /// Tears the tap down before a TCC reset so no event is answered while
    /// the permission work is in progress. MUST run on the main thread.
    func suspend() {
        precondition(Thread.isMainThread)
        tapLock.withLock { suspended = true }
        removeTap()
    }

    /// Ends the reset-only guard and lets the preference syncs decide
    /// whether the tap comes back. MUST run on the main thread.
    func resume() {
        precondition(Thread.isMainThread)
        tapLock.withLock { suspended = false }
        sync()
    }

    // MARK: - Tap lifecycle

    private func installTap() {
        let newThread = tapLock.withLock { () -> Thread? in
            if self.thread != nil {
                if shouldStopThread { pendingRestart = true }
                return nil
            }
            shouldStopThread = false
            pendingRestart = false
            let thread = Thread { [weak self] in self?.runTap() }
            thread.name = "Vorssaint Function Keys"
            thread.qualityOfService = .userInteractive
            self.thread = thread
            return thread
        }
        newThread?.start()
    }

    private func removeTap() {
        let snapshot = tapLock.withLock { () -> (runLoop: CFRunLoop?, tap: CFMachPort?,
                                                 threadExists: Bool) in
            shouldStopThread = true
            pendingRestart = false
            return (runLoop, tap, thread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            tapLock.withLock {
                shouldStopThread = false
                thread = nil
            }
        }
    }

    private func runTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            tapLock.withLock { self.runLoop = runLoop }
            let stopBeforeCreating = tapLock.withLock { shouldStopThread }
            guard !stopBeforeCreating else {
                if clearTapThread() { installTap() }
                return
            }
            let systemDefined = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.keyUp.rawValue)
                | CGEventMask(1 << systemDefined.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let tap = Unmanaged<FunctionKeyTap>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return tap.route(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearTapThread()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            tapLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            if tapLock.withLock({ shouldStopThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearTapThread() { installTap() }
        }
    }

    private func clearTapThread() -> Bool {
        tapLock.withLock {
            let restart = pendingRestart
            tap = nil
            runLoop = nil
            thread = nil
            shouldStopThread = false
            pendingRestart = false
            return restart
        }
    }

    // MARK: - Dispatch (tap thread)

    /// Runs on the tap thread. The window server holds every keystroke
    /// until this returns, so the listeners are chained without sorting,
    /// without allocation and without touching the main thread; each
    /// listener owns its thread safety.
    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let shouldSync = tapLock.withLock { () -> Bool in
                guard SessionActivity.shared.isActive, AXIsProcessTrusted(),
                      !suspended, !shouldStopThread, let tap else { return true }
                // Keep the lock through the enable so a main-thread suspend
                // cannot disable the tap and then lose a race to re-enable it.
                CGEvent.tapEnable(tap: tap, enable: true)
                return false
            }
            if shouldSync {
                DispatchQueue.main.async { [weak self] in self?.sync() }
            }
            return Unmanaged.passUnretained(event)
        }
        let chain = tapLock.withLock { listeners }
        var routed: Unmanaged<CGEvent>? = Unmanaged.passUnretained(event)
        for listener in chain {
            guard let current = routed else { return nil }
            routed = listener.route(type, current.takeUnretainedValue())
        }
        return routed
    }
}
