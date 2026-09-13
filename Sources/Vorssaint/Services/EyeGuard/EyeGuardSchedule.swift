// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Starting points for the work/break cycle. The named ones carry the timing
/// of the guidance they come from rather than a number picked here, so the
/// settings screen can attribute them and claim nothing on its own.
enum EyeGuardPreset: String, CaseIterable, Identifiable {
    /// Every 20 minutes, look away for 20 seconds. Published by the American
    /// Optometric Association and the American Academy of Ophthalmology.
    case twentyTwentyTwenty
    /// A short break every half hour, the cadence Stretchly ships as its long
    /// break.
    case balanced
    /// One proper break per hour of desk work.
    case longSession
    case custom

    var id: String { rawValue }

    /// Minutes of work and seconds of break, or nil for the custom pairing
    /// the user stores themselves.
    var timing: (workMinutes: Int, breakSeconds: Int)? {
        switch self {
        case .twentyTwentyTwenty: return (20, 20)
        case .balanced: return (30, 300)
        case .longSession: return (50, 600)
        case .custom: return nil
        }
    }

    static func sanitized(_ raw: String?) -> EyeGuardPreset {
        guard let raw, let preset = EyeGuardPreset(rawValue: raw) else { return .twentyTwentyTwenty }
        return preset
    }
}

/// Where the cycle stands right now. The service renders this and nothing else,
/// so every timing decision stays here where a test can reach it.
enum EyeGuardPhase: Equatable {
    /// Working, with nothing on screen.
    case working
    /// Working, with the break about to land. `secondsLeft` counts down to it.
    case warning(secondsLeft: Int)
    /// The break screen is up. `secondsLeft` counts down to its end.
    case onBreak(secondsLeft: Int)
}

enum EyeGuardSchedule {
    /// How long before the break the warning appears. Stretchly warns 10s
    /// before a short break and 30s before a long one; one lead is enough here
    /// and 10s is the short end, because the warning exists to let someone
    /// finish a sentence, not to be a second break.
    static let warningLead: TimeInterval = 10

    static let workMinutesRange = 1...180
    static let breakSecondsRange = 5...1800

    static func clampWorkMinutes(_ minutes: Int) -> Int {
        min(max(minutes, workMinutesRange.lowerBound), workMinutesRange.upperBound)
    }

    static func clampBreakSeconds(_ seconds: Int) -> Int {
        min(max(seconds, breakSecondsRange.lowerBound), breakSecondsRange.upperBound)
    }

    /// The timing actually in force: a preset's own numbers, or the stored
    /// custom pair clamped into range. A value already on disk from an earlier
    /// version is clamped the same way, so a stale or hand-edited number cannot
    /// produce a zero-length cycle that fires every tick.
    static func timing(preset: EyeGuardPreset,
                       customWorkMinutes: Int,
                       customBreakSeconds: Int) -> (work: TimeInterval, breakLength: TimeInterval) {
        let pair = preset.timing ?? (clampWorkMinutes(customWorkMinutes),
                                     clampBreakSeconds(customBreakSeconds))
        return (TimeInterval(clampWorkMinutes(pair.workMinutes) * 60),
                TimeInterval(clampBreakSeconds(pair.breakSeconds)))
    }

    /// Time away from the keyboard is already the break this feature exists to
    /// produce, so it restarts the cycle instead of blacking the screen at
    /// somebody who just sat back down.
    static func idleCountsAsBreak(idle: TimeInterval, breakLength: TimeInterval) -> Bool {
        idle >= breakLength
    }

    /// Where `elapsed` seconds into a cycle lands. A cycle shorter than the
    /// warning lead is warning the whole way through, having no working phase
    /// to speak of.
    static func phase(elapsed: TimeInterval,
                      work: TimeInterval,
                      breakLength: TimeInterval) -> EyeGuardPhase {
        guard work > 0, breakLength > 0 else { return .working }
        if elapsed >= work {
            let remaining = work + breakLength - elapsed
            guard remaining > 0 else { return .working }
            return .onBreak(secondsLeft: Int(remaining.rounded(.up)))
        }
        let warningStart = work - warningLead
        guard elapsed >= warningStart else { return .working }
        return .warning(secondsLeft: Int((work - elapsed).rounded(.up)))
    }

    /// Whether `elapsed` has run past the end of the cycle, so the service
    /// starts the next one. Kept beside `phase` because the two answer the same
    /// boundary and drifting apart would leave a break that never ends.
    static func cycleIsComplete(elapsed: TimeInterval,
                                work: TimeInterval,
                                breakLength: TimeInterval) -> Bool {
        elapsed >= work + breakLength
    }
}
