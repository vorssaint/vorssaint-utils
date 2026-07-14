// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Keeps a most-recently-used order of applications by watching activation
/// notifications. The switcher orders its windows by this, so a quick
/// ⌘Tab→release always lands on the previous app, and tapping again returns —
/// the deterministic toggle the live window-server z-order can't guarantee
/// (its order lags a freshly activated window by a frame or two).
final class AppActivationTracker {
    static let shared = AppActivationTracker()

    private(set) var mru: [pid_t] = []
    private var started = false

    private init() {}

    /// The MRU feeds the switcher and Window Layout's "every app" actions;
    /// with both features off in the hub, the observers have no consumer.
    func syncWithFeatures() {
        if AppFeature.switcher.isAvailable || AppFeature.windowLayout.isAvailable {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        if let front = NSWorkspace.shared.frontmostApplication {
            record(front.processIdentifier)
        }
    }

    func stop() {
        guard started else { return }
        started = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        mru.removeAll()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// MRU rank of an app; unseen apps sort after every known one.
    func rank(of pid: pid_t) -> Int {
        mru.firstIndex(of: pid) ?? Int.max
    }

    /// The app the user is currently in (front of the MRU).
    var frontmostPid: pid_t? { mru.first }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        record(app.processIdentifier)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        mru.removeAll { $0 == app.processIdentifier }
    }

    private func record(_ pid: pid_t) {
        mru.removeAll { $0 == pid }
        mru.insert(pid, at: 0)
    }
}
