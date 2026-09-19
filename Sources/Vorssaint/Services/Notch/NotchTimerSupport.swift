// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum NotchTimerMode: String, CaseIterable { case timer, pomodoro, stopwatch }
enum NotchTimerPhase: String { case timer, focus, shortBreak, longBreak, stopwatch }

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

/// Every value accepted by the saved configuration remains selectable.
enum NotchPomodoroOption: CaseIterable, Identifiable {
    case focus, shortBreak, longBreak, longBreakInterval, totalSessions
    var id: Self { self }

    var range: ClosedRange<Int> {
        switch self {
        case .focus: return NotchPomodoroConfiguration.focusRange
        case .shortBreak, .longBreak: return NotchPomodoroConfiguration.breakRange
        case .longBreakInterval, .totalSessions: return NotchPomodoroConfiguration.sessionRange
        }
    }

    var isDuration: Bool {
        switch self {
        case .focus, .shortBreak, .longBreak: return true
        case .longBreakInterval, .totalSessions: return false
        }
    }
}

/// The anchor is an injected, continuous time coordinate: a countdown's
/// deadline, or the instant a stopwatch read zero. UI refreshes and delayed
/// callbacks never subtract ticks, so sleep and busy frames cannot drift.
struct NotchTimerSession: Equatable {
    private(set) var mode: NotchTimerMode = .timer
    private(set) var phase: NotchTimerPhase = .timer
    private(set) var duration: TimeInterval = 300
    private(set) var anchor: TimeInterval?
    private(set) var pausedReading: TimeInterval?
    private(set) var completed = false
    private(set) var completedFocuses = 0
    private(set) var configuration = NotchPomodoroConfiguration()

    var countsUp: Bool { mode == .stopwatch }
    var isRunning: Bool { anchor != nil }
    var isPaused: Bool { pausedReading != nil }
    var hasSession: Bool { isRunning || isPaused || completed }
    var deadline: TimeInterval? { countsUp ? nil : anchor }
    var cycleFinished: Bool { mode == .pomodoro && completed && completedFocuses >= configuration.totalSessions }
    var canStartNext: Bool { mode == .pomodoro && completed && !cycleFinished }
    var sessionNumber: Int {
        min(configuration.totalSessions, completedFocuses + (phase == .focus && !completed ? 1 : 0))
    }

    /// Seconds left in a countdown, or elapsed on a stopwatch.
    func reading(at now: TimeInterval) -> TimeInterval {
        if let anchor { return max(0, countsUp ? now - anchor : anchor - now) }
        return pausedReading ?? (completed || countsUp ? 0 : duration)
    }

    mutating func start(mode: NotchTimerMode, minutes: Int, now: TimeInterval,
                        configuration: NotchPomodoroConfiguration = NotchPomodoroConfiguration()) {
        guard !hasSession, now.isFinite else { return }
        self.mode = mode
        self.configuration = configuration
        completedFocuses = 0
        switch mode {
        case .timer:
            phase = .timer
            duration = Double(min(180, max(1, minutes))) * 60
            anchor = now + duration
        case .pomodoro:
            phase = .focus
            duration = Double(configuration.focusMinutes) * 60
            anchor = now + duration
        case .stopwatch:
            phase = .stopwatch
            duration = 0
            anchor = now
        }
    }

    @discardableResult mutating func finishIfDue(at now: TimeInterval) -> Bool {
        guard let deadline, now.isFinite, now >= deadline else { return false }
        anchor = nil
        pausedReading = nil
        completed = true
        if phase == .focus { completedFocuses += 1 }
        return true
    }

    mutating func pause(at now: TimeInterval) {
        guard isRunning, now.isFinite else { return }
        if finishIfDue(at: now) { return }
        pausedReading = reading(at: now)
        anchor = nil
    }

