// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Away lasts while any condition holds; it ends once, when the last clears.
struct AwayTracker {
    enum Condition: Hashable { case locked, sessionInactive, asleep, screensAsleep }

    private(set) var conditions: Set<Condition> = []
    private var start: Date?

    var isAway: Bool { !conditions.isEmpty }

    mutating func begin(_ c: Condition, now: Date) {
        if conditions.isEmpty { start = now }
        conditions.insert(c)
    }

    mutating func end(_ c: Condition, now: Date) -> TimeInterval? {
        guard conditions.remove(c) != nil, conditions.isEmpty else { return nil }
        return finish(now)
    }

    /// Recovers from a missed wake or unlock notification.
    mutating func watchdog(now: Date, screenLocked: Bool, idleSeconds: TimeInterval) -> TimeInterval? {
        guard isAway, !screenLocked, idleSeconds < BusyPolicy.idleThreshold else { return nil }
        conditions.removeAll()
        return finish(now)
    }

    private mutating func finish(_ now: Date) -> TimeInterval? {
        defer { start = nil }
        return start.map { max(0, now.timeIntervalSince($0)) }
    }
}

struct TickClock {
    private var last: Date?

    mutating func reset(now: Date) { last = now }

    /// A gap over twice the tick is an absence (dt 0); a backwards jump counts nothing.
    mutating func step(now: Date, interval: TimeInterval) -> (dt: TimeInterval, gap: TimeInterval?) {
        defer { last = now }
        guard let last else { return (0, nil) }
        let delta = now.timeIntervalSince(last)
        if delta < 0 { return (0, nil) }
        if delta > interval * 2 { return (0, delta) }
        return (delta, nil)
    }
}

/// Backstop for paths that hide a notch break without collapsing the island.
struct NotchBreakWatch {
    static let limit: TimeInterval = 10
    private var invisibleSince: Date?

    mutating func displaced(id: UUID, currentCaptureID: UUID?, visible: Bool, expanded: Bool, now: Date) -> Bool {
        if currentCaptureID != id { return true }
        guard expanded, !visible else { invisibleSince = nil; return false }
        let since = invisibleSince ?? now
        invisibleSince = since
        return now.timeIntervalSince(since) >= Self.limit
    }
}
