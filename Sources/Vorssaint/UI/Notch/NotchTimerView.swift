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
    @State private var minutes = 15
    @Namespace private var modeSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    private var wide: Bool { size.width >= NotchLayout.timerWideWidth }

    var body: some View {
        Group {
            if service.session.hasSession { activeTimer }
            else { setup }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .tint(.orange)
    }

    /// The mode row over the ruler's row, whatever the mode: the
    /// timer and the Pomodoro's focus set on the ruler, the stopwatch's
    /// clock alone in that row. The Pomodoro adds one quiet line of
    /// readouts; a narrow island gives Start the last row and seats the
    /// readouts beside it.
    private var setup: some View {
        let rulerHeight = NotchLayout.timerRulerHeight(mode: mode, width: size.width, height: size.height)
        let locale = Locale(identifier: l10n.language.rawValue)
        return VStack(spacing: NotchLayout.timerRowSpacing) {
            HStack(spacing: 12) {
                modePicker
                Spacer(minLength: 0)
                if wide { startButton }
            }
            .frame(height: NotchLayout.timerTopRowHeight)
            HStack(spacing: 12) {
                switch mode {
                case .timer:
                    NotchTimerRuler(minutes: $minutes, label: text.timer, locale: locale)
                        .frame(height: rulerHeight)
                case .pomodoro:
                    NotchTimerRuler(minutes: binding(.focus), label: text.focus, locale: locale)
                        .frame(height: rulerHeight)
                case .stopwatch:
                    Spacer(minLength: 0)
                }
                if wide || mode == .stopwatch { clock(setupClock, size: 26) }
            }
            .frame(height: rulerHeight)
            if mode == .pomodoro {
                HStack(spacing: 12) {
                    if !wide { clock(setupClock, size: 26) }
                    pomodoroSettings
                    if !wide { startButton }
                }
                .frame(height: wide ? NotchLayout.timerSettingsRowHeight : NotchLayout.timerStartHeight)
            } else if !wide {
                HStack(spacing: 12) {
                    if mode == .timer { clock(setupClock, size: 26) }
                    Spacer(minLength: 0)
                    startButton
                }
                .frame(height: NotchLayout.timerStartHeight)
            }
        }
    }

    private var startButton: some View {
        Button { service.start(mode: mode, minutes: minutes) } label: {
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

    private var setupClock: String {
        switch mode {
        case .timer: return NotchTimerSupport.clockText(Double(minutes) * 60)
        case .pomodoro: return NotchTimerSupport.clockText(Double(binding(.focus).wrappedValue) * 60)
        case .stopwatch: return NotchTimerSupport.stopwatchText(0)
        }
    }

    /// Three words in a row, the current one underlined in the ruler's
    /// orange: a heading beside Start, not a control with a box of its own.
    /// Each label is as wide as its word, so the longest translation never
    /// pushes the three past a narrow island.
    private var modePicker: some View {
        HStack(spacing: NotchTimerSupport.ModePicker.spacing) {
            ForEach(NotchTimerMode.allCases, id: \.self) { candidate in
                let selected = mode == candidate
                Button { mode = candidate } label: {
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

    private var activeTimer: some View {
        VStack(spacing: 4) {
            activeControls
            if service.session.mode == .pomodoro {
                Text(String(format: text.sessionProgress, service.session.sessionNumber, service.session.configuration.totalSessions))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var activeControls: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                if !service.session.completed {
                    roundButton(symbol: service.session.isPaused ? "play.fill" : "pause.fill",
                                title: service.session.isPaused ? text.resume : l10n.s.actionPause,
                                primary: true, action: service.pauseOrResume)
                } else if service.session.canStartNext {
                    roundButton(symbol: "play.fill", title: text.start + " " + text.phase(service.session.nextPhase),
                                primary: true, action: service.startNext)
                }
                roundButton(symbol: "xmark",
                            title: service.session.completed ? l10n.s.supportIntroDoneButton : l10n.s.mediaCancel,
                            primary: false, action: service.cancel)
            }
            Spacer(minLength: 0)
            if service.session.isRunning {
                TimelineView(.periodic(from: Date(timeIntervalSinceNow: NotchTimerSupport.tickScheduleOffset(
                    for: service.session, at: service.now)), by: 1)) { _ in reading }
            } else {
                reading
            }
        }
        .frame(height: 96)
    }

    private var reading: some View {
        let value = NotchTimerSupport.clockText(for: service.session, at: service.now)
        let title = service.session.cycleFinished ? text.pomodoroFinished
            : service.session.completed ? text.finished : text.phase(service.session.phase)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 17, weight: .medium))
                clock(value, size: 62)
            }.fixedSize()
            VStack(alignment: .trailing, spacing: 0) {
                Text(title).font(.system(size: 13, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.7)
                clock(value, size: 62)
            }
        }
        .foregroundStyle(.orange)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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

    private func roundButton(symbol: String, title: String, primary: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(primary ? .orange : .white)
                .frame(width: 52, height: 52)
                .background(primary ? Color.orange.opacity(0.28) : Color.white.opacity(0.18), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 26))
        .accessibilityLabel(title)
        .help(title)
    }
}