    mutating func resume(at now: TimeInterval) {
        guard let reading = pausedReading, now.isFinite else { return }
        pausedReading = nil
        anchor = countsUp ? now - reading : now + reading
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
        anchor = now + duration
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

    /// The modes read as three words in a row, the current one underlined,
    /// each as wide as its text, so the three fit the narrowest island in
    /// every language where equal segments would not.
    enum ModePicker {
        static let height: CGFloat = 24
        static let spacing: CGFloat = 14
        static let labelSize: CGFloat = 12
        static let labelPadding: CGFloat = 4
    }

    /// The start capsule beside the mode row; the test measures both against the
    /// width the wide layout starts at, in every language.
    enum StartButton {
        static let labelSize: CGFloat = 14
        static let padding: CGFloat = 18
    }

    static let timerLimit: TimeInterval = 180 * 60
    /// A stopwatch keeps counting; its clock saturates at the widest reading
    /// the surface fits, two hour digits.
    static let stopwatchLimit: TimeInterval = 100 * 3600 - 1

    static func savedMode(in defaults: UserDefaults = .standard) -> NotchTimerMode {
        NotchTimerMode(rawValue: defaults.string(forKey: DefaultsKey.notchTimerMode) ?? "") ?? .timer
    }

    private static func wholeSeconds(_ value: TimeInterval, limit: TimeInterval,
                                     rounded rule: FloatingPointRoundingRule) -> Int {
        value.isFinite ? Int(min(limit, max(0, value)).rounded(rule)) : 0
    }

    private static func clockText(seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    static func clockText(_ remaining: TimeInterval) -> String {
        clockText(seconds: wholeSeconds(remaining, limit: timerLimit, rounded: .up))
    }

    /// Elapsed time never rounds up: a stopwatch cannot show a second that
    /// has not passed yet.
    static func stopwatchText(_ elapsed: TimeInterval) -> String {
        clockText(seconds: wholeSeconds(elapsed, limit: stopwatchLimit, rounded: .down))
    }

    /// Hours read as "1h35", never "1:35", which beside the minute clock
    /// would pass for one minute and thirty five seconds.
    static func hoursText(hours: Int, minutes: Int) -> String {
        String(format: "%dh%02d", hours, minutes)
    }

    static func compactHoursText(_ remaining: TimeInterval) -> String {
        let seconds = wholeSeconds(remaining, limit: timerLimit, rounded: .down)
        return hoursText(hours: seconds / 3600, minutes: seconds / 60 % 60)
    }

    /// The compact strip keeps a stopwatch's seconds, the reading that shows
    /// it is alive, until hours take their place.
    static func compactStopwatchText(_ elapsed: TimeInterval) -> String {
        let seconds = wholeSeconds(elapsed, limit: stopwatchLimit, rounded: .down)
        return seconds >= 3600 ? hoursText(hours: seconds / 3600, minutes: seconds / 60 % 60) : clockText(seconds: seconds)
    }

    static func clockText(for session: NotchTimerSession, at now: TimeInterval) -> String {
        session.countsUp ? stopwatchText(session.reading(at: now)) : clockText(session.reading(at: now))
    }

    static func compactText(for session: NotchTimerSession, at now: TimeInterval, locale: Locale) -> String {
        let reading = session.reading(at: now)
        if session.countsUp { return compactStopwatchText(reading) }
        return reading >= 3600 ? compactHoursText(reading) : compactText(reading, locale: locale)
    }

    /// Seconds until the reading next crosses a whole second. A tick every
    /// second from there lands just after each change; ticks spaced from the
    /// display refresh instead drift across a boundary and skip a value.
    static func secondBoundaryOffset(for session: NotchTimerSession, at now: TimeInterval) -> TimeInterval {
        let reading = session.reading(at: now)
        guard reading.isFinite else { return 0 }
        let fraction = reading.truncatingRemainder(dividingBy: 1)
        let offset = session.countsUp ? 1 - fraction : fraction
        return offset > 0 ? offset : 1
    }

    /// Start of the periodic schedule that ticks the clock, relative to now.
    /// A timeline renders its first entry at once and wakes only at the next,
    /// so the schedule starts at the boundary already behind the reading: the
    /// entry that fires is the boundary ahead, never one skipped past.
    static func tickScheduleOffset(for session: NotchTimerSession, at now: TimeInterval) -> TimeInterval {
        secondBoundaryOffset(for: session, at: now) - 1
    }

    static func compactText(_ remaining: TimeInterval, locale: Locale) -> String {
        let seconds = remaining.isFinite ? ceil(min(timerLimit, max(0, remaining))) : 0
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds >= 3600
            ? [.hours, .minutes] : [seconds >= 60 ? .minutes : .seconds]
        return Duration.seconds(seconds).formatted(.units(
            allowed: units, width: .narrow,
            fractionalPart: .hide(rounded: .down)).locale(locale))
    }
}
