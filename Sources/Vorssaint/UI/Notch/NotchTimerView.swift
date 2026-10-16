// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchTimerView: View {
    let size: CGSize
    @ObservedObject private var service = NotchTimerService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchTimerMode) private var mode: NotchTimerMode = .timer
    @AppStorage(DefaultsKey.notchPomodoroFocusMinutes) private var focusMinutes = 25
    @AppStorage(DefaultsKey.notchPomodoroShortBreakMinutes) private var shortBreakMinutes = 5
    @AppStorage(DefaultsKey.notchPomodoroLongBreakMinutes) private var longBreakMinutes = 15
    @AppStorage(DefaultsKey.notchPomodoroLongBreakInterval) private var longBreakInterval = 4
    @AppStorage(DefaultsKey.notchPomodoroTotalSessions) private var totalSessions = 4
    @AppStorage(DefaultsKey.notchTimerMinutes) private var savedMinutes = 15
    @Namespace private var modeSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchBand) private var band
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        Group {
            if service.session.hasSession { activeTimer }
            else { setup }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(.orange)
        // The island's top row holds what used to head the page: the modes
        // and Start while setting up, the phase and the way out once running.
        .notchBand {
            if service.session.hasSession { phaseReading }
            else if band.besideCamera { modeMenu }
            else {
                // A full row keeps the three words where they fit beside Start.
                ViewThatFits(in: .horizontal) {
                    modePicker
                    modeMenu
                }
            }
        } trailing: {
            if service.session.hasSession {
                NotchIconButton(symbol: "xmark",
                                title: service.session.completed ? l10n.s.supportIntroDoneButton : l10n.s.mediaCancel,
                                action: service.cancel)
            } else {
                startButton
            }
        }
    }

    /// The ruler's row, whatever the mode: the timer and the Pomodoro's
    /// focus set on the ruler beside their clock, the stopwatch's clock
    /// alone in that row. The Pomodoro adds one quiet line of readouts.
    private var setup: some View {
        let rulerHeight = NotchLayout.timerRulerHeight(mode: mode, height: size.height)
        let locale = Locale(identifier: l10n.language.rawValue)
        return VStack(spacing: NotchLayout.timerRowSpacing) {
            HStack(spacing: 12) {
                switch mode {
                case .timer:
                    NotchTimerRuler(minutes: timerMinutes, label: text.timer, locale: locale)
                        .frame(height: rulerHeight)
                case .pomodoro:
                    NotchTimerRuler(minutes: binding(.focus), label: text.focus, locale: locale)
                        .frame(height: rulerHeight)
                case .stopwatch:
                    Spacer(minLength: 0)
                }
                clock(setupClock, size: 26)
            }
            .frame(height: rulerHeight)
            if mode == .pomodoro {
                pomodoroSettings
                    .frame(height: NotchLayout.timerSettingsRowHeight)
            }
        }
    }

    /// A small capsule in the top row, in the ruler's orange.
    private var startButton: some View {
        Button { service.start(mode: mode, minutes: timerMinutes.wrappedValue) } label: {
            Text(text.start)
                .font(.system(size: NotchTimerSupport.StartButton.labelSize, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, NotchTimerSupport.StartButton.padding)
                .frame(height: NotchLayout.timerStartHeight)
                .foregroundStyle(.orange)
                .background(.orange.opacity(0.18), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.timerStartHeight / 2))
        .help(mode == .pomodoro ? text.pomodoroHint : text.start)
    }

    /// Beside the camera the three words do not fit, so the modes are a
    /// menu named by the current one.
    private var modeMenu: some View {
        let current = title(for: mode)
        return NotchMenuButton(title: text.timer, items: NotchTimerMode.allCases.map { candidate in
            NotchMenuItem(title: title(for: candidate), checked: candidate == mode) {
                NotchService.shared.selectTimerMode(candidate)
            }
        }) {
            HStack(spacing: NotchTimerSupport.ModePicker.menuSpacing) {
                // Beside a wide camera a long name narrows a little rather
                // than losing its last letters.
                Text(current)
                    .font(.system(size: NotchTimerSupport.ModePicker.labelSize, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(NotchTimerSupport.ModePicker.menuMinimumScale)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, NotchTimerSupport.ModePicker.labelPadding)
            .frame(height: 28)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help(current)
        .accessibilityValue(current)
    }

    private var setupClock: String {
        switch mode {
        case .timer: return NotchTimerSupport.clockText(Double(timerMinutes.wrappedValue) * 60)
        case .pomodoro: return NotchTimerSupport.clockText(Double(binding(.focus).wrappedValue) * 60)
        case .stopwatch: return NotchTimerSupport.stopwatchText(0)
        }
    }

    /// Three words in a row, the current one underlined in the ruler's
    /// orange: a heading beside Start, not a control with a box of its own.
    /// Each label is as wide as its word, so the three fit beside Start in
    /// every language from the compact preset's width on.
    private var modePicker: some View {
        HStack(spacing: NotchTimerSupport.ModePicker.spacing) {
            ForEach(NotchTimerMode.allCases, id: \.self) { candidate in
                let selected = mode == candidate
                Button { NotchService.shared.selectTimerMode(candidate) } label: {
                    Text(title(for: candidate))
                        .font(.system(size: NotchTimerSupport.ModePicker.labelSize, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(selected ? .white : .white.opacity(0.5))
                        .padding(.horizontal, NotchTimerSupport.ModePicker.labelPadding)
                        .frame(height: NotchTimerSupport.ModePicker.height)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(.orange).frame(height: 2)
                                    .padding(.horizontal, NotchTimerSupport.ModePicker.labelPadding)
                                    .matchedGeometryEffect(id: "selection", in: modeSelection)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 6, lifts: false))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: mode)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(text.timer)
    }

    private func title(for mode: NotchTimerMode) -> String {
        switch mode {
        case .timer: return text.timer
        case .pomodoro: return text.pomodoro
        case .stopwatch: return text.stopwatch
        }
    }

    /// The primary button and the clock; the phase and the way out are in
    /// the top row.
    private var activeTimer: some View {
        HStack(spacing: 16) {
            if !service.session.completed {
                roundButton(symbol: service.session.isPaused ? "play.fill" : "pause.fill",
                            title: service.session.isPaused ? text.resume : l10n.s.actionPause,
                            action: service.pauseOrResume)
            } else if service.session.canStartNext {
                roundButton(symbol: "play.fill", title: text.start + " " + text.phase(service.session.nextPhase),
                            action: service.startNext)
            }
            Spacer(minLength: 0)
            if service.session.isRunning {
                TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                    for: service.session, at: service.now)), by: 1)) { _ in reading }
            } else {
                reading
            }
        }
        .frame(height: NotchLayout.timer(mode: service.session.mode, hasSession: true, height: size.height))
    }

    private var phaseTitle: String {
        service.session.cycleFinished ? text.pomodoroFinished
            : service.session.completed ? text.finished : text.phase(service.session.phase)
    }

    /// The phase, and a Pomodoro's place in its cycle, on one line where
    /// they fit and on two short ones where they do not.
    private var phaseReading: some View {
        let title = phaseTitle
        let progress = service.session.mode == .pomodoro
            ? String(format: text.sessionProgress, service.session.sessionNumber, service.session.configuration.totalSessions)
            : nil
        let phase = Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
        let place = progress.map { Text($0).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary) }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                phase
                place
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 0) {
                phase
                place
            }
            .lineLimit(1)
        }
        .help([title, progress].compactMap { $0 }.joined(separator: ", "))
        .accessibilityElement(children: .combine)
    }

    private var reading: some View {
        let value = NotchTimerSupport.clockText(for: service.session, at: service.now)
        return clock(value, size: 62)
            .modifier(NotchRollingDigits(value: value, countsDown: !service.session.countsUp))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phaseTitle)
            .accessibilityValue(value)
    }

    /// The breaks and the sessions as readouts in the ruler's own language:
    /// the name small and dim, the value in orange, the usual values behind
    /// a native menu. They spread across a wide island and run sideways past
    /// a narrow one.
    private var pomodoroSettings: some View {
        let readouts = NotchPomodoroOption.allCases.filter { $0 != .focus }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(readouts) { readout($0).frame(maxWidth: .infinity, alignment: .leading) }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(readouts) { readout($0) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func readout(_ option: NotchPomodoroOption) -> some View {
        let value = binding(option)
        let title = title(option)
        let current = value.wrappedValue
        return NotchMenuButton(title: title, items: option.range.map { choice in
            NotchMenuItem(title: display(option, choice), checked: choice == current) { value.wrappedValue = choice }
        }) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                HStack(spacing: 3) {
                    Text(display(option, current))
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.orange)
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: NotchLayout.timerSettingsRowHeight)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help(title)
        .accessibilityValue(display(option, current))
    }

    private var timerMinutes: Binding<Int> {
        Binding(get: { NotchTimerSupport.timerMinutes(savedMinutes) },
                set: { savedMinutes = NotchTimerSupport.timerMinutes($0) })
    }

    private func binding(_ option: NotchPomodoroOption) -> Binding<Int> {
        let stored: Binding<Int>
        switch option {
        case .focus: stored = $focusMinutes
        case .shortBreak: stored = $shortBreakMinutes
        case .longBreak: stored = $longBreakMinutes
        case .longBreakInterval: stored = $longBreakInterval
        case .totalSessions: stored = $totalSessions
        }
        let range = option.range
        return Binding(get: { min(range.upperBound, max(range.lowerBound, stored.wrappedValue)) },
                       set: { stored.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) })
    }

    private func title(_ option: NotchPomodoroOption) -> String {
        switch option {
        case .focus: return text.focus
        case .shortBreak: return text.shortBreak
        case .longBreak: return text.longBreak
        case .longBreakInterval: return text.longBreakInterval
        case .totalSessions: return text.totalSessions
        }
    }

    private func display(_ option: NotchPomodoroOption, _ value: Int) -> String {
        option.isDuration
            ? NotchTimerSupport.compactText(Double(value) * 60, locale: Locale(identifier: l10n.language.rawValue))
            : String(value)
    }

    private func clock(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .thin)).monospacedDigit()
            .foregroundStyle(.orange)
            .lineLimit(1).minimumScaleFactor(0.5)
    }

    private func roundButton(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(Color.orange.opacity(0.28), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 26))
        .accessibilityLabel(title)
        .help(title)
    }
}
