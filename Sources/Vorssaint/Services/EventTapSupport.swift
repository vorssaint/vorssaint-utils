// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What a tap owes the window server after reporting itself disabled.
enum EventTapRecovery: Equatable {
    /// The system switched it off and it is still wanted: switch it back on.
    case rearm
    /// It may no longer run: tear it down and let the owner sync from
    /// preferences.
    case tearDown
    /// Its owner already let go of it. Nothing to recover.
    case leaveStopped
}

/// One tap's lifetime and its re-arm policy, kept apart from the event chain so
/// the decisions can be tested without creating a tap.
///
/// Switching a tap off is reported to its callback exactly like a disable by
/// the system, and a tap served on another thread can be stopped while a
/// notice is on its way. The lifetime is what tells the two apart: once the
/// owner stopped, the notice is answered with `.leaveStopped` and the policy is
/// never asked again, so a stopped tap cannot be re-armed and a refused tap
/// does not schedule a second teardown on every notice.
final class EventTapLifetime {
    private let lock = NSLock()
    private var stopped = false
    private var policyAsks = 0
    /// Asked only while the tap is still owned. Answers whether the feature
    /// still wants the tap in the event chain.
    private let rearm: () -> Bool

    init(rearm: @escaping () -> Bool) {
        self.rearm = rearm
    }

    /// Whether this tap can still be re-armed.
    var isActive: Bool { lock.withLock { !stopped } }

    /// How many times the re-arm policy was consulted. A stopped lifetime
    /// never asks again.
    var policyConsultations: Int { lock.withLock { policyAsks } }

    /// The decision for a `tapDisabledByTimeout`/`tapDisabledByUserInput`
    /// notice. Must be called on the thread that serves the tap.
    func recovery() -> EventTapRecovery {
        lock.lock()
        let active = !stopped
        if active { policyAsks += 1 }
        lock.unlock()
        guard active else { return .leaveStopped }
        guard rearm() else {
            return stop() ? .tearDown : .leaveStopped
        }
        // A stop that landed while the policy was being asked wins.
        return isActive ? .rearm : .leaveStopped
    }

    /// Ends this tap's lifetime. Returns whether this call ended it.
    @discardableResult
    func stop() -> Bool {
        lock.withLock {
            guard !stopped else { return false }
            stopped = true
            return true
        }
    }
}
