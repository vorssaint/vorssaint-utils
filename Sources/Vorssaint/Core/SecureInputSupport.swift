// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Who, if anyone, holds macOS Secure Event Input. While it is on the system
/// suppresses synthetic keystrokes, so snippets stop expanding and the
/// Command Bar's typing actions stop working. Only the holder can release it,
/// which is why naming it is the whole point.
///
/// Pure by design: the test harness compiles this file without IOKit, so
/// every rule here is pinned by `MetricsTests`. The reads themselves live in
/// `SecureInputMonitor`.
enum SecureInputSupport {
    enum Holder: Equatable {
        /// Not on. Snippets and Command Bar typing work normally.
        case off
        /// A running app holds it. Giving up its password field releases it,
        /// so the user has somewhere to go.
        case app(name: String, pid: pid_t)
        /// On, and nothing running can release it: the session records no
        /// holder, or the one it records has exited. Both need a new login
        /// session, so both read the same.
        case unattributed
        /// On, and the holder could not be identified: the read failed, or the
        /// recorded holder is alive but is not a regular app. Nothing to
        /// reveal, and a logout would not help.
        case unknown
    }

    /// What the session's registry entry reports. `unavailable` and
    /// `noHolder` stay apart so a read that stopped working cannot be
    /// reported as a session with no holder, whose advice is to log out.
    enum RegistryRead: Equatable {
        case holder(pid_t)
        case noHolder
        case unavailable
    }

    /// - Parameters:
    ///   - isEnabled: whether Secure Event Input is on.
    ///   - read: what the session records about the holder.
    ///   - runningApp: the regular app owning a PID and that app's own PID, or
    ///     nil when the PID belongs to no regular application.
    ///   - isProcessAlive: whether a PID still belongs to a running process.
    static func holder(isEnabled: Bool,
                       read: RegistryRead,
                       runningApp: (pid_t) -> (name: String, pid: pid_t)?,
                       isProcessAlive: (pid_t) -> Bool) -> Holder {
        // The flag is the authority on whether anything is blocked. The
        // recorded PID can outlive it, so consulting the read first would
        // warn about a condition that has already cleared.
        guard isEnabled else { return .off }
        switch read {
        case .unavailable:
            return .unknown
        case .noHolder:
            return .unattributed
        case .holder(let pid):
            guard pid > 0 else { return .unattributed }
            if let app = runningApp(pid), !app.name.isEmpty {
                return .app(name: app.name, pid: app.pid)
            }
            // A logout is the advice for a flag whose holder has gone. A live
            // holder can resolve to no name instead: a system password prompt
            // is not served by a regular app (`loginwindow` runs as an
            // accessory), and ending the session is the last thing to tell
            // the person looking at that prompt.
            return isProcessAlive(pid) ? .unknown : .unattributed
        }
    }

    /// Sampling runs only while a surface that displays the state is on
    /// screen, so the timer's lifetime follows the demand set's emptiness.
    static func shouldPoll(observingSurfaceCount: Int) -> Bool {
        observingSurfaceCount > 0
    }
}
