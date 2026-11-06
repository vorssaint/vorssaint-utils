// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Whether macOS Secure Event Input is on, and which app to point at. While
/// it is on the system suppresses synthetic keystrokes, so snippets stop
/// expanding and the Command Bar's typing actions stop working. Only the
/// process that turned it on can release it, and macOS never says which one
/// that is: the window server records the app that was active when it turned
/// on. That is usually the app with the password field, but a background
/// process can turn it on while any app is in front, so the app recorded is
/// offered as a lead, never as the holder.
///
/// Pure by design: the test harness compiles this file without IOKit, so
/// every rule here is pinned by `MetricsTests`. The reads themselves live in
/// `SecureInputMonitor`.
enum SecureInputSupport {
    enum Holder: Equatable {
        /// Not on. Snippets and Command Bar typing work normally.
        case off
        /// A running regular app was active when it turned on, so it may be
        /// holding it. If it is, giving up its password field releases it,
        /// so the user has somewhere to start.
        case app(name: String, pid: pid_t)
        /// On, and no running app can be pointed at: none is recorded, or the
        /// one recorded has quit. Whatever holds it is still running, since
        /// the window server drops a holder's request when it exits, but it
        /// cannot be named, so a new login session is the fallback.
        case unattributed
        /// On, and nothing should be pointed at: the read failed, or the app
        /// recorded is alive but is not a regular app, or is Vorssaint itself.
        /// Nothing to reveal, and a logout is not the advice.
        case unknown
    }

    /// What the session's registry entry reports: the app that was active
    /// when secure input turned on, not the process that turned it on.
    /// `unavailable` and `noHolder` stay apart so a read that stopped working
    /// cannot be reported as a session with nothing recorded, whose advice is
    /// to log out.
    enum RegistryRead: Equatable {
        case holder(pid_t)
        case noHolder
        case unavailable
    }

    /// - Parameters:
    ///   - isEnabled: whether Secure Event Input is on.
    ///   - read: the app the session recorded when secure input turned on.
    ///   - ownPid: this process, which is never named.
    ///   - runningApp: the regular app owning a PID and that app's own PID, or
    ///     nil when the PID belongs to no regular application.
    ///   - isProcessAlive: whether a PID still belongs to a running process.
    static func holder(isEnabled: Bool,
                       read: RegistryRead,
                       ownPid: pid_t,
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
                // Settings makes Vorssaint a regular, active app, and it never
                // turns secure input on, so finding it recorded only means
                // something in the background turned it on meanwhile.
                guard app.pid != ownPid else { return .unknown }
                return .app(name: app.name, pid: app.pid)
            }
            // A logout is the fallback once the app recorded has quit, since
            // nothing is left to point at. A live process can resolve to no
            // name instead: a system password prompt is not served by a
            // regular app (`loginwindow` runs as an accessory), and ending
            // the session is the last thing to tell the person looking at
            // that prompt.
            return isProcessAlive(pid) ? .unknown : .unattributed
        }
    }

    /// Sampling runs only while a surface that displays the state is on
    /// screen and the Settings window itself is open. Demand alone is not
    /// enough: a page's onAppear/onDisappear pair does not always run
    /// around the window closing and reopening, so the window's own state
    /// is a second, independent gate rather than something demand implies.
    static func shouldPoll(observingSurfaceCount: Int, windowIsOpen: Bool) -> Bool {
        observingSurfaceCount > 0 && windowIsOpen
    }
}
