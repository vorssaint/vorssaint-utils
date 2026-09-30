// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Kept apart from FanControlSupport.swift, which the protected helper also
// compiles: resuming is the app's own business, and code the helper never
// runs must not change its binary and force every Mac to register it again.
extension FanControlConfiguration {
    /// The control kept for a restart or wake. Only a valid manual speed or
    /// curve qualifies: System control has nothing to bring back.
    static func encodeResume(_ configuration: FanControlConfiguration) -> String? {
        guard configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(configuration) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeResume(_ value: String) -> FanControlConfiguration? {
        guard let data = value.data(using: .utf8),
              let configuration = try? JSONDecoder().decode(FanControlConfiguration.self, from: data),
              configuration.mode != .system,
              FanControlPolicy.validConfiguration(configuration) else { return nil }
        return configuration
    }
}

/// How long a manual speed holds before the fans go back to the system. Kept
/// with the resume rules for the same reason: the helper never sees it, since
/// the app ends a timed speed through the ordinary return to System.
enum FanControlManualDuration {
    /// Minutes offered beside the manual speed, in the order of the Keep
    /// awake chips: timed choices first, then 0, which keeps the speed until
    /// the user changes it, as manual control always did.
    static let choices = [5, 10, 15, 30, 60, 0]
    static let untilChanged = 0

    /// A value restored from another build or edited by hand falls back to
    /// the untimed behavior rather than inventing a duration.
    static func validated(_ minutes: Int) -> Int {
        choices.contains(minutes) ? minutes : untilChanged
    }

    /// When a manual speed applied at `now` ends, or nil when it stays.
    static func end(minutes: Int, from now: Date) -> Date? {
        let minutes = validated(minutes)
        guard minutes > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// The wall clock keeps counting while the Mac sleeps and between
    /// launches, so an end that passed meanwhile has ended on wake or launch.
    /// An end further away than the longest choice can only mean the clock
    /// was moved back; it has ended too, so a timed speed never outlasts the
    /// duration the user picked.
    static func hasEnded(_ end: Date, now: Date) -> Bool {
        let longest = TimeInterval((choices.max() ?? 0) * 60)
        return now >= end || end.timeIntervalSince(now) > longest
    }

    /// The end to count down to: only while the helper confirms the manual
    /// speed it belongs to is running.
    static func runningEnd(_ end: Date?, snapshot: FanControlSnapshot) -> Date? {
        guard snapshot.isCooling, snapshot.configuration?.mode == .manual else { return nil }
        return end
    }
}
