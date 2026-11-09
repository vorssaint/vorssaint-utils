// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

enum NotchTimerMode: String, CaseIterable { case timer, pomodoro, stopwatch }
enum NotchTimerPhase: String { case timer, focus, shortBreak, longBreak, stopwatch }

enum NotchTimerRulerScale {
    static let spacing = 14.0
    static let maximumAcceleration = 3.0
    static let speedForMaximumAcceleration = 900.0
    static let velocitySmoothingDuration = 0.08

    static func moving(_ value: Double, by points: Double) -> Double {
        guard value.isFinite, points.isFinite else { return 1 }
        return min(180, max(1, value - points / spacing))
    }

    static func acceleration(for pointsPerSecond: Double) -> Double {
        guard pointsPerSecond.isFinite else { return 1 }
        let progress = cubicBezierProgress(
            min(1, max(0, pointsPerSecond) / speedForMaximumAcceleration),
            control1: CGPoint(x: 0.35, y: 0),
            control2: CGPoint(x: 0.8, y: 1)
        )
        return 1 + (maximumAcceleration - 1) * progress
    }

    static func easedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        return cubicBezierProgress(
            min(1, max(0, progress)),
            control1: CGPoint(x: 0.25, y: 0.1),
            control2: CGPoint(x: 0.25, y: 1)
        )
    }

    private static func cubicBezierProgress(_ x: Double, control1: CGPoint, control2: CGPoint) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }

        func coordinate(_ t: Double, first: CGFloat, second: CGFloat) -> Double {
            let inverse = 1 - t
            return 3 * inverse * inverse * t * Double(first)
                + 3 * inverse * t * t * Double(second) + t * t * t
        }

        var lower = 0.0
        var upper = 1.0
        for _ in 0..<20 {
            let parameter = (lower + upper) / 2
            if coordinate(parameter, first: control1.x, second: control2.x) < x {
                lower = parameter
            } else {
                upper = parameter
            }
        }
        return coordinate((lower + upper) / 2, first: control1.y, second: control2.y)
    }

    static func minute(_ value: Double) -> Int {
        Int(moving(value, by: 0).rounded())
    }

    static func offset(of minute: Int, selected: Int) -> Double {
        offset(of: minute, selected: Double(selected))
    }

    static func offset(of minute: Int, selected: Double) -> Double {
        (Double(minute) - selected) * spacing
    }

    /// Keep the ruler filled near either end instead of centering a short
    /// duration over an empty half. The inset fits the hour labels as well.
    static func selectionX(selected: Int, width: Double) -> Double {
        selectionX(selected: Double(selected), width: width)
    }

    static func selectionX(selected: Double, width: Double) -> Double {
        guard width.isFinite, width > 0 else { return 0 }
        let inset = min(24, width / 2)
        let selected = selected.isFinite ? min(180, max(1, selected)) : 1
        let leading = (selected - 1) * spacing
        let trailing = (180 - selected) * spacing
        if leading + trailing <= width - 2 * inset {
            return (width - leading - trailing) / 2 + leading
        }
        return min(inset + leading, max(width / 2, width - inset - trailing))
    }

    static func label(for minute: Int) -> String {
        minute >= 60 ? NotchTimerSupport.hoursText(hours: minute / 60, minutes: minute % 60) : String(minute)
    }
}

enum NotchTimerRulerFeedback {
    static func pattern(distance: Double, speed: Double) -> NSHapticFeedbackManager.FeedbackPattern? {
        guard distance.isFinite, distance > 0 else { return nil }
        let easedDistance = distance * NotchTimerRulerScale.acceleration(for: speed)
        if easedDistance >= 2.5 { return .generic }
        if easedDistance >= 1 { return .levelChange }
        return .alignment
    }
}

/// Retains fractional movement and velocity across drag events so fast drags
/// accelerate smoothly while a reversal immediately responds in the new direction.
struct NotchTimerRulerDrag {
    private(set) var value: Double
    private var lastX: Double
    private var lastTimestamp: TimeInterval
    private var velocity: Double = 0
    var speed: Double { abs(velocity) }

    init(x: Double, value: Double, timestamp: TimeInterval) {
        lastX = x.isFinite ? x : 0
        self.value = NotchTimerRulerScale.moving(value, by: 0)
        lastTimestamp = timestamp.isFinite ? timestamp : 0
    }

    mutating func move(to x: Double, at timestamp: TimeInterval) -> Double {
        guard x.isFinite else { return value }
        let points = x - lastX
        let elapsed = timestamp - lastTimestamp
        if elapsed.isFinite, elapsed > 0 {
            if points == 0 {
                velocity *= exp(-elapsed / NotchTimerRulerScale.velocitySmoothingDuration)
            } else {
                let instantaneousVelocity = points / elapsed
                if velocity != 0, velocity.sign != instantaneousVelocity.sign {
                    velocity = 0
                }
                let response = 1 - exp(-elapsed / NotchTimerRulerScale.velocitySmoothingDuration)
                velocity += (instantaneousVelocity - velocity) * response
            }
        } else {
            velocity = 0
        }
        value = NotchTimerRulerScale.moving(
            value,
            by: points * NotchTimerRulerScale.acceleration(for: abs(velocity))
        )
        lastX = x
        if timestamp.isFinite { lastTimestamp = timestamp }
        return value
    }
}

struct NotchTimerRulerAnimation {
    let from: Double
    let to: Double
    let startTime: TimeInterval
    let duration: TimeInterval

