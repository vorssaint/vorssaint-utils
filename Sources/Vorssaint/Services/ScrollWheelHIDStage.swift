// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Watches the HID stage for the wheel taps that sit further down, so they can
/// leave remote scrolling alone (see `ScrollWheelHIDStageLedger`).
///
/// The tap only notes each wheel event and hands it on untouched. It is an
/// active tap rather than a listener because the window server waits for an
/// active tap before passing the event on: the note is always there by the
/// time the event reaches the annotated stage, which a listener, told
/// asynchronously, could not promise. It lives on the pointer thread with the
/// other taps in the path of every wheel event, and only while a wheel tap
/// wants it.
final class ScrollWheelHIDStage {
    static let shared = ScrollWheelHIDStage()

    enum Client: Hashable {
        case smoothScroll
        case wheelTap
    }

    /// Guards everything below; the callback runs on the pointer thread, the
    /// wheel taps ask from theirs and the main thread arms and tears down.
    private let lock = NSLock()
    private var ledger = ScrollWheelHIDStageLedger()
    private var clients = Set<Client>()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Main thread only, like `setWatching`.
    private var creationRetryUsed = false

    private init() {}

    /// Whether `event` came in at the HID stage. Answers yes while nothing
    /// is watching, so the wheel features never go dead with this tap.
    func passed(_ event: CGEvent) -> Bool {
        let timestamp = event.timestamp
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        return lock.withLock { ledger.passed(timestamp, sourceProcessID: sourceProcessID) }
    }

    /// Main thread. Each wheel tap asks for the watch while it runs; the tap
    /// goes back with the last one, and with them when the session switches
    /// away. A failed create gets one more try half a second later, as the
    /// wheel taps' own do, and again on the next request.
    func setWatching(_ wanted: Bool, for client: Client) {
        let (port, source) = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            if wanted {
                clients.insert(client)
            } else {
                clients.remove(client)
            }
            guard clients.isEmpty, tap != nil else { return (nil, nil) }
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            ledger.reset()
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            if let source {
                PointerTapRunLoop.remove(source, invalidating: port)
            }
            return
        }
        guard wanted, lock.withLock({ tap == nil }) else { return }
        guard let created = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let stage = Unmanaged<ScrollWheelHIDStage>.fromOpaque(userInfo).takeUnretainedValue()
                stage.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // Without the watch remote scroll counts as local, so a create
            // that failed during the session handoff gets another look once
            // the switch settles.
            guard !creationRetryUsed else { return }
            creationRetryUsed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let client = self.lock.withLock({ self.clients.first }) else { return }
                self.setWatching(true, for: client)
            }
            return
        }
        creationRetryUsed = false
        let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        lock.withLock {
            tap = created
            runLoopSource = createdSource
        }
        if let createdSource {
            PointerTapRunLoop.add(createdSource)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        // Nothing is noted before the tap is on, so until then every event
        // still counts as having come through.
        lock.withLock { ledger.isWatching = true }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // Re-armed like the wheel taps, except in a session that was switched
        // away from, where they are about to hand this tap back.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, let port = lock.withLock({ tap }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return
        }
        guard type == .scrollWheel else { return }
        let timestamp = event.timestamp
        lock.withLock { ledger.note(timestamp) }
    }
}
