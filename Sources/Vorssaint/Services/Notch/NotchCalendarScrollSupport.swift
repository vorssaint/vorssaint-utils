// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Release velocity and time-based friction for the month carousel. Finger
/// input remains direct; only the movement after release uses this model.
struct NotchCalendarMomentum {
    private var lastTimestamp: TimeInterval?
    private var lastMovement: TimeInterval?
    private var velocity = 0.0
    static let decayTime = 0.32

    mutating func record(delta: Double, timestamp: TimeInterval) {
        guard delta.isFinite, timestamp.isFinite else { self = Self(); return }
        let elapsed = lastTimestamp.map { timestamp - $0 } ?? 1 / 60
        lastTimestamp = timestamp
        guard delta != 0 else { return }
        guard elapsed >= 0 else { self = Self(); return }
        let instantaneous = delta / min(max(elapsed, 1 / 240), 1 / 30)
        if elapsed > 0.1 || velocity * instantaneous <= 0 {
            velocity = instantaneous
        } else {
            let weight = 1 - exp(-elapsed / 0.035)
            velocity += (instantaneous - velocity) * weight
        }
        lastMovement = timestamp
    }

    func released(at timestamp: TimeInterval, limit: Double) -> Double {
        guard let lastMovement, timestamp.isFinite, limit.isFinite, limit > 0 else { return 0 }
        let idle = timestamp - lastMovement
        guard idle >= 0, idle < 0.1 else { return 0 }
        let release = velocity * exp(-idle / 0.06)
        return min(max(release, -limit), limit)
    }

    static func step(velocity: Double, elapsed: TimeInterval) -> (distance: Double, velocity: Double) {
        guard velocity.isFinite, elapsed.isFinite, elapsed > 0 else { return (0, velocity.isFinite ? velocity : 0) }
        let decay = exp(-elapsed / decayTime)
        return (velocity * decayTime * (1 - decay), velocity * decay)
    }
}

/// Geometry of the rolling calendar document, measured in days or months.
struct NotchCalendarScrollSupport {
    static func rebase(position: Double, radius: Int) -> (shift: Int, remainder: Double) {
        guard position.isFinite, abs(position) < Double(Int.max), radius > 0 else { return (0, 0) }
        guard abs(position) > Double(radius) / 2 else { return (0, position) }
        let shift = Int(position.rounded(.towardZero))
        return (shift, position - Double(shift))
    }
}
