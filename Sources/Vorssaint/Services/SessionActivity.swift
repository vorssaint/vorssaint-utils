// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Whether this login session is the one on screen, for the services that own
/// an event tap.
///
/// Fast user switching leaves this process running in a session that is no
/// longer front-most, and an event tap created there keeps its place in the
/// chain: the window server still routes events through a process that cannot
/// answer, waits out the tap timeout on every one, and the account actually in
/// use gets the stall (issue #1075). The tap goes back on the way out and is
/// rebuilt from the preferences on the way in, which is also why the timeout
/// re-arm has to ask first — re-enabling a tap that was handed back for this
/// reason puts the stall straight back.
final class SessionActivity {
    static let shared = SessionActivity()

    /// True while this session is the one on screen. Written on the main
    /// thread and read from the tap callbacks the pointer thread serves, so
    /// it answers under `lock`.
    var isActive: Bool { lock.withLock { active } }

    private let lock = NSLock()
    private var active = false

    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var handlers: [(Bool) -> Void] = []

    /// Registration and the initial read both happen before any main-queue
    /// delivery can run, so there is no window in which a change is missed.
    /// macOS tells a process launched into a switched-away session before
    /// `didFinishLaunching`, which is before the services that own a tap are
    /// built, so the state is read here rather than assumed.
    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         initialIsActive: () -> Bool = {
             SessionActivitySupport.isOnConsole(CGSessionCopyCurrentDictionary() as? [String: Any])
         }) {
        self.center = center
        observers = [
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.update(isActive: false)
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.update(isActive: true)
            },
        ]
        active = initialIsActive()
    }

    deinit {
        for observer in observers { center.removeObserver(observer) }
    }

    /// Runs `handler` on every change, so a service can hand its tap back and
    /// build it again. Never called for a change that did not happen.
    func onChange(_ handler: @escaping (Bool) -> Void) {
        handlers.append(handler)
    }

    /// The handlers hand taps back and build them again, so they run with the
    /// lock released.
    private func update(isActive: Bool) {
        let changed = lock.withLock { () -> Bool in
            guard isActive != active else { return false }
            active = isActive
            return true
        }
        guard changed else { return }
        for handler in handlers { handler(isActive) }
    }
}
