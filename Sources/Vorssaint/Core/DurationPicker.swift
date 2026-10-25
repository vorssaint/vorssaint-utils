// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Session durations shared by Keep Awake and Cleaning Mode.
enum DurationPicker {
    /// The offered durations in minutes; 0 keeps the session open until it
    /// is switched off.
    static let choices = [15, 30, 60, 120, 240, 480, 0]

    static func title(for minutes: Int, _ s: Strings) -> String {
        switch minutes {
        case 15: return s.minutes15
        case 30: return s.minutes30
        case 60: return s.hour1
        case 120: return s.hours2
        case 240: return s.hours4
        case 480: return s.hours8
        default: return s.indefinite
        }
    }

    /// Chip-sized label ("15m", "1h" in English), localized by Foundation.
    static func shortTitle(for minutes: Int, _ s: Strings, _ language: AppLanguage) -> String {
        guard minutes > 0 else { return "∞" }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: language.rawValue)
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: TimeInterval(minutes * 60)) ?? title(for: minutes, s)
    }
}
