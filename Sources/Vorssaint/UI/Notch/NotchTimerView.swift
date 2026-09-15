// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchTimerView: View {
    @ObservedObject private var service = NotchTimerService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchTimerMode) private var mode: NotchTimerMode = .timer
    @AppStorage(DefaultsKey.notchPomodoroFocusMinutes) private var focusMinutes = 25
    @AppStorage(DefaultsKey.notchPomodoroShortBreakMinutes) private var shortBreakMinutes = 5
    @AppStorage(DefaultsKey.notchPomodoroLongBreakMinutes) private var longBreakMinutes = 15
    @AppStorage(DefaultsKey.notchPomodoroLongBreakInterval) private var longBreakInterval = 4
    @AppStorage(DefaultsKey.notchPomodoroTotalSessions) private var totalSessions = 4
    @State private var minutes = 15
    private var text: NotchActivityStrings { FeatureStrings.notchActivities(l10n.language) }

    var body: some View {
        ScrollView {
            Group {
                if service.session.hasSession { activeTimer }
                else { setup }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .tint(.orange)
    }

    private var setup: some View {
        VStack(spacing: 12) {
            Picker(text.timer, selection: $mode) {
                Text(text.timer).tag(NotchTimerMode.timer)
                Text(text.pomodoro).tag(NotchTimerMode.pomodoro)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            if mode == .timer {
                NotchTimerRuler(minutes: $minutes, label: text.timer,
                                locale: Locale(identifier: l10n.language.rawValue))
                    .frame(height: 82)
            } else {
                pomodoroOptions
            }
            HStack(spacing: 16) {
                Button { service.start(mode: mode, minutes: minutes) } label: {
                    Text(text.start)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .padding(.horizontal, 22).frame(height: 44)
                        .foregroundStyle(.orange)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(NotchButtonStyle(cornerRadius: 22))
                Spacer(minLength: 0)
                clock(NotchTimerSupport.clockText(Double(mode == .timer ? minutes : NotchPomodoroConfiguration.load().focusMinutes) * 60))
            }
            .frame(height: 72)
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
            TimelineView(.animation(minimumInterval: 1, paused: !service.session.isRunning)) { _ in
                let remaining = NotchTimerSupport.clockText(service.session.remaining(at: service.now))
                let title = service.session.cycleFinished ? text.pomodoroFinished
                    : service.session.completed ? text.finished : text.phase(service.session.phase)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(.system(size: 17, weight: .medium))
                        clock(remaining)
                    }.fixedSize()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(title).font(.system(size: 13, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        clock(remaining)
                    }
                }
                .foregroundStyle(.orange)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue(remaining)
            }
        }
        .frame(height: 96)
    }

    private var pomodoroOptions: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                option(text.focus, value: $focusMinutes, range: NotchPomodoroConfiguration.focusRange, duration: true)
                option(text.shortBreak, value: $shortBreakMinutes, range: NotchPomodoroConfiguration.breakRange, duration: true)
                option(text.longBreak, value: $longBreakMinutes, range: NotchPomodoroConfiguration.breakRange, duration: true)
                option(text.longBreakInterval, value: $longBreakInterval, range: NotchPomodoroConfiguration.sessionRange)
                option(text.totalSessions, value: $totalSessions, range: NotchPomodoroConfiguration.sessionRange)
            }
            .padding(10)
            .modifier(NotchControlSurface(cornerRadius: 16))
            Text(text.pomodoroHint)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func option(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, duration: Bool = false) -> some View {
        let bounded = Binding(get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) },
                              set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) })
        let display = duration
            ? NotchTimerSupport.compactText(Double(bounded.wrappedValue) * 60, locale: Locale(identifier: l10n.language.rawValue))
            : String(bounded.wrappedValue)
        return Stepper(value: bounded, in: range) {
            HStack(spacing: 8) {
                Text(title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(display).monospacedDigit().foregroundStyle(.orange).fixedSize()
            }
            .font(.system(size: 12, weight: .medium))
        }
        .frame(minHeight: 28)
        .accessibilityLabel(title)
        .accessibilityValue(display)
    }

    private func clock(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 62, weight: .thin)).monospacedDigit()
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
