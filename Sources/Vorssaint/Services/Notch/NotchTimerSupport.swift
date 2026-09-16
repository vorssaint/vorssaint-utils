// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchTimerMode: String, CaseIterable { case timer, pomodoro }
enum NotchTimerPhase: String { case timer, focus, shortBreak, longBreak }

enum NotchTimerRulerScale {
    static let spacing = 14.0

    static func moving(_ value: Double, by points: Double) -> Double {
        guard value.isFinite, points.isFinite else { return 1 }
        return min(180, max(1, value - points / spacing))
    }

    static func minute(_ value: Double) -> Int {
        Int(moving(value, by: 0).rounded())
    }

    static func offset(of minute: Int, selected: Int) -> Double {
        (Double(minute) - Double(selected)) * spacing
    }

    static func label(for minute: Int) -> String {
        minute >= 60 ? NotchTimerSupport.hoursText(hours: minute / 60, minutes: minute % 60) : String(minute)
    }
}

/// Preferences describe the next cycle; a running cycle owns an immutable copy.
struct NotchPomodoroConfiguration: Equatable {
    static let focusRange = 1...180
    static let breakRange = 1...60
    static let sessionRange = 1...24
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let longBreakInterval: Int
    let totalSessions: Int

    init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5, longBreakMinutes: Int = 15,
         longBreakInterval: Int = 4, totalSessions: Int = 4) {
        self.focusMinutes = min(Self.focusRange.upperBound, max(Self.focusRange.lowerBound, focusMinutes))
        self.shortBreakMinutes = min(Self.breakRange.upperBound, max(Self.breakRange.lowerBound, shortBreakMinutes))
        self.longBreakMinutes = min(Self.breakRange.upperBound, max(Self.breakRange.lowerBound, longBreakMinutes))
        self.longBreakInterval = min(Self.sessionRange.upperBound, max(Self.sessionRange.lowerBound, longBreakInterval))
        self.totalSessions = min(Self.sessionRange.upperBound, max(Self.sessionRange.lowerBound, totalSessions))
    }

    static func load(in defaults: UserDefaults = .standard) -> Self {
        Self(focusMinutes: defaults.object(forKey: DefaultsKey.notchPomodoroFocusMinutes) as? Int ?? 25,
             shortBreakMinutes: defaults.object(forKey: DefaultsKey.notchPomodoroShortBreakMinutes) as? Int ?? 5,
             longBreakMinutes: defaults.object(forKey: DefaultsKey.notchPomodoroLongBreakMinutes) as? Int ?? 15,
             longBreakInterval: defaults.object(forKey: DefaultsKey.notchPomodoroLongBreakInterval) as? Int ?? 4,
             totalSessions: defaults.object(forKey: DefaultsKey.notchPomodoroTotalSessions) as? Int ?? 4)
    }
}

/// The deadline uses an injected, continuous time coordinate. UI refreshes and
/// delayed callbacks never subtract ticks, so sleep and busy frames cannot drift.
struct NotchTimerSession: Equatable {
    private(set) var mode: NotchTimerMode = .timer
    private(set) var phase: NotchTimerPhase = .timer
    private(set) var duration: TimeInterval = 300
    private(set) var deadline: TimeInterval?
    private(set) var pausedRemaining: TimeInterval?
    private(set) var completed = false
    private(set) var completedFocuses = 0
    private(set) var configuration = NotchPomodoroConfiguration()

    var isRunning: Bool { deadline != nil }
    var isPaused: Bool { pausedRemaining != nil }
    var hasSession: Bool { isRunning || isPaused || completed }
    var cycleFinished: Bool { mode == .pomodoro && completed && completedFocuses >= configuration.totalSessions }
    var canStartNext: Bool { mode == .pomodoro && completed && !cycleFinished }
    var sessionNumber: Int {
        min(configuration.totalSessions, completedFocuses + (phase == .focus && !completed ? 1 : 0))
    }

    func remaining(at now: TimeInterval) -> TimeInterval {
        if let deadline { return max(0, deadline - now) }
        return pausedRemaining ?? (completed ? 0 : duration)
    }

    mutating func start(mode: NotchTimerMode, minutes: Int, now: TimeInterval,
                        configuration: NotchPomodoroConfiguration = NotchPomodoroConfiguration()) {
        guard !hasSession, now.isFinite else { return }
        self.mode = mode
        self.configuration = configuration
        phase = mode == .pomodoro ? .focus : .timer
        duration = Double(mode == .pomodoro ? configuration.focusMinutes : min(180, max(1, minutes))) * 60
        completedFocuses = 0
        deadline = now + duration
    }

    @discardableResult mutating func finishIfDue(at now: TimeInterval) -> Bool {
        guard let deadline, now.isFinite, now >= deadline else { return false }
        self.deadline = nil
        pausedRemaining = nil
        completed = true
        if phase == .focus { completedFocuses += 1 }
        return true
    }

    mutating func pause(at now: TimeInterval) {
        guard isRunning, now.isFinite else { return }
        if finishIfDue(at: now) { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }

    mutating func resume(at now: TimeInterval) {
        guard let remaining = pausedRemaining, now.isFinite else { return }
        pausedRemaining = nil
        deadline = now + remaining
    }

    var nextPhase: NotchTimerPhase {
        phase == .focus ? (completedFocuses.isMultiple(of: configuration.longBreakInterval) ? .longBreak : .shortBreak) : .focus
    }

    /// A new phase always starts by an explicit action. Returning from a long
    /// sleep cannot silently complete work/break cycles the user never took.
    mutating func startNext(at now: TimeInterval) {
        guard canStartNext, now.isFinite else { return }
        phase = nextPhase
        duration = Double(phase == .focus ? configuration.focusMinutes
            : phase == .longBreak ? configuration.longBreakMinutes : configuration.shortBreakMinutes) * 60
        completed = false
        deadline = now + duration
    }

    mutating func cancel() { self = Self() }
}

enum NotchTimerSupport {
    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchTimerSoundEnabled) as? Bool ?? true
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchTimer.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchTimerEnabled)
            && NotchSupport.modules(in: defaults).contains(.timer)
    }

    static func clockText(_ remaining: TimeInterval) -> String {
        let seconds = remaining.isFinite ? Int(ceil(min(180 * 60, max(0, remaining)))) : 0
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Hours read as "1h35", never "1:35", which beside the minute clock
    /// would pass for one minute and thirty five seconds.
    static func hoursText(hours: Int, minutes: Int) -> String {
        String(format: "%dh%02d", hours, minutes)
    }

    static func compactHoursText(_ remaining: TimeInterval) -> String {
        let seconds = remaining.isFinite ? Int(min(180 * 60, max(0, remaining))) : 0
        return hoursText(hours: seconds / 3600, minutes: seconds / 60 % 60)
    }

    static func compactText(_ remaining: TimeInterval, locale: Locale) -> String {
        let seconds = remaining.isFinite ? ceil(min(180 * 60, max(0, remaining))) : 0
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600
            ? [.hours, .minutes] : [seconds >= 60 ? .minutes : .seconds]
        return Duration.seconds(seconds).formatted(.units(
            allowed: units, width: .narrow,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }
}
