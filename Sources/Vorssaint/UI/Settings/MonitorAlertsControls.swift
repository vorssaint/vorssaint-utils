// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct MonitorAlertsControls: View {
    @ObservedObject private var l10n = L10n.shared
    let compact: Bool
    @AppStorage(DefaultsKey.monitorAlertCPU) private var alertCPU = false
    @AppStorage(DefaultsKey.monitorAlertCPUTemperature) private var alertCPUTemperature = false
    @AppStorage(DefaultsKey.monitorAlertMemory) private var alertMemory = false
    @AppStorage(DefaultsKey.monitorAlertDisk) private var alertDisk = false
    @AppStorage(DefaultsKey.monitorAlertBattery) private var alertBattery = false
    @AppStorage(DefaultsKey.monitorAlertCPUThreshold) private var alertCPUThreshold = 90
    @AppStorage(DefaultsKey.monitorAlertCPUTemperatureThreshold) private var alertCPUTemperatureThreshold = 90
    @AppStorage(DefaultsKey.monitorAlertDiskFreePercent) private var alertDiskFreePercent = 10
    @AppStorage(DefaultsKey.monitorAlertBatteryPercent) private var alertBatteryPercent = 15
    @AppStorage(DefaultsKey.monitorAlertCooldownMinutes) private var alertCooldown = 15

    private var text: MonitorAlertFeatureStrings {
        FeatureStrings.monitorAlerts(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 8) {
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
            Toggle(text.memory, isOn: $alertMemory)
            Toggle(text.disk, isOn: $alertDisk)
            if alertDisk {
                Stepper("\(text.diskThreshold) \(alertDiskFreePercent)%",
                        value: $alertDiskFreePercent,
                        in: 5...30,
                        step: 5)
            }
            Toggle(text.battery, isOn: $alertBattery)
            if alertBattery {
                Stepper("\(text.batteryThreshold) \(alertBatteryPercent)%",
                        value: $alertBatteryPercent,
                        in: 5...50,
                        step: 5)
            }
            Picker(text.cooldown, selection: $alertCooldown) {
                Text(text.cooldown5).tag(5)
                Text(text.cooldown15).tag(15)
                Text(text.cooldown30).tag(30)
                Text(text.cooldown60).tag(60)
            }
            .pickerStyle(.menu)
            Text(text.caption)
                .font(compact ? .system(size: 9.5) : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
        .controlSize(compact ? .small : .regular)
        .font(compact ? .system(size: 10.5) : .body)
        .onAppear(perform: sanitizeAlertValues)
        .onChange(of: alertCPU) { _, _ in MonitorAlertService.shared.syncWithPreferences() }
        .onChange(of: alertCPUTemperature) { _, _ in MonitorAlertService.shared.syncWithPreferences() }
        .onChange(of: alertMemory) { _, _ in MonitorAlertService.shared.syncWithPreferences() }
        .onChange(of: alertDisk) { _, _ in MonitorAlertService.shared.syncWithPreferences() }
        .onChange(of: alertBattery) { _, _ in MonitorAlertService.shared.syncWithPreferences() }
        .onChange(of: alertCPUThreshold) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertCPUTemperatureThreshold) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertDiskFreePercent) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertBatteryPercent) { _, _ in sanitizeAlertValues() }
        .onChange(of: alertCooldown) { _, _ in sanitizeAlertValues() }
    }

    private func sanitizeAlertValues() {
        alertCPUThreshold = Defaults.sanitizedPercent(alertCPUThreshold, fallback: 90, range: 50...100)
        alertCPUTemperatureThreshold = Defaults.sanitizedPercent(alertCPUTemperatureThreshold, fallback: 90, range: 70...105)
        alertDiskFreePercent = Defaults.sanitizedPercent(alertDiskFreePercent, fallback: 10, range: 5...30)
        alertBatteryPercent = Defaults.sanitizedPercent(alertBatteryPercent, fallback: 15, range: 5...50)
        alertCooldown = Defaults.sanitizedMonitorAlertCooldown(alertCooldown)
    }
}
