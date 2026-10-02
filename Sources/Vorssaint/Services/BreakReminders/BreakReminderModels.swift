// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BreakKind: String, CaseIterable, Codable { case eyes, movement }

enum DeliveryStyle: String, CaseIterable, Codable { case notch, notification, escalating, overlay }

struct BreakActivity: Codable, Equatable {
    var id: UUID
    var text: String
    var seconds: Int
    /// SF Symbol shown on the full-screen overlay; nil uses the kind's default.
    var symbol: String? = nil
}

/// `days` bit n = Calendar weekday n+1 (bit 0 = Sunday). Start inclusive, end exclusive.
struct WorkingHours: Equatable {
    var enabled: Bool
    var days: Int
    var startMinutes: Int
    var endMinutes: Int

    /// Degenerate hours (no day selected, or start >= end) behave as disabled.
    var isEffective: Bool { enabled && days & 0x7F != 0 && startMinutes < endMinutes }

    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard isEffective else { return true }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, days & (1 << (weekday - 1)) != 0 else { return false }
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= startMinutes && minute < endMinutes
    }
}

struct KindSettings: Equatable {
    var enabled: Bool
    var interval: TimeInterval
    var breakLength: TimeInterval
    var style: DeliveryStyle
    var activities: [BreakActivity]

    var resetThreshold: TimeInterval { max(breakLength, 120) }
}

/// Which signals hold a break off. All on by default.
struct HoldOffs: Equatable {
    var mic = true
    var camera = true
    var fullscreen = true
    /// Restart the countdown after an absence (idle, locked, asleep).
    var resetWhenAway = true
}

struct BreakSettings: Equatable {
    var eyes: KindSettings
    var movement: KindSettings
    var escalateAfter: TimeInterval
    var hours: WorkingHours
    var pausedUntil: Date?
    var holdOffs = HoldOffs()

    /// The tick only has work while a kind is enabled.
    var needsTick: Bool { eyes.enabled || movement.enabled }

    subscript(kind: BreakKind) -> KindSettings {
        get { kind == .eyes ? eyes : movement }
        set { if kind == .eyes { eyes = newValue } else { movement = newValue } }
    }
}

struct BreakSignals: Equatable {
    var micInUse = false
    var cameraInUse = false
    var fullscreenFrontmost = false
    var idleSeconds: TimeInterval = 0
}

enum BusyVerdict: Equatable { case off, idle, busy, active }

enum BreakAction: Equatable { case done, skip, snooze }

struct BreakPrompt: Equatable {
    let id: UUID
    let kind: BreakKind
    /// nil when the kind's list is empty; the sink shows the generic message.
    let activity: BreakActivity?
    /// The activity's own seconds, or the kind's break length.
    let seconds: Int
}

/// Each break plays its start sound once and its end sound once, whichever of
/// the countdown finishing or Done comes first; snooze or skip ends it silently.
struct BreakSoundState: Equatable {
    private(set) var started: UUID?
    private var ended: UUID?

    /// True when this prompt has not sounded its start yet.
    mutating func start(_ id: UUID) -> Bool {
        guard started != id else { return false }
        started = id
        ended = nil
        return true
    }

    /// True when this started prompt has not sounded its end yet.
    mutating func end(_ id: UUID) -> Bool {
        guard started == id, ended != id else { return false }
        ended = id
        return true
    }

    /// The break ended without completing; its end sound never plays.
    mutating func cancel(_ id: UUID) {
        if started == id { ended = id }
    }
}
