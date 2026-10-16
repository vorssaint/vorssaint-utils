// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BusyPolicy {
    static let idleThreshold: TimeInterval = 60

    /// First match wins: off, idle, busy, active.
    static func verdict(_ s: BreakSignals, settings: BreakSettings, now: Date, calendar: Calendar) -> BusyVerdict {
        if let until = settings.pausedUntil, until > now { return .off }
        if !settings.hours.contains(now, calendar: calendar) { return .off }
        if s.idleSeconds >= idleThreshold { return .idle }
        let h = settings.holdOffs
        if (h.mic && s.micInUse) || (h.camera && s.cameraInUse) || (h.fullscreen && s.fullscreenFrontmost) {
            return .busy
        }
        return .active
    }

    /// Working start on the first calendar day after today whose bit is set;
    /// next local midnight when working hours are not in effect.
    static func pauseUntilTomorrow(now: Date, hours: WorkingHours, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: today)!
        guard hours.isEffective else { return midnight }
        for offset in 1...7 {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let weekday = calendar.component(.weekday, from: day)
            if hours.days & (1 << (weekday - 1)) != 0 {
                return calendar.date(bySettingHour: hours.startMinutes / 60, minute: hours.startMinutes % 60, second: 0, of: day)!
            }
        }
        return midnight
    }
}
