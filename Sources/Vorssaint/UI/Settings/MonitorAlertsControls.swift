// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UserNotifications

struct MonitorAlertsControls: View {
    @ObservedObject private var l10n = L10n.shared
    let compact: Bool
    @State private var notificationsDenied = false
    @AppStorage(DefaultsKey.monitorAlertCPU) private var alertCPU = false
    @AppStorage(DefaultsKey.monitorAlertCPUTemperature) private var alertCPUTemperature = false
    @AppStorage(DefaultsKey.monitorAlertBatteryTemperature) private var alertBatteryTemperature = false
    @AppStorage(DefaultsKey.monitorAlertMemory) private var alertMemory = false
    @AppStorage(DefaultsKey.monitorAlertDisk) private var alertDisk = false
    @AppStorage(DefaultsKey.monitorAlertBattery) private var alertBattery = false
    @AppStorage(DefaultsKey.monitorAlertCPUThreshold) private var alertCPUThreshold = 90
    @AppStorage(DefaultsKey.monitorAlertCPUTemperatureThreshold) private var alertCPUTemperatureThreshold = 90
    @AppStorage(DefaultsKey.monitorAlertBatteryTemperatureThreshold) private var alertBatteryTemperatureThreshold = 40
    @AppStorage(DefaultsKey.monitorAlertDiskFreePercent) private var alertDiskFreePercent = 10
    @AppStorage(DefaultsKey.monitorAlertBatteryPercent) private var alertBatteryPercent = 15
    @AppStorage(DefaultsKey.monitorAlertCooldownMinutes) private var alertCooldown = 15

    private var text: MonitorAlertFeatureStrings {
        FeatureStrings.monitorAlerts(l10n.language)
    }

