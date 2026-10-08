// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// An event tap that only listens, on a thread of its own.
///
/// A listening tap cannot hold an event back or change it, so whatever the
/// handler does, input reaches apps exactly as before and never waits for
/// this process. The handler runs on the tap's thread and must stay short.
///
/// Lifecycle follows the input taps elsewhere in the app: a stop that races a
/// start is remembered and the newest request wins, and a tap macOS disables
/// for a slow answer is re-armed in place while it is still wanted.
final class ListenOnlyEventTap {
    typealias Handler = (CGEventType, CGEvent) -> Void

    private let name: String
    private let handler: Handler
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var shouldStop = false
    private var pendingStart: CGEventMask?
    private(set) var mask: CGEventMask = 0

    init(name: String, handler: @escaping Handler) {
        self.name = name
        self.handler = handler
    }

    var isRunning: Bool {
        lock.withLock { thread != nil && !shouldStop }
    }

    /// Starts listening for `mask`, restarting when the mask changed.
    func start(mask newMask: CGEventMask) {
        let toStart: Thread? = lock.withLock {
            if thread != nil {
                if shouldStop || mask != newMask {
                    // Let the running tap wind down, then come back with the
                    // new mask.
                    pendingStart = newMask
                    if !shouldStop { stopLocked() }
                }
                return nil
            }
            mask = newMask
            shouldStop = false
            pendingStart = nil
            let thread = Thread { [weak self] in self?.run() }
            thread.name = name
            thread.qualityOfService = .userInteractive
            self.thread = thread
            return thread
        }
        toStart?.start()
    }

    func stop() {
        lock.withLock {
            pendingStart = nil
            stopLocked()
        }
    }

    private func stopLocked() {
        shouldStop = true
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func run() {
        autoreleasepool {
            let currentRunLoop = CFRunLoopGetCurrent()
            let (stopEarly, eventMask) = lock.withLock { () -> (Bool, CGEventMask) in
                runLoop = currentRunLoop
                return (shouldStop, mask)
            }
            guard !stopEarly,
                  let newTap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .tailAppendEventTap,
                    options: .listenOnly,
                    eventsOfInterest: eventMask,
                    callback: { _, type, event, userInfo in
                        guard let userInfo else { return Unmanaged.passUnretained(event) }
                        let owner = Unmanaged<ListenOnlyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
                        owner.receive(type: type, event: event)
                        return Unmanaged.passUnretained(event)
                    },
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else {
                finish()
                return
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
            CFRunLoopAddSource(currentRunLoop, source, .commonModes)
            let stopNow = lock.withLock { () -> Bool in
                tap = newTap
                return shouldStop
            }
            CGEvent.tapEnable(tap: newTap, enable: !stopNow)
            if !stopNow { CFRunLoopRun() }
            CGEvent.tapEnable(tap: newTap, enable: false)
            CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
            CFMachPortInvalidate(newTap)
            finish()
        }
    }

    private func receive(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.withLock {
                if !shouldStop, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return
        }
        handler(type, event)
    }

    private func finish() {
        let restartMask: CGEventMask? = lock.withLock {
            let restart = pendingStart
            tap = nil
            runLoop = nil
            thread = nil
            shouldStop = false
            pendingStart = nil
            return restart
        }
        if let restartMask {
            start(mask: restartMask)
        }
    }

    static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { $0 | (CGEventMask(1) << $1.rawValue) }
    }
}
