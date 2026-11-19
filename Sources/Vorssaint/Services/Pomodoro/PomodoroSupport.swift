// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure, stateless helpers for the Pomodoro timer service.
///
/// All logic here is deterministic and side-effect free, making it trivially
/// unit-testable without any dependency on `Timer`, `Date`, or UI layers.
public enum PomodoroSupport {

    // MARK: - Default Constants

    /// Default focus (work) duration in minutes.
    public static let defaultFocusMinutes: Int = 25

    /// Default short-break duration in minutes.
    public static let defaultShortBreakMinutes: Int = 5

    /// Default long-break duration in minutes.
    public static let defaultLongBreakMinutes: Int = 15

    /// Number of focus cycles before a long break is scheduled.
    public static let defaultLongBreakInterval: Int = 4

    // MARK: - Sanitization

    /// Returns `minutes` when it falls within `range`; otherwise returns `fallback`.
    ///
    /// - Parameters:
    ///   - minutes: The raw value to validate.
    ///   - fallback: The value to use when `minutes` is out of bounds.
    ///   - range: The inclusive range of acceptable values (default `1...120`).
    /// - Returns: A sanitized `Int` duration in minutes.
    public static func sanitizedDuration(
        _ minutes: Int,
        fallback: Int = defaultFocusMinutes,
        range: ClosedRange<Int> = 1...120
    ) -> Int {
        guard range.contains(minutes) else {
            return range.contains(fallback) ? fallback : range.lowerBound
        }
        return minutes
    }

    public static func sanitizedDuration(_ minutes: Double) -> Int {
        guard minutes.isFinite else {
            return minutes.sign == .minus ? 1 : 120
        }
        return sanitizedDuration(Int(minutes))
    }

    // MARK: - Phase Duration

    /// Resolves the `TimeInterval` (in seconds) for a given phase.
    public static func duration(
        for phase: PomodoroPhase,
        focusMinutes: Int = defaultFocusMinutes,
        shortBreakMinutes: Int = defaultShortBreakMinutes,
        longBreakMinutes: Int = defaultLongBreakMinutes
    ) -> TimeInterval {
        let minutes: Int
        switch phase {
        case .focus:
            minutes = sanitizedDuration(focusMinutes, fallback: defaultFocusMinutes, range: 1...120)
        case .shortBreak:
            minutes = sanitizedDuration(shortBreakMinutes, fallback: defaultShortBreakMinutes, range: 1...60)
        case .longBreak:
            minutes = sanitizedDuration(longBreakMinutes, fallback: defaultLongBreakMinutes, range: 1...90)
        }
        return TimeInterval(minutes * 60)
    }

    // MARK: - Phase Transition

    /// Computes the next phase and the updated completed-cycle count.
    ///
    /// Transition rules:
    /// - After `.focus` → increment `completedCycles`; if the new count is a
    ///   multiple of `longBreakInterval`, go to `.longBreak`, otherwise `.shortBreak`.
    /// - After `.shortBreak` or `.longBreak` → go to `.focus` (cycles unchanged).
    ///
    /// - Parameters:
    ///   - current: The phase that just finished.
    ///   - completedCycles: How many focus cycles have been completed so far.
    ///   - longBreakInterval: How many focus cycles trigger a long break.
    /// - Returns: A tuple of `(nextPhase, updatedCycles)`.
    public static func nextPhase(
        after current: PomodoroPhase,
        completedCycles: Int,
        longBreakInterval: Int
    ) -> (phase: PomodoroPhase, cycles: Int) {
        let safeInterval = max(1, longBreakInterval)

        switch current {
        case .focus:
            let newCycles = completedCycles + 1
            let phase: PomodoroPhase =
                (newCycles % safeInterval == 0) ? .longBreak : .shortBreak
            return (phase, newCycles)

        case .shortBreak, .longBreak:
            return (.focus, completedCycles)

        @unknown default:
            return (.focus, completedCycles)
        }
    }

    public static func nextPhase(from current: PomodoroPhase, focusCount: Int) -> PomodoroPhase {
        nextPhase(after: current, completedCycles: focusCount, longBreakInterval: defaultLongBreakInterval).phase
    }

    // MARK: - Formatting

    /// Formats a `TimeInterval` as `mm:ss`, guarding against non-finite values.
    ///
    /// - Parameter seconds: The remaining time in seconds.
    /// - Returns: A zero-padded `mm:ss` string. Returns `"00:00"` for NaN,
    ///   negative, or infinite inputs.
    public static func formattedTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "00:00"
        }

        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60

        return String(format: "%02d:%02d", minutes, secs)
    }

    // MARK: - Progress

    /// Computes elapsed progress as a fraction between `0.0` and `1.0`.
    ///
    /// - Parameters:
    ///   - remaining: Seconds remaining in the current phase.
    ///   - total: Total duration of the current phase in seconds.
    /// - Returns: A `Double` in `[0.0, 1.0]`. Returns `0.0` when `total <= 0`
    ///   or when either argument is non-finite.
    public static func progress(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total.isFinite, remaining.isFinite, total > 0 else {
            return 0.0
        }

        let fraction = (total - remaining) / total
        return min(max(fraction, 0.0), 1.0)
    }

    // MARK: - Menu Bar Title

    /// Builds the string displayed in the macOS menu bar for the current state.
    ///
    /// - Parameters:
    ///   - phase: The active `PomodoroPhase`.
    ///   - remaining: Seconds remaining in the current phase.
    ///   - isRunningOrPaused: `true` when the timer is active (running or paused);
    ///     `false` when idle / stopped.
    /// - Returns: A compact title such as `"🍅 24:59"` or `"☕ 04:59"`.
    public static func menuBarTitle(
        state: PomodoroState,
        phase: PomodoroPhase,
        remaining: TimeInterval
    ) -> String {
        guard state == .running || state == .paused else { return "" }
        return "\(phase.emoji) \(formattedTime(remaining))"
    }

    public static func menuBarTitle(
        phase: PomodoroPhase,
        remaining: TimeInterval,
        isRunningOrPaused: Bool
    ) -> String {
        guard isRunningOrPaused else { return "" }
        return "\(phase.emoji) \(formattedTime(remaining))"
    }
}
