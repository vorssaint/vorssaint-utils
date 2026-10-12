// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Active taps get a dedicated run loop. Slow UI/AX work on the main thread
/// must never make the window server wait before delivering ordinary input.
final class WindowInputTap {
    private let lock = NSLock()
    private var wanted = false, stopping = false
    private var thread: Thread?
    private var loop: CFRunLoop?
    private var port: CFMachPort?
    private let mask: CGEventMask
    private let handler: (CGEventType, CGEvent) -> Bool
    init(mask: CGEventMask, handler: @escaping (CGEventType, CGEvent) -> Bool) {
        self.mask = mask; self.handler = handler
    }
    var isRunning: Bool { lock.withLock { wanted && !stopping && port != nil } }
    func start() {
        let worker = lock.withLock { () -> Thread? in
            wanted = true
            guard thread == nil else { return nil }
            stopping = false
            let worker = Thread { [weak self] in self?.run() }
            worker.name = "com.vorssaint.window-input"; worker.qualityOfService = .userInteractive
            thread = worker
            return worker
        }
        worker?.start()
    }
    func stop() {
        lock.withLock {
            wanted = false; stopping = true
            if let port { CGEvent.tapEnable(tap: port, enable: false) }
            if let loop {
                CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
                CFRunLoopWakeUp(loop)
            }
        }
    }
    private func run() {
        guard lock.withLock({ wanted && !stopping }) else { finish(); return }
        let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<WindowInputTap>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    owner.lock.withLock {
                        if owner.wanted, !owner.stopping, SessionActivity.shared.isActive, let port = owner.port { CGEvent.tapEnable(tap: port, enable: true) }
                    }
                    return Unmanaged.passUnretained(event)
                }
                guard owner.isRunning, SessionActivity.shared.isActive else { return Unmanaged.passUnretained(event) }
                return owner.handler(type, event) ? Unmanaged.passUnretained(event) : nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap, let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            // Permission/runtime sync retries; no idle busy loop on denial.
            lock.withLock { wanted = false }
            finish(); return
        }
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        let accepted = lock.withLock { () -> Bool in
            guard wanted && !stopping else { return false }
            port = tap; loop = runLoop
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        if accepted { CFRunLoopRun() }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(tap)
        finish()
    }
    private func finish() {
        let restart = lock.withLock { () -> Bool in
            port = nil; loop = nil; thread = nil; stopping = false
            return wanted
        }
        if restart { start() }
    }
    deinit { stop() }
}
