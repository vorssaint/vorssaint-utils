// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UserNotifications

struct MonitorAlertsControls: View {
    @ObservedObject private var l10n = L10n.shared
    let compact: Bool
    /// Non-nil only when hosted in the menu panel; Settings keeps its native
    /// controls without registering them in the panel navigator.
    var keyboardSection: PanelSectionID? = nil
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
        VStack(alignment: .leading, spacing: compact ? 7 : 8) {
            Text(text.caption)
                .font(compact ? .system(size: 9.5) : .caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if AppFeature.monitorCPU.isAvailable {
                Toggle(text.cpu, isOn: $alertCPU)
                    .panelKeyboardRow(row("alertCPU"), actions: toggleAction($alertCPU))
                if alertCPU {
                    Stepper("\(text.cpuThreshold) \(alertCPUThreshold)%",
                            value: $alertCPUThreshold,
                            in: 50...100,
                            step: 5)
                        .panelKeyboardRow(row("alertCPUThreshold"),
                                          actions: stepAction($alertCPUThreshold, range: 50...100))
                }
                Toggle(text.cpuTemperature, isOn: $alertCPUTemperature)
                    .panelKeyboardRow(row("alertCPUTemperature"), actions: toggleAction($alertCPUTemperature))
                if alertCPUTemperature {
                    Stepper("\(text.cpuTemperatureThreshold) \(alertCPUTemperatureThreshold) °C",
                            value: $alertCPUTemperatureThreshold,
                            in: 70...105,
                            step: 5)
                        .panelKeyboardRow(row("alertCPUTemperatureThreshold"),
                                          actions: stepAction($alertCPUTemperatureThreshold, range: 70...105))
                }
            }
            if AppFeature.monitorMemory.isAvailable {
                Toggle(text.memory, isOn: $alertMemory)
                    .panelKeyboardRow(row("alertMemory"), actions: toggleAction($alertMemory))
            }
            if AppFeature.monitorDisk.isAvailable {
                Toggle(text.disk, isOn: $alertDisk)
                    .panelKeyboardRow(row("alertDisk"), actions: toggleAction($alertDisk))
                if alertDisk {
                    Stepper("\(text.diskThreshold) \(alertDiskFreePercent)%",
                            value: $alertDiskFreePercent,
                            in: 5...30,
                            step: 5)
                        .panelKeyboardRow(row("alertDiskThreshold"),
                                          actions: stepAction($alertDiskFreePercent, range: 5...30))
                }
            }
            if AppFeature.monitorPower.isAvailable, PowerSampler.hasInternalBattery {
                Toggle(text.batteryTemperature, isOn: $alertBatteryTemperature)
                    .panelKeyboardRow(row("alertBatteryTemperature"), actions: toggleAction($alertBatteryTemperature))
                if alertBatteryTemperature {
                    Stepper("\(text.batteryTemperatureThreshold) \(alertBatteryTemperatureThreshold) °C",
                            value: $alertBatteryTemperatureThreshold,
                            in: 30...50,
                            step: 5)
                        .panelKeyboardRow(row("alertBatteryTemperatureThreshold"),
                                          actions: stepAction($alertBatteryTemperatureThreshold, range: 30...50))
                }
                Toggle(text.battery, isOn: $alertBattery)
                    .panelKeyboardRow(row("alertBattery"), actions: toggleAction($alertBattery))
                if alertBattery {
                    Stepper("\(text.batteryThreshold) \(alertBatteryPercent)%",
                            value: $alertBatteryPercent,
                            in: 5...50,
                            step: 5)
                        .panelKeyboardRow(row("alertBatteryThreshold"),
                                          actions: stepAction($alertBatteryPercent, range: 5...50))
                }
            }
            if anyAlertEnabled {
                Picker(text.cooldown, selection: $alertCooldown) {
                    Text(text.cooldown2).tag(2)
                    Text(text.cooldown5).tag(5)
                    Text(text.cooldown15).tag(15)
                    Text(text.cooldown30).tag(30)
                    Text(text.cooldown60).tag(60)
                }
                .pickerStyle(.menu)
                .panelKeyboardRow(row("alertCooldown"), actions: PanelRowActions(adjust: { direction, _ in
                    let values = [2, 5, 15, 30, 60]
                    guard let index = values.firstIndex(of: alertCooldown) else { return false }
                    let next = direction == .increase ? index + 1 : index - 1
                    guard values.indices.contains(next) else { return false }
                    alertCooldown = values[next]
                    return true
                }))
            }
            // Alerts silently cannot fire when macOS notifications are denied
            // for the app; without this line that state is invisible (the
            // user just never hears anything).
            if notificationsDenied, anyAlertEnabled {
                Text(text.notificationsDenied)
                    .font(compact ? .system(size: 9.5) : .caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
        .controlSize(compact ? .small : .regular)
        .font(compact ? .system(size: 10.5) : .body)
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

    private var anyAlertEnabled: Bool {
        alertCPU || alertCPUTemperature || alertMemory || alertDisk
            || (PowerSampler.hasInternalBattery && (alertBatteryTemperature || alertBattery))
    }

    private func row(_ localID: String) -> PanelRowID? {
        keyboardSection.map { PanelRowID($0, localID) }
    }

    private func toggleAction(_ value: Binding<Bool>) -> PanelRowActions {
        PanelRowActions(activate: { value.wrappedValue.toggle() })
    }

    private func stepAction(_ value: Binding<Int>, range: ClosedRange<Int>) -> PanelRowActions {
        PanelRowActions(adjust: { direction, _ in
            let next = min(range.upperBound, max(range.lowerBound,
                                                  value.wrappedValue + (direction == .increase ? 5 : -5)))
            guard next != value.wrappedValue else { return false }
            value.wrappedValue = next
            return true
        })
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
