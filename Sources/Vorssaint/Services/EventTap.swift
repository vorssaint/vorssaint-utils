// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// One event tap, created, served and handed back the same way everywhere.
///
/// Every tap here exists to filter one feature's events, and every one of them
/// is disabled by the window server on a timeout or a lock. Re-arming is the
/// part a feature forgets, and a forgotten re-arm silently kills it until the
/// next preference sync. This type makes the decision explicit once: the owner
/// supplies a mask, a handler and a `rearm` policy, and the tap answers every
/// disabling notice with that policy or with "my owner stopped me, leave it".
///
/// One instance is one tap lifetime. `stop()` ends it, and a stopped tap
/// refuses to be installed or re-armed again; an owner that wants the feature
/// back makes a new instance from the same preferences.
///
/// Main thread only: the tap is served by the main run loop and the handler
/// runs there. Taps that must not wait for the UI are served by their own
/// thread and are not migrated to this type yet.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    private let location: CGEventTapLocation
    private let place: CGEventTapPlacement
    private let options: CGEventTapOptions
    private let mask: CGEventMask
    private let handler: Handler
    private let lifetime: EventTapLifetime
    /// Called on the main thread after a disabling notice tore this tap down.
    private let onRearmRefused: (() -> Void)?
    private let lock = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    /// `rearm` is asked on every disabling notice while the tap is owned. It
    /// has to be cheap and thread-safe for the thread serving the tap.
    init(location: CGEventTapLocation = .cgSessionEventTap,
         place: CGEventTapPlacement = .headInsertEventTap,
         options: CGEventTapOptions = .defaultTap,
         mask: CGEventMask,
         onRearmRefused: (() -> Void)? = nil,
         handler: @escaping Handler,
         rearm: @escaping () -> Bool) {
        self.location = location
        self.place = place
        self.options = options
        self.mask = mask
        self.onRearmRefused = onRearmRefused
        self.handler = handler
        lifetime = EventTapLifetime(rearm: rearm)
    }

    /// Creates the tap and serves it on the main run loop. Main thread only.
    /// A lifetime that already ended refuses to install.
    @discardableResult
    func install() -> Bool {
        guard lifetime.isActive else { return false }
        guard lock.withLock({ port }) == nil else { return true }
        guard let created = CGEvent.tapCreate(
            tap: location,
            place: place,
            options: options,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
                return tap.receive(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let createdSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        lock.withLock {
            port = created
            source = createdSource
        }
        if let createdSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), createdSource, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    /// Switches the tap off and hands its port back. The lifetime ends before
    /// the switch-off, so the notice that switch-off produces is not mistaken
    /// for one more reason to re-arm. Safe to call twice.
    func stop() {
        let (port, source) = lock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (self.port, self.source)
            self.port = nil
            self.source = nil
            return current
        }
        guard lifetime.stop() || port != nil else { return }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let port {
            CFMachPortInvalidate(port)
        }
    }

    /// Whether this tap is in the event chain.
    var isInstalled: Bool { lock.withLock { port != nil } }

    /// Runs on the thread serving the tap.
    private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else {
            return handler(type, event)
        }
        switch lifetime.recovery() {
        case .rearm:
            if let port = lock.withLock({ self.port }) {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        case .tearDown:
            // Invalidating the port from its own callback stack is unsafe;
            // finish this callback fail-open, then let the owner tear down.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                stop()
                onRearmRefused?()
            }
        case .leaveStopped:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
