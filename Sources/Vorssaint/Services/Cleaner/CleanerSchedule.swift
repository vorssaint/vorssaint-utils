// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// When the automatic cleanup runs. Pure calendar math, kept away from the
/// timer so the tests can pin every boundary.
enum CleanerSchedule {
    enum Frequency: String, CaseIterable, Identifiable {
        case off, daily, weekly

        var id: String { rawValue }

        static func sanitized(_ raw: String) -> Frequency {
            Frequency(rawValue: raw) ?? .off
        }
    }

    /// The next moment the cleanup should fire strictly after `date`.
    /// Weekly runs use `weekday` (1 = Sunday … 7 = Saturday, calendar
    /// convention); daily runs ignore it. Off never fires.
    static func nextFireDate(after date: Date,
                             frequency: Frequency,
                             hour: Int,
                             minute: Int,
                             weekday: Int,
                             calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        switch frequency {
        case .off:
            return nil
        case .daily:
            break
        case .weekly:
            components.weekday = min(max(weekday, 1), 7)
        }
        return calendar.nextDate(after: date, matching: components,
                                 matchingPolicy: .nextTime)
    }

    /// Twelve hour clock conversions for the schedule pickers, pinned by
    /// tests because midnight and noon trip everyone up.
    static func hour24(hour12: Int, isPM: Bool) -> Int {
        let clamped = min(max(hour12, 1), 12)
        return (clamped % 12) + (isPM ? 12 : 0)
    }

    static func hour12Components(fromHour24 hour: Int) -> (hour12: Int, isPM: Bool) {
        let clamped = min(max(hour, 0), 23)
        let hour12 = clamped % 12 == 0 ? 12 : clamped % 12
        return (hour12, clamped >= 12)
    }

    /// Whether a scheduled run was missed while the Mac was off or asleep:
    /// the fire that followed the last run is already in the past.
    static func missedRun(now: Date,
                          lastRun: Date?,
                          frequency: Frequency,
                          hour: Int,
                          minute: Int,
                          weekday: Int,
                          calendar: Calendar = .current) -> Bool {
        guard frequency != .off else { return false }
        // Never ran before: the schedule starts counting from now, without
        // a surprise catch up clean on the very first enable.
        guard let lastRun else { return false }
        guard let due = nextFireDate(after: lastRun, frequency: frequency,
                                     hour: hour, minute: minute,
                                     weekday: weekday, calendar: calendar) else { return false }
        return due <= now
    }
}
