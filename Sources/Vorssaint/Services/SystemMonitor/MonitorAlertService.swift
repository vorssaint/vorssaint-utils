// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Optional Monitor notifications. Everything is off by default, throttled, and
/// driven by the existing SystemMonitor sampler.
final class MonitorAlertService {
    static let shared = MonitorAlertService()

    private var cancellables = Set<AnyCancellable>()
    private var cpuUsageGate = SustainedAlertGate()
    private var cpuTemperatureGate = SustainedAlertGate()
    private var batteryTemperatureGate = SustainedAlertGate()
    private var lastSent: [MonitorAlertKind: Date] = [:]
    private var lastDiskAlert: (sentAt: Date, isCritical: Bool)?

    private init() {}

    /// Owns the whole lifecycle: the snapshot sink only exists while some
    /// alert is on for an available metric, so the service costs nothing
    /// otherwise. The alert toggles in Settings call this on every change.
    func syncWithPreferences() {
        let enabled = Self.anyEnabled(in: .standard)
        if enabled {
            startSinkIfNeeded()
        } else {
            stopSink()
        }
        SystemMonitor.shared.setAlertsActive(enabled)
        if enabled {
            Notifier.requestPermission()
        }
    }

    static func anyEnabled(in defaults: UserDefaults) -> Bool {
        AppFeature.anyMonitorAlertEnabled(
            isAvailable: {
                defaults.bool(forKey: $0.availabilityKey)
                    && ($0 != .monitorPower || PowerSampler.hasInternalBattery)
            },
            boolFor: { defaults.bool(forKey: $0) }
        )
    }

