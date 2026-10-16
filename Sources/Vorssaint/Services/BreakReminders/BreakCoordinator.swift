// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Owns both schedules, coalesces them, and drives one prompt at a time
/// through its delivery chain.
struct BreakCoordinator {
    enum Output: Equatable {
        case present(BreakPrompt, via: DeliveryStyle)
        case dismiss(UUID, via: DeliveryStyle)
    }

    private struct Live {
        var prompt: BreakPrompt
        var chain: [DeliveryStyle]
        var via: DeliveryStyle
        var escalating: Bool
        var escalateAt: Date?
    }

    static let finalTimeout: TimeInterval = 600
    static let overlayGrace: TimeInterval = 60
    static let nearDue: TimeInterval = 60

    private(set) var schedules: [BreakKind: BreakSchedule] = [.eyes: BreakSchedule(), .movement: BreakSchedule()]
    private(set) var rotation: ActivityRotation
    private var live: Live?
    private var stopped = false

    init(rotation: ActivityRotation) { self.rotation = rotation }

    var livePromptID: UUID? { live?.prompt.id }

    var needsBusySignals: Bool {
        schedules.values.contains {
            switch $0.state {
            case .due, .deferred, .prompting: return true
            case .counting, .snoozed: return false
            }
        }
    }

    // MARK: Tick

    mutating func tick(now: Date, dt: TimeInterval, verdict: BusyVerdict, idleSeconds: TimeInterval,
                       awayFor: TimeInterval?, settings: BreakSettings, newID: () -> UUID) -> [Output] {
        guard !stopped else { return [] }
        var out: [Output] = []
        var events: [BreakKind: [BreakSchedule.Event]] = [:]
        // With the away reset off, absences never restart a countdown; an idle
        // verdict still defers a due prompt until the user is back.
        let resets = settings.holdOffs.resetWhenAway
        for kind in [BreakKind.movement, .eyes] {
            events[kind] = schedules[kind]!.tick(dt: dt, verdict: verdict, idleSeconds: resets ? idleSeconds : 0,
                                                 awayFor: resets ? awayFor : nil,
                                                 settings: settings[kind], now: now, newID: newID)
        }
        for kind in [BreakKind.movement, .eyes] {
            for event in events[kind] ?? [] { if case let .ended(id, advance) = event {
                out += end(id: id, kind: kind, advance: advance, settings: settings)
            } }
        }

        let movementPrompted = events[.movement]!.contains { if case .prompt = $0 { return true }; return false }
        if movementPrompted {
            out += resetEyes(settings: settings)
            events[.eyes] = []
        } else if eyesWouldPrompt(events[.eyes]!), movementBlocksEyes(settings: settings) {
            _ = schedules[.eyes]!.reset()
            events[.eyes] = []
        }

        for kind in [BreakKind.movement, .eyes] {
            for event in events[kind] ?? [] { if case let .prompt(id) = event {
                out += start(id: id, kind: kind, settings: settings)
            } }
        }

        if var current = live, let at = current.escalateAt, now >= at {
            out.append(.dismiss(current.prompt.id, via: current.via))
            current.via = .overlay
            current.escalateAt = nil
            current.chain = []
            live = current
            out.append(.present(current.prompt, via: .overlay))
        }
        return out
    }

    // MARK: Sink callbacks

    mutating func presented(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) {
        guard var current = live, current.prompt.id == id, current.via == via else { return }
        let kind = current.prompt.kind
        let firstStage = current.escalating && via != .overlay
        let deadline: Date?
        if via == .overlay {
            deadline = now.addingTimeInterval(TimeInterval(current.prompt.seconds) + Self.overlayGrace)
        } else if firstStage {
            deadline = nil
            current.escalateAt = now.addingTimeInterval(settings.escalateAfter)
        } else {
            deadline = now.addingTimeInterval(Self.finalTimeout)
        }
        live = current
        schedules[kind]!.presented(id: id, deadline: deadline)
    }

    mutating func deliveryFailed(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) -> [Output] {
        guard !stopped, var current = live, current.prompt.id == id, current.via == via else { return [] }
        guard !current.chain.isEmpty else {
            live = nil
            _ = schedules[current.prompt.kind]!.reset()
            return []
        }
        current.via = current.chain.removeFirst()
        current.escalateAt = nil
        live = current
        return [.present(current.prompt, via: current.via)]
    }

