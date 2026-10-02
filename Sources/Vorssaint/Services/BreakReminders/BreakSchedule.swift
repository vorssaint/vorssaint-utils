// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One kind's countdown. At most one transition per tick; the crossing tick
/// emits nothing, so the next tick decides on freshly sampled busy signals.
struct BreakSchedule {
    enum State: Equatable {
        case counting(TimeInterval)
        case due
        case deferred(TimeInterval)
        /// `seen` turns true when a sink actually showed it; `deadline` is
        /// the no-response timeout measured from that moment.
        case prompting(id: UUID, seen: Bool, deadline: Date?)
        case snoozed(until: Date)
    }

    enum Event: Equatable {
        case prompt(UUID)
        case ended(UUID, advance: Bool)
    }

    static let grace: TimeInterval = 30
    static let snoozeLength: TimeInterval = 300

    private(set) var state: State

    init(state: State = .counting(0)) { self.state = state }

    mutating func tick(dt: TimeInterval, verdict: BusyVerdict, idleSeconds: TimeInterval,
                       awayFor: TimeInterval?, settings: KindSettings, now: Date,
                       newID: () -> UUID) -> [Event] {
        let dt = max(0, dt)
        guard settings.enabled else { return reset() }

        let threshold = settings.resetThreshold
        if (awayFor ?? 0) >= threshold || idleSeconds >= threshold {
            if case let .prompting(id, seen, _) = state {
                state = .counting(0)
                return [.ended(id, advance: seen)]
            }
            state = .counting(0)
            return []
        }

        switch state {
        case let .counting(elapsed):
            if elapsed >= settings.interval { state = .due; return [] }
            let next = verdict == .off ? elapsed : elapsed + dt
            state = next >= settings.interval ? .due : .counting(next)
            return []
        case .due:
            switch verdict {
            case .active: return startPrompt(newID())
            case .busy, .idle: state = .deferred(0)
            case .off: break
            }
            return []
        case let .deferred(activeFor):
            guard verdict == .active else { state = .deferred(0); return [] }
            let next = activeFor + dt
            if next >= Self.grace { return startPrompt(newID()) }
            state = .deferred(next)
            return []
        case let .prompting(id, seen, deadline):
            switch verdict {
            case .busy:
                state = .deferred(0)
                return [.ended(id, advance: false)]
            case .off:
                state = .counting(0)
                return [.ended(id, advance: false)]
            case .active, .idle:
                if let deadline, now >= deadline {
                    state = .counting(0)
                    return [.ended(id, advance: seen)]
                }
                return []
            }
        case let .snoozed(until):
            if verdict == .off { state = .counting(0) }
            else if now >= until { state = .due }
            return []
        }
    }

    mutating func presented(id: UUID, deadline: Date?) {
        guard case let .prompting(current, _, _) = state, current == id else { return }
        state = .prompting(id: id, seen: true, deadline: deadline)
    }

    mutating func respond(id: UUID, action: BreakAction, now: Date) -> [Event] {
        guard case let .prompting(current, _, _) = state, current == id else { return [] }
        switch action {
        case .done, .skip:
            state = .counting(0)
            return [.ended(id, advance: true)]
        case .snooze:
            state = .snoozed(until: now.addingTimeInterval(Self.snoozeLength))
            return [.ended(id, advance: false)]
        }
    }

    mutating func reset() -> [Event] {
        defer { state = .counting(0) }
        if case let .prompting(id, _, _) = state { return [.ended(id, advance: false)] }
        return []
    }

    private mutating func startPrompt(_ id: UUID) -> [Event] {
        state = .prompting(id: id, seen: false, deadline: nil)
        return [.prompt(id)]
    }
}
