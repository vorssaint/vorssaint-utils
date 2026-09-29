// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// The scheduler's real run bookkeeping feeds the Cleaner card's real last-run
/// line. Defaults, the cleaner and notifications are replaced; nothing is cleaned.
enum CleanerLastRunContract {
    final class Cleaner {
        static let shared = Cleaner()
        func reset() {}
    }
    final class Preferences {
        static let standard = Preferences()
        var values: [String: Any] = [:]
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }
    class SchedulerState {
        typealias JunkCleaner = Cleaner
        typealias UserDefaults = Preferences
        var runObserver: AnyCancellable?
        func notifyIfWanted(freed: Int64, failed: Int) {}
        func scheduleNext() {}
    }
    final class Localization {
        let s = Text()
        struct Text {
            let cleanerScheduleLastFormat = "Freed %@."
            let cleanerScheduleRanFormat = "Ran %@."
            let uninstallerSomeFailed = "Some failed."
        }
    }
    class CardState {
        let l10n = Localization()
        var lastAutoRun = 0.0
        var lastAutoFreed = 0
        var lastAutoFailed = 0
        static let nextRunFormatter = DateFormatter()
        static func byteString(_ bytes: Int64) -> String { "\(bytes) bytes" }
    }

    static func run(_ suite: TestSuite) {
        let scheduler = Scheduler()
        let card = Card()
        for (freed, failed, line) in [(Int64(0), 3, "Ran . Some failed."), (0, 0, "Ran ."),
                                      (5, 1, "Freed 5 bytes. Some failed."), (5, 0, "Freed 5 bytes.")] {
            scheduler.finishRun(freed: freed, failed: failed)
            let values = Preferences.standard.values
            card.lastAutoFreed = Int(values[DefaultsKey.cleanerLastAutoFreed] as? Int64 ?? -1)
            card.lastAutoFailed = values[DefaultsKey.cleanerLastAutoFailed] as? Int ?? -1
            suite.expect(card.lastRunLine == line,
                         "a scheduled run freeing \(freed) bytes and leaving \(failed) items reads \"\(card.lastRunLine)\"")
        }
    }
}