    mutating func displaced(id: UUID, via: DeliveryStyle, now: Date, settings: BreakSettings) -> [Output] {
        guard !stopped, var current = live, current.prompt.id == id, current.via == via else { return [] }
        if current.escalating && via != .overlay {
            current.chain = []
            current.via = .overlay
            current.escalateAt = nil
            live = current
            return [.present(current.prompt, via: .overlay)]
        }
        return deliveryFailed(id: id, via: via, now: now, settings: settings)
    }

    mutating func respond(id: UUID, action: BreakAction, now: Date, settings: BreakSettings) -> [Output] {
        guard !stopped, let current = live, current.prompt.id == id else { return [] }
        let kind = current.prompt.kind
        var out: [Output] = []
        for event in schedules[kind]!.respond(id: id, action: action, now: now) {
            if case let .ended(endedID, advance) = event {
                out += end(id: endedID, kind: kind, advance: advance, settings: settings)
            }
        }
        return out
    }

    mutating func settingsChanged(from old: BreakSettings, to new: BreakSettings) -> [Output] {
        guard !stopped, var current = live else { return [] }
        let kind = current.prompt.kind
        guard old[kind].style != new[kind].style, new[kind].enabled else { return [] }
        let previous = current.via
        let chain = Self.chain(for: new[kind].style)
        current.via = chain.first!
        current.chain = Array(chain.dropFirst())
        current.escalating = new[kind].style == .escalating
        current.escalateAt = nil
        live = current
        return [.dismiss(current.prompt.id, via: previous), .present(current.prompt, via: current.via)]
    }

    mutating func stop() -> [Output] {
        stopped = true
        defer { live = nil }
        guard let current = live else { return [] }
        _ = schedules[current.prompt.kind]!.reset()
        return [.dismiss(current.prompt.id, via: current.via)]
    }

    /// The surface went away with the session: reset with no fallback and no advance.
    mutating func stopPromptQuietly(id: UUID) -> [Output] {
        guard let current = live, current.prompt.id == id else { return [] }
        live = nil
        _ = schedules[current.prompt.kind]!.reset()
        return [.dismiss(id, via: current.via)]
    }

    // MARK: Helpers

    static func chain(for style: DeliveryStyle) -> [DeliveryStyle] {
        let order: [DeliveryStyle] = [.notch, .notification, .overlay]
        if style == .escalating { return order }
        return [style] + order.filter { $0 != style }
    }

    private mutating func start(id: UUID, kind: BreakKind, settings: BreakSettings) -> [Output] {
        let k = settings[kind]
        let activity = rotation.current(kind, in: k.activities)
        let prompt = BreakPrompt(id: id, kind: kind, activity: activity,
                                 seconds: activity?.seconds ?? Int(k.breakLength))
        let chain = Self.chain(for: k.style)
        live = Live(prompt: prompt, chain: Array(chain.dropFirst()), via: chain[0],
                    escalating: k.style == .escalating, escalateAt: nil)
        return [.present(prompt, via: chain[0])]
    }

    private mutating func end(id: UUID, kind: BreakKind, advance: Bool, settings: BreakSettings) -> [Output] {
        if advance { rotation.advance(kind, count: settings[kind].activities.count) }
        guard let current = live, current.prompt.id == id else { return [] }
        live = nil
        return [.dismiss(id, via: current.via)]
    }

    private mutating func resetEyes(settings: BreakSettings) -> [Output] {
        let near: Bool
        switch schedules[.eyes]!.state {
        case let .counting(e): near = e >= settings.eyes.interval - Self.nearDue
        case .due, .deferred, .snoozed, .prompting: near = true
        }
        guard near else { return [] }
        var out: [Output] = []
        for event in schedules[.eyes]!.reset() {
            if case let .ended(id, _) = event { out += end(id: id, kind: .eyes, advance: false, settings: settings) }
        }
        return out
    }

    private func eyesWouldPrompt(_ events: [BreakSchedule.Event]) -> Bool {
        events.contains { if case .prompt = $0 { return true }; return false }
    }

    private func movementBlocksEyes(settings: BreakSettings) -> Bool {
        guard settings.movement.enabled else { return false }
        switch schedules[.movement]!.state {
        case .due, .deferred, .prompting, .snoozed: return true
        case let .counting(e): return e >= settings.movement.interval - Self.nearDue
        }
    }

    /// The live prompt with this id, if it is still the one on screen.
    func prompt(_ id: UUID) -> BreakPrompt? { live?.prompt.id == id ? live?.prompt : nil }

    // MARK: Test support (used only by Tests/BreakReminderTests.swift)

    mutating func forceState(_ kind: BreakKind, _ state: BreakSchedule.State) {
        schedules[kind] = BreakSchedule(state: state)
    }
}
