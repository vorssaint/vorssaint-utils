// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CleaningModeTimerSupport {
    /// Seconds; zero keeps the existing manual unlock behavior.
    static var durations: [Int] { DurationPicker.choices.map { $0 * 60 } }

    static func sanitizedDuration(_ seconds: Int) -> Int {
        durations.contains(seconds) ? seconds : 0
    }

    static func title(seconds: Int, language: AppLanguage) -> String {
        DurationPicker.shortTitle(for: sanitizedDuration(seconds) / 60,
                                  Strings.localized(language), language)
    }

    static func savedUntilTime(_ rawValue: Double) -> Date? {
        guard rawValue.isFinite, rawValue > 0,
              rawValue < Date.distantFuture.timeIntervalSinceReferenceDate else { return nil }
        return Date(timeIntervalSinceReferenceDate: rawValue)
    }

    static func deadline(seconds: Int, usesUntil: Bool, savedUntilTime: Double, now: Date) -> Date? {
        if usesUntil {
            guard let picked = self.savedUntilTime(savedUntilTime) else { return nil }
            return KeepAwakeAutomationSupport.resolvedUntilDate(picked: picked, now: now)
        }
        let duration = sanitizedDuration(seconds)
        return duration > 0 ? now.addingTimeInterval(TimeInterval(duration)) : nil
    }
}
