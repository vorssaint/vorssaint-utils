// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BatteryCareSettings: View {
    @ObservedObject private var service = BatteryControlService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = BatteryConfiguration()
    @State private var dirty = false
    @State private var confirmingCalibration = false
    private func text(_ key: String) -> String { BatteryControlStrings.text(key, l10n.language) }

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                Label(text("title"), systemImage: "battery.100.bolt").font(.headline)
                Text(text("description")).font(.callout).foregroundStyle(.secondary)
                if !PowerSampler.hasInternalBattery { Text(text("noBattery")) }
                else if !service.authorized {
                    Text(text("authorizeCaption")).font(.caption).foregroundStyle(.secondary)
                    Button(text("authorize")) { service.authorize() }
                } else {
                    if let response = service.response {
                        HStack {
                            Text(text(response.state.rawValue)).font(.headline)
                            Spacer()
                            if let reading = response.telemetry { Text("\(reading.percent)%").font(.title2.monospacedDigit()) }
                        }
                        if let r = response.telemetry {
                            HStack(spacing: 16) {
                                if let temperature = r.temperature { Label(String(format: "%.1f °C", locale: MetricFormat.locale, temperature), systemImage: "thermometer.medium") }
                                if let watts = r.watts { Label(String(format: "%+.1f W", locale: MetricFormat.locale, watts), systemImage: "bolt.fill") }
                                if let cycles = r.cycles { Label("\(cycles)", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
                                if let health = r.health { Label(String(format: "%.0f%%", locale: MetricFormat.locale, health), systemImage: "heart") }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        if !response.supportsLimit { Text(text("unsupported")).foregroundStyle(.secondary) }
                    }
                    Toggle(text("enable"), isOn: binding(\.enabled))
                    valueRow("limit", value: binding(\.limit), range: 20...100, suffix: "%")
                    HStack {
                        ForEach([50, 70, 80, 90, 100], id: \.self) { limit in
                            Button("\(limit)%") { draft.limit = limit; dirty = true }
                        }
                        Spacer()
                        Button(text("apply")) { apply() }
                            .buttonStyle(.borderedProminent)
                            .disabled(service.busy || !draft.valid)
                    }
                    if service.configuration.enabled {
                        HStack {
                            Button(text("topUp")) { service.action(.topUp) }
                            Button(text("discharge")) { service.action(.discharge) }
                                .disabled(service.response?.supportsDischarge != true)
                            Button(text("pause")) { service.action(.pause) }
                            Button(text("resume")) { service.action(.resume) }
                        }.disabled(service.busy)
                        HStack {
                            Button(text("calibrate")) { confirmingCalibration = true }
                                .disabled(service.busy || service.response?.supportsDischarge != true)
                            if service.response?.mode == .calibration {
                                Text(text(service.response!.phase.rawValue)).font(.caption)
                                Button(text("cancel")) { service.action(.cancel) }
                            }
                        }
                    }
                    HStack {
                        Button(text("lowPowerOn")) { service.action(.lowPowerOn) }
                        Button(text("lowPowerOff")) { service.action(.lowPowerOff) }
                    }.disabled(service.busy || !service.configuration.enabled)
                    DisclosureGroup(FeatureStrings.recorder(l10n.language).moreOptions) {
                        VStack(alignment: .leading, spacing: 12) {
                            valueRow("sailing", value: binding(\.sailing), range: 0...20, suffix: "%")
                            Toggle(text("heatProtection"), isOn: binding(\.heatProtection))
                            if draft.heatProtection { valueRow("temperature", value: binding(\.maximumTemperature), range: 25...45, suffix: " °C") }
                            Toggle(text("automaticDischarge"), isOn: binding(\.automaticDischarge))
                                .disabled(service.response?.supportsDischarge != true)
                            Toggle(text("clamshell"), isOn: binding(\.dischargeInClamshell))
                                .disabled(service.response?.supportsDischarge != true)
                            Toggle(text("stopOnSleep"), isOn: binding(\.stopOnSleep))
                            Toggle(text("pauseClosed"), isOn: binding(\.pauseWhenClosed))
                            Toggle(text("continueClosed"), isOn: binding(\.continueWhenClosed))
                            Toggle(text("preventSleep"), isOn: binding(\.preventSleep))
                            Picker(text("led"), selection: binding(\.led)) {
                                ForEach(BatteryLED.allCases, id: \.self) { Text(text($0.rawValue)).tag($0) }
                            }.disabled(service.response?.supportsLED != true)
                            Text(text("conflict")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }
                    DisclosureGroup(text("schedule")) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(binding(\.schedules)) { $task in
                                VStack(alignment: .leading) {
                                    HStack {
                                        Toggle(text("enable"), isOn: $task.enabled).labelsHidden()
                                        DatePicker(text("date"), selection: $task.date)
                                        Button(role: .destructive) { draft.schedules.removeAll { $0.id == task.id }; dirty = true } label: {
                                            Image(systemName: "trash")
                                        }.accessibilityLabel(text("remove"))
                                    }
                                    HStack {
                                        Picker(text("action"), selection: $task.action) {
                                            ForEach(BatteryAction.allCases.filter { $0 != .cancel && $0 != .resume }, id: \.self) { Text(text($0.rawValue)).tag($0) }
                                        }
                                        Picker(text("repeat"), selection: $task.repetition) {
                                            ForEach(BatteryRepeat.allCases, id: \.self) { Text(text($0.rawValue)).tag($0) }
                                        }
                                    }
                                    if task.action == .setLimit || task.action == .discharge {
                                        Stepper("\(task.value)%", value: $task.value, in: 20...100)
                                    }
                                }
                                Divider()
                            }
                            Button(text("add")) { draft.schedules.append(BatterySchedule()); dirty = true }
                                .disabled(draft.schedules.count >= 32)
                        }.padding(.top, 8)
                    }
                    DisclosureGroup(text("shortcuts")) {
                        Text(text("shortcutsCaption")).font(.caption).textSelection(.enabled).padding(.top, 8)
                    }
                }
                if let error = service.error {
                    Text(text(error)).font(.caption).foregroundStyle(.red)
                    if service.response?.error == error, let detail = service.response?.errorDetail {
                        Text(verbatim: detail).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if service.busy { ProgressView().controlSize(.small) }
                if dirty { Text(text("unsaved")).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onAppear { draft = service.configuration; service.appear() }
        .onDisappear { service.disappear() }
        .onReceive(service.$response) { receive($0) }
        .confirmationDialog(text("calibrationCaption"), isPresented: $confirmingCalibration, titleVisibility: .visible) {
            Button(text("calibrate")) { service.action(.calibrate) }
        }
    }
    private func apply() {
        let submitted = draft
        service.save(submitted) { accepted in
            if accepted && self.draft == submitted { self.dirty = false }
        }
    }
    private func receive(_ response: BatteryResponse?) {
        guard !dirty, let response else { return }
        // An idle helper may restart with defaults; retain locally saved disabled settings.
        draft = response.configuration.enabled || service.configuration.enabled
            ? response.configuration : service.configuration
    }
    private func binding<T>(_ path: WritableKeyPath<BatteryConfiguration, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0; dirty = true })
    }
    private func valueRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) -> some View {
        HStack {
            Text(text(title)).frame(width: 160, alignment: .leading)
            Slider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                .accessibilityLabel(text(title))
            Text("\(value.wrappedValue)\(suffix)").monospacedDigit().frame(width: 55, alignment: .trailing)
        }
    }
}