    var body: some View {
        // The panel keeps its compact checkbox list; Settings draws one label
        // per alert, with its limit on the label's options half.
        Group {
            if compact {
                checklist
            } else {
                tiles
            }
        }
        .onAppear {
            sanitizeAlertValues()
            refreshNotificationStatus()
        }
        .onChange(of: alertCPU) { _, _ in MonitorAlertService.shared.syncWithPreferences(); refreshNotificationStatus() }
        .onChange(of: alertCPUTemperature) { _, _ in MonitorAlertService.shared.syncWithPreferences(); refreshNotificationStatus() }
        .onChange(of: alertBatteryTemperature) { _, _ in MonitorAlertService.shared.syncWithPreferences(); refreshNotificationStatus() }
        .onChange(of: alertMemory) { _, _ in MonitorAlertService.shared.syncWithPreferences(); refreshNotificationStatus() }
        .onChange(of: alertDisk) { _, _ in MonitorAlertService.shared.syncWithPreferences(); refreshNotificationStatus() }
        .onChange(of: alertBattery) { _, _ in MonitorAlertService.shared.syncWithPreferences(); refreshNotificationStatus() }
        .onChange(of: alertCPUThreshold) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertCPUTemperatureThreshold) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertBatteryTemperatureThreshold) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertDiskFreePercent) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertBatteryPercent) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertCooldown) { _, _ in sanitizeAlertValues() }
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: monitorTokenColumns, spacing: 8) {
                if AppFeature.monitorCPU.isAvailable {
                    alertToken(text.cpu, symbol: "cpu", isOn: $alertCPU,
                               limit: .init(label: text.cpuThreshold, value: $alertCPUThreshold,
                                            range: 50...100, step: 5, unit: "%"))
                    alertToken(text.cpuTemperature, symbol: "thermometer.medium", isOn: $alertCPUTemperature,
                               limit: .init(label: text.cpuTemperatureThreshold, value: $alertCPUTemperatureThreshold,
                                            range: 70...105, step: 5, unit: " °C"))
                }
                if AppFeature.monitorMemory.isAvailable {
                    alertToken(text.memory, symbol: "memorychip", isOn: $alertMemory, limit: nil)
                }
                if AppFeature.monitorDisk.isAvailable {
                    alertToken(text.disk, symbol: "internaldrive", isOn: $alertDisk,
                               limit: .init(label: text.diskThreshold, value: $alertDiskFreePercent,
                                            range: 5...30, step: 5, unit: "%"))
                }
                if AppFeature.monitorPower.isAvailable, PowerSampler.hasInternalBattery {
                    alertToken(text.batteryTemperature, symbol: "thermometer.high", isOn: $alertBatteryTemperature,
                               limit: .init(label: text.batteryTemperatureThreshold,
                                            value: $alertBatteryTemperatureThreshold,
                                            range: 30...50, step: 5, unit: " °C"))
                    alertToken(text.battery, symbol: "battery.25percent", isOn: $alertBattery,
                               limit: .init(label: text.batteryThreshold, value: $alertBatteryPercent,
                                            range: 5...50, step: 5, unit: "%"))
                }
            }
            .monitorTokenGroup()
            // One interval for every alert, each timed on its own, so it sits
            // outside the alerts box rather than under the last of them.
            SettingsRow(symbol: "bell.badge", title: text.cooldown) {
                cooldownPicker
                    .labelsHidden()
                    .fixedSize()
            }
            .disabled(!anyAlertEnabled)
            if notificationsDenied, anyAlertEnabled {
                Text(text.notificationsDenied)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(text.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Limit {
        let label: String
        let value: Binding<Int>
        let range: ClosedRange<Int>
        let step: Int
        let unit: String
    }

    /// One alert as a label, with the limit it fires at on its options half.
    private func alertToken(_ title: String, symbol: String, isOn: Binding<Bool>, limit: Limit?) -> some View {
        MonitorToken(symbol: symbol, title: title, included: isOn,
                     options: limit.map { limit in
                         AnyView(Stepper(value: limit.value, in: limit.range, step: limit.step) {
                             Text("\(limit.label) \(limit.value.wrappedValue)\(limit.unit)").monospacedDigit()
                         })
                     },
                     optionsSummary: limit.map { "\($0.value.wrappedValue)\($0.unit)" } ?? "")
    }

    private var cooldownPicker: some View {
        Picker(text.cooldown, selection: $alertCooldown) {
            Text(text.cooldown2).tag(2)
            Text(text.cooldown5).tag(5)
            Text(text.cooldown15).tag(15)
            Text(text.cooldown30).tag(30)
            Text(text.cooldown60).tag(60)
        }
        .pickerStyle(.menu)
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(text.caption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if AppFeature.monitorCPU.isAvailable {
                Toggle(text.cpu, isOn: $alertCPU)
                if alertCPU {
                    Stepper("\(text.cpuThreshold) \(alertCPUThreshold)%",
                            value: $alertCPUThreshold,
                            in: 50...100,
                            step: 5)
                }
                Toggle(text.cpuTemperature, isOn: $alertCPUTemperature)
                if alertCPUTemperature {
                    Stepper("\(text.cpuTemperatureThreshold) \(alertCPUTemperatureThreshold) °C",
                            value: $alertCPUTemperatureThreshold,
                            in: 70...105,
                            step: 5)
                }
            }
            if AppFeature.monitorMemory.isAvailable {
                Toggle(text.memory, isOn: $alertMemory)
            }
            if AppFeature.monitorDisk.isAvailable {
                Toggle(text.disk, isOn: $alertDisk)
                if alertDisk {
                    Stepper("\(text.diskThreshold) \(alertDiskFreePercent)%",
                            value: $alertDiskFreePercent,
                            in: 5...30,
                            step: 5)
                }
            }
            if AppFeature.monitorPower.isAvailable, PowerSampler.hasInternalBattery {
                Toggle(text.batteryTemperature, isOn: $alertBatteryTemperature)
                if alertBatteryTemperature {
                    Stepper("\(text.batteryTemperatureThreshold) \(alertBatteryTemperatureThreshold) °C",
                            value: $alertBatteryTemperatureThreshold,
                            in: 30...50,
                            step: 5)
                }
                Toggle(text.battery, isOn: $alertBattery)
                if alertBattery {
                    Stepper("\(text.batteryThreshold) \(alertBatteryPercent)%",
                            value: $alertBatteryPercent,
                            in: 5...50,
                            step: 5)
                }
            }
            if anyAlertEnabled {
                cooldownPicker
            }
            // Alerts silently cannot fire when macOS notifications are denied
            // for the app; without this line that state is invisible (the
            // user just never hears anything).
            if notificationsDenied, anyAlertEnabled {
                Text(text.notificationsDenied)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.system(size: 10.5))
    }

    private var anyAlertEnabled: Bool {
        alertCPU || alertCPUTemperature || alertMemory || alertDisk
            || (PowerSampler.hasInternalBattery && (alertBatteryTemperature || alertBattery))
    }

    /// Checked slightly delayed so a just-fired authorization prompt has a
    /// chance to be answered before the warning appears.
    private func refreshNotificationStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    notificationsDenied = settings.authorizationStatus == .denied
                }
            }
        }
    }

    private func sanitizeAlertValues() {
        alertCPUThreshold = Defaults.sanitizedPercent(alertCPUThreshold, fallback: 90, range: 50...100)
        alertCPUTemperatureThreshold = Defaults.sanitizedPercent(alertCPUTemperatureThreshold, fallback: 90, range: 70...105)
        alertBatteryTemperatureThreshold = Defaults.sanitizedPercent(alertBatteryTemperatureThreshold,
                                                                     fallback: 40,
                                                                     range: 30...50)
        alertDiskFreePercent = Defaults.sanitizedPercent(alertDiskFreePercent, fallback: 10, range: 5...30)
        alertBatteryPercent = Defaults.sanitizedPercent(alertBatteryPercent, fallback: 15, range: 5...50)
        alertCooldown = Defaults.sanitizedMonitorAlertCooldown(alertCooldown)
    }
}
