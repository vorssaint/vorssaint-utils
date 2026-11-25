// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import AppKit
import CoreGraphics

/// Hears the Mac lock, unlock, sleep and wake and reports each as it happens.
///
/// None of these notifications is trustworthy by itself: any process of the
/// same user can post a distributed notification, and this one can be suspended
/// before it receives one. They only say when to look; `isScreenActuallyLocked`
/// is what decides.
final class FaceUnlockLockMonitor {
    /// Called on the main thread.
    var onEvent: ((FaceUnlockLockEvent) -> Void)?

    /// True from the moment the Mac starts sleeping until it next wakes. A lock
    /// is announced a moment before the system finishes suspending, so a scan
    /// started then would be cut off; the wake that follows starts it instead.
    private(set) var isSleeping = false

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        guard distributedObservers.isEmpty else { return }
        let distributed = DistributedNotificationCenter.default()
        distributedObservers = [
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                    object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?(.locked)
            },
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                    object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?(.unlocked)
            },
            // A key press that dismisses the screen saver cannot be observed on
            // the lock screen, where Secure Event Input hides the keyboard, so
            // the saver stopping stands in for it.
            distributed.addObserver(forName: Notification.Name("com.apple.screensaver.didstop"),
                                    object: nil, queue: .main) { [weak self] _ in
                self?.onEvent?(.wake)
            },
        ]
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.isSleeping = true
                self?.onEvent?(.willSleep)
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.isSleeping = false
                self?.onEvent?(.wake)
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.isSleeping = false
                self?.onEvent?(.wake)
            },
        ]
    }

    func stop() {
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributed.removeObserver)
        distributedObservers = []
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers = []
        isSleeping = false
    }

    deinit { stop() }

    /// The session server's own answer, not a notification anyone can forge.
    /// Reads as unlocked when the server cannot be asked, which only ever
    /// withholds an unlock.
    static func isScreenActuallyLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