    private func startSinkIfNeeded() {
        guard cancellables.isEmpty else { return }
        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.evaluate(snapshot)
            }
            .store(in: &cancellables)
    }

    private func stopSink() {
        cancellables.removeAll()
        cpuUsageGate.reset()
        cpuTemperatureGate.reset()
        batteryTemperatureGate.reset()
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        let defaults = UserDefaults.standard
        guard Self.anyEnabled(in: defaults) else {
            cpuUsageGate.reset()
            cpuTemperatureGate.reset()
            batteryTemperatureGate.reset()
            return
        }
        let strings = FeatureStrings.monitorAlerts(L10n.shared.language)

        func alertOn(_ key: String, _ feature: AppFeature) -> Bool {
            defaults.bool(forKey: key)
                && defaults.bool(forKey: feature.availabilityKey)
                && (feature != .monitorPower || PowerSampler.hasInternalBattery)
        }

        if alertOn(DefaultsKey.monitorAlertCPU, .monitorCPU) {
            evaluateCPU(snapshot, defaults: defaults, strings: strings)
        } else {
            cpuUsageGate.reset()
        }

        if alertOn(DefaultsKey.monitorAlertCPUTemperature, .monitorCPU) {
            evaluateCPUTemperature(snapshot, defaults: defaults, strings: strings)
        } else {
            cpuTemperatureGate.reset()
        }

        if alertOn(DefaultsKey.monitorAlertBatteryTemperature, .monitorPower) {
            evaluateBatteryTemperature(snapshot, defaults: defaults, strings: strings)
        } else {
            batteryTemperatureGate.reset()
        }

        if alertOn(DefaultsKey.monitorAlertMemory, .monitorMemory),
           snapshot.memoryPressure == .critical {
            send(.memory, title: strings.memoryTitle, body: strings.memoryBody)
        }

        if alertOn(DefaultsKey.monitorAlertDisk, .monitorDisk),
           let disk = diskAlert(from: snapshot, defaults: defaults, now: Date()) {
            let body = String(format: strings.diskBodyFormat, disk.name, disk.threshold)
            Notifier.post(title: strings.diskTitle, body: body)
        }

        if alertOn(DefaultsKey.monitorAlertBattery, .monitorPower),
           let battery = lowBattery(from: snapshot, defaults: defaults) {
            let body = String(format: strings.batteryBodyFormat, battery)
            send(.battery, title: strings.batteryTitle, body: body)
        }
    }

    private func evaluateCPU(_ snapshot: SystemSnapshot,
                             defaults: UserDefaults,
                             strings: MonitorAlertFeatureStrings) {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUThreshold),
                                                  fallback: 90,
                                                  range: 50...100)
        guard cpuUsageGate.shouldAlert(reading: snapshot.cpuUsage,
                                       threshold: Double(threshold) / 100.0,
                                       readAt: snapshot.cpuUsageReadAt) else { return }
        send(.cpu,
             title: strings.cpuTitle,
             body: String(format: strings.cpuBodyFormat, threshold))
    }

    private func diskAlert(from snapshot: SystemSnapshot, defaults: UserDefaults, now: Date)
        -> (name: String, threshold: Int)? {
        guard let disk = lowDisk(from: snapshot, defaults: defaults) else { return nil }
        if let previous = lastDiskAlert,
           now.timeIntervalSince(previous.sentAt) < 6 * 60 * 60,
           !(disk.isCritical && !previous.isCritical) {
            return nil
        }

        lastDiskAlert = (now, disk.isCritical)
        return (disk.name, disk.threshold)
    }

    private func lowDisk(from snapshot: SystemSnapshot, defaults: UserDefaults)
        -> (name: String, threshold: Int, isCritical: Bool)? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertDiskFreePercent),
                                                  fallback: 10,
                                                  range: 5...30)
        guard let devices = snapshot.disk?.devices else { return nil }
        var firstLowDisk: String?
        for device in devices where device.totalBytes >= 10_000_000_000 {
            let freePercent = Double(device.freeBytes) / Double(device.totalBytes) * 100.0
            if freePercent < Double(threshold) / 2 {
                return (device.name, threshold, true)
            }
            if freePercent < Double(threshold), firstLowDisk == nil {
                firstLowDisk = device.name
            }
        }
        guard let firstLowDisk else { return nil }
        return (firstLowDisk, threshold, false)
    }

    private func evaluateCPUTemperature(_ snapshot: SystemSnapshot,
                                        defaults: UserDefaults,
                                        strings: MonitorAlertFeatureStrings) {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUTemperatureThreshold),
                                                  fallback: 90,
                                                  range: 70...105)
        guard cpuTemperatureGate.shouldAlert(reading: snapshot.cpuTemperature,
                                             threshold: Double(threshold),
                                             readAt: snapshot.cpuTemperatureReadAt),
              let temperature = snapshot.cpuTemperature else { return }
        send(.cpuTemperature,
             title: strings.cpuTemperatureTitle,
             body: String(format: strings.cpuTemperatureBodyFormat,
                          Self.formattedTemperature(temperature, defaults: defaults)))
    }

    private func lowBattery(from snapshot: SystemSnapshot,
                            defaults: UserDefaults) -> Int? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertBatteryPercent),
                                                  fallback: 15,
                                                  range: 5...50)
        guard let power = snapshot.power,
              power.hasBattery,
              !power.isCharging,
              let charge = power.chargePercent,
              charge <= threshold else { return nil }
        return charge
    }

    private func evaluateBatteryTemperature(_ snapshot: SystemSnapshot,
                                            defaults: UserDefaults,
                                            strings: MonitorAlertFeatureStrings) {
        let threshold = Defaults.sanitizedPercent(
            defaults.integer(forKey: DefaultsKey.monitorAlertBatteryTemperatureThreshold),
            fallback: 40,
            range: 30...50
        )
        guard batteryTemperatureGate.shouldAlert(reading: snapshot.batteryTemperature,
                                                 threshold: Double(threshold),
                                                 readAt: snapshot.batteryTemperatureReadAt),
              let temperature = snapshot.batteryTemperature else { return }
        send(.batteryTemperature,
             title: strings.batteryTemperatureTitle,
             body: String(format: strings.batteryTemperatureBodyFormat,
                          Self.formattedTemperature(temperature, defaults: defaults)))
    }

    private static func formattedTemperature(_ celsius: Double, defaults: UserDefaults) -> String {
        let unit = TemperatureUnit(rawValue: defaults.string(forKey: DefaultsKey.temperatureUnit) ?? "") ?? .celsius
        return MetricFormat.temperature(celsius, unit: unit)
    }

    private func send(_ kind: MonitorAlertKind, title: String, body: String) {
        let now = Date()
        let minutes = Defaults.sanitizedMonitorAlertCooldown(
            UserDefaults.standard.integer(forKey: DefaultsKey.monitorAlertCooldownMinutes)
        )
        if let previous = lastSent[kind], now.timeIntervalSince(previous) < Double(minutes * 60) {
            return
        }
        lastSent[kind] = now
        Notifier.post(title: title, body: body)
    }
}

private enum MonitorAlertKind: Hashable {
    case cpu, cpuTemperature, memory, battery, batteryTemperature
}