    func value(at time: TimeInterval) -> Double {
        guard time.isFinite, startTime.isFinite, duration.isFinite, duration > 0 else { return to }
        if time <= startTime { return from }
        if isComplete(at: time) { return to }
        let progress = min(1, max(0, (time - startTime) / duration))
        return from + (to - from) * NotchTimerRulerScale.easedProgress(progress)
    }

    func isComplete(at time: TimeInterval) -> Bool {
        !time.isFinite || !startTime.isFinite || !duration.isFinite || duration <= 0
            || time >= startTime + duration
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
            duration = Double(NotchTimerSupport.timerMinutes(minutes)) * 60
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
    static func timerTileSymbol(for session: NotchTimerSession) -> String {
        guard session.hasSession else { return "timer" }
        if session.completed { return "checkmark" }
        if session.isPaused { return "pause.fill" }
        return session.countsUp ? "stopwatch" : "timer"
    }

    static func compactMarkSymbol(for session: NotchTimerSession) -> String {
        if session.completed { return "checkmark.circle" }
        if session.isPaused { return "pause.circle" }
        return session.countsUp ? "stopwatch" : "timer.circle"
    }

    static func compactMarkVariableValue(for session: NotchTimerSession, at now: TimeInterval) -> Double? {
        guard session.isRunning, !session.countsUp, now.isFinite,
              session.duration.isFinite, session.duration > 0 else { return nil }
        return min(1, max(0, session.reading(at: now) / session.duration))
    }

    /// Hiding the countdown never disables the session or its completion
    /// alerts, and a finished timer shows in the closed island until it is
    /// dismissed. The expanded timer page remains available.
    static func showsActivity(_ session: NotchTimerSession, in defaults: UserDefaults = .standard) -> Bool {
        session.hasSession && isEnabled(in: defaults)
            && (session.completed || !defaults.bool(forKey: DefaultsKey.notchHideTimerCountdown))
    }

    static func isSoundEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: DefaultsKey.notchTimerSoundEnabled) as? Bool ?? true
    }

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchTimer.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchTimerEnabled)
            && NotchSupport.modules(in: defaults).contains(.timer)
    }

    /// The modes read as three words in a row, the current one underlined,
    /// each as wide as its text, where a full top row leaves them room;
    /// beside a camera they are a menu named by the current one, its chevron
    /// `menuSpacing` from the name. The test measures both in every language.
    enum ModePicker {
        static let height: CGFloat = 24
        static let spacing: CGFloat = 14
        static let labelSize: CGFloat = 12
        static let labelPadding: CGFloat = 4
        static let menuSpacing: CGFloat = 3
        /// macOS 15 draws Japanese kana about 4% wider than macOS 26, so the
        /// stopwatch's name needs about 0.74 of its size beside the widest
        /// camera there.
        static let menuMinimumScale: CGFloat = 0.7

        /// Whether the menu beside the camera can name the current mode in
        /// `room`: every mode's name, so choosing another never changes how
        /// the menu reads, at the minimum scale with macOS 15's wider kana.
        /// Where the sections button leaves less, the menu shows the mode's
        /// glyph instead of cutting its name.
        static func menuNamesFit(_ names: [String], in room: CGFloat) -> Bool {
            let font = NSFont.systemFont(ofSize: labelSize, weight: .medium)
            let widest = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))?.size.width ?? 8
            return widest * menuMinimumScale * 1.05 + menuSpacing + chevron + labelPadding * 2 <= room
        }

        /// The glyph a menu with no room for the name shows: the closed
        /// island's own, a countdown's timer or the stopwatch.
        static func symbol(for mode: NotchTimerMode) -> String { mode == .stopwatch ? "stopwatch" : "timer" }
    }

    /// The start capsule in the top row; the test measures it against a side
    /// beside the camera, with the pin, in every language.
    enum StartButton {
        static let labelSize: CGFloat = 12
        static let padding: CGFloat = 10
    }

    static let timerLimit: TimeInterval = 180 * 60
    /// A stopwatch keeps counting; its clock saturates at the widest reading
    /// the surface fits, two hour digits.
    static let stopwatchLimit: TimeInterval = 100 * 3600 - 1

    static func timerMinutes(_ value: Int) -> Int { min(180, max(1, value)) }

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

    /// What a clock's digits roll on. The closed island can show a clock for
    /// hours, and rolling every second kept it animating a third of the time,
    /// at about ten times the energy of a clock that changes in place. There
    /// the seconds change in place and the rest rolls: "12:04" rolls as "12".
    static func rollingValue(_ value: String, everySecond: Bool) -> String {
        guard !everySecond, let colon = value.lastIndex(of: ":") else { return value }
        return String(value[..<colon])
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

    // MARK: Strip

    /// A wing is never narrower than the music strip's; the longest readings
    /// keep the width the strip always had.
    static let stripWingRange: ClosedRange<CGFloat> = 44...64
    /// Air between the camera and what sits beside it.
    static let stripCameraGap: CGFloat = 6

    static func stripTextSize(height: CGFloat) -> CGFloat { min(16, height - 6) }
    /// The mark takes the strip's height less an even gap above and below.
    static func stripIconSize(height: CGFloat) -> CGFloat { min(20, height - NotchLayout.compactEdgeGap * 2) }
    static func stripAgentMarkSize(height: CGFloat, working: Int) -> CGFloat {
        min(working > 1 ? 11 : 14, max(8, height - NotchLayout.compactEdgeGap * 2 - 4))
    }
}
