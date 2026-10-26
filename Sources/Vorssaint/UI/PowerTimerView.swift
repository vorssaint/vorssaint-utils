// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The same native editor is used in Energy settings and the menu panel.
struct PowerTimerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service: PowerTimerService
    @AppStorage(DefaultsKey.powerTimerMinutes) private var minutes = 30
    @AppStorage(DefaultsKey.powerTimerAction) private var actionValue = PowerTimerAction.sleep.rawValue
    @State private var minutesInput = ""
    @State private var atClockTime = false
    @State private var clockTime = Date().addingTimeInterval(3600)
    @State private var confirmingShutdown = false
    @State private var pendingShutdown: PendingSchedule?
    private enum PendingSchedule { case duration(Int), clock(Date) }

    init(service: PowerTimerService = .shared, clockTime: Date? = nil) {
        self.service = service
        _atClockTime = State(initialValue: clockTime != nil)
        _clockTime = State(initialValue: clockTime ?? Date().addingTimeInterval(3600))
    }

    private var text: PowerTimerStrings { FeatureStrings.powerTimer(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var action: PowerTimerAction { PowerTimerAction(rawValue: actionValue) ?? .sleep }
    private var busy: Bool { service.preparing || service.executing }
    private var valid: Bool {
        atClockTime ? PowerTimerSession.clockTime(clockTime, action: action, now: Date()) != nil
            : PowerTimerSession.minutes(from: minutesInput) != nil
    }
    private func title(_ action: PowerTimerAction) -> String {
        let strings = FeatureStrings.commandBar(l10n.language)
        return action == .sleep ? strings.powerSleep : strings.powerShutDown
    }

    var body: some View {
        if AppFeature.powerTimer.isAvailable {
            VStack(alignment: .leading, spacing: 12) {
                if let session = service.session { running(session) }
                else if busy { busyStatus }
                else { editor }
                if let failure = service.failure { caption(errorText(failure), error: true) }
                caption(text.note)
                if action == .shutDown || service.session?.action == .shutDown { caption(text.shutdownNote) }
            }
            .confirmationDialog(title(.shutDown), isPresented: $confirmingShutdown) {
                Button(text.start, role: .destructive) { startConfirmedShutdown() }
                Button(l10n.s.cutCancel, role: .cancel) {}
            } message: { Text(text.shutdownNote) }
            .onAppear {
                if !(1...1440).contains(minutes) { minutes = 30 }
                minutesInput = String(minutes)
                if PowerTimerAction(rawValue: actionValue) == nil { actionValue = PowerTimerAction.sleep.rawValue }
            }
        }
    }

    private func running(_ session: PowerTimerSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(title(session.action), systemImage: session.action == .sleep ? "moon.zzz" : "power")
                        Spacer()
                        Text(countdown(service.remaining())).font(.title2.monospacedDigit())
                    }
                    Text(text.scheduled + " " + (service.scheduledDate() ?? session.displayDate)
                        .formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(l10n.s.cutCancel) { service.cancel() }
        }
    }

    private var busyStatus: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { ProgressView().controlSize(.small); Text(text.working) }
            if service.preparing { Button(l10n.s.cutCancel) { service.cancel() } }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text.action, selection: $actionValue) {
                ForEach(PowerTimerAction.allCases, id: \.rawValue) { action in
                    Text(title(action)).tag(action.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Picker(text.scheduled, selection: $atClockTime) {
                Text(text.after).tag(false)
                Text(text.at).tag(true)
            }
            .pickerStyle(.segmented)
            timeEditor
            Button(text.start) {
                if action == .shutDown {
                    if atClockTime { pendingShutdown = .clock(clockTime) }
                    else if let value = PowerTimerSession.minutes(from: minutesInput) {
                        pendingShutdown = .duration(value)
                    }
                    confirmingShutdown = true
                }
                else { start() }
            }
            .buttonStyle(.borderedProminent).disabled(!valid)
            if !valid { caption(text.timeError) }
        }
    }

    @ViewBuilder private var timeEditor: some View {
        if atClockTime {
            DatePicker(text.at, selection: $clockTime,
                       displayedComponents: [.date, .hourAndMinute]).datePickerStyle(.field)
                .environment(\.locale, locale)
        } else {
            HStack {
                Text(text.minutes)
                Spacer()
                TextField(text.minutes, text: $minutesInput)
                    .textFieldStyle(.roundedBorder).frame(width: 74)
                    .accessibilityLabel(text.minutes)
                Stepper(text.minutes, value: minuteBinding, in: 1...1440)
                    .labelsHidden().accessibilityLabel(text.minutes)
            }
        }
    }

    private func start() {
        if atClockTime { service.start(at: clockTime, action: action) }
        else if let value = PowerTimerSession.minutes(from: minutesInput) {
            minutes = value
            service.start(minutes: value, action: action)
        }
    }

    private var minuteBinding: Binding<Int> {
        Binding(get: { PowerTimerSession.minutes(from: minutesInput) ?? minutes },
                set: { minutesInput = String($0); minutes = $0 })
    }

    private func startConfirmedShutdown() {
        // Another open editor can change AppStorage while this dialog is up.
        // Execute only the action and schedule that this editor confirmed.
        guard let pendingShutdown else { return }
        self.pendingShutdown = nil
        switch pendingShutdown {
        case .duration(let value):
            minutes = value
            service.start(minutes: value, action: .shutDown)
        case .clock(let date): service.start(at: date, action: .shutDown)
        }
    }

    private func caption(_ value: String, error: Bool = false) -> some View {
        Text(value).font(.caption).foregroundStyle(error ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func errorText(_ failure: PowerTimerService.Failure) -> String {
        switch failure {
        case .permission: return text.permissionError
        case .execution: return text.failureError
        case .invalidTime: return text.timeError
        case .keepAwake: return text.clamshellError
        }
    }

    private func countdown(_ seconds: TimeInterval) -> String {
        let value = Int(ceil(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}
