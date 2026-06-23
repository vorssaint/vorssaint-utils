// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Optional Monitor notifications. Everything is off by default, throttled, and
/// driven by the existing SystemMonitor sampler.
final class MonitorAlertService {
    static let shared = MonitorAlertService()

    private var cancellables = Set<AnyCancellable>()
    private var defaultsObserver: NSObjectProtocol?
    private var started = false
    private var highCPUSince: Date?
    private var lastSent: [MonitorAlertKind: Date] = [:]

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        syncWithPreferences()

        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.evaluate(snapshot)
            }
            .store(in: &cancellables)

        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let enabled = Self.anyEnabled(in: .standard)
        SystemMonitor.shared.setAlertsActive(enabled)
        if enabled {
            Notifier.requestPermission()
        }
    }

    static func anyEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: DefaultsKey.monitorAlertCPU)
            || defaults.bool(forKey: DefaultsKey.monitorAlertCPUTemperature)
            || defaults.bool(forKey: DefaultsKey.monitorAlertMemory)
            || defaults.bool(forKey: DefaultsKey.monitorAlertDisk)
            || defaults.bool(forKey: DefaultsKey.monitorAlertBattery)
    }

    private func evaluate(_ snapshot: SystemSnapshot) {
        let defaults = UserDefaults.standard
        guard Self.anyEnabled(in: defaults) else {
            highCPUSince = nil
            return
        }
        let strings = FeatureStrings.monitorAlerts(L10n.shared.language)

        if defaults.bool(forKey: DefaultsKey.monitorAlertCPU) {
            evaluateCPU(snapshot.cpuUsage, defaults: defaults, strings: strings)
        } else {
            highCPUSince = nil
        }

        if defaults.bool(forKey: DefaultsKey.monitorAlertCPUTemperature),
           let temperature = highCPUTemperature(from: snapshot, defaults: defaults) {
            send(.cpuTemperature,
                 title: strings.cpuTemperatureTitle,
                 body: String(format: strings.cpuTemperatureBodyFormat, temperature))
        }

        if defaults.bool(forKey: DefaultsKey.monitorAlertMemory),
           snapshot.memoryPressure == .critical {
            send(.memory, title: strings.memoryTitle, body: strings.memoryBody)
        }

        if defaults.bool(forKey: DefaultsKey.monitorAlertDisk),
           let disk = lowDisk(from: snapshot, defaults: defaults) {
            let body = String(format: strings.diskBodyFormat, disk.name, disk.threshold)
            send(.disk, title: strings.diskTitle, body: body)
        }

        if defaults.bool(forKey: DefaultsKey.monitorAlertBattery),
           let battery = lowBattery(from: snapshot, defaults: defaults) {
            let body = String(format: strings.batteryBodyFormat, battery)
            send(.battery, title: strings.batteryTitle, body: body)
        }
    }

    private func evaluateCPU(_ usage: Double?,
                             defaults: UserDefaults,
                             strings: MonitorAlertFeatureStrings) {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUThreshold),
                                                  fallback: 90,
                                                  range: 50...100)
        guard let usage, usage >= Double(threshold) / 100.0 else {
            highCPUSince = nil
            return
        }

        let now = Date()
        if highCPUSince == nil {
            highCPUSince = now
            return
        }
        guard let since = highCPUSince, now.timeIntervalSince(since) >= 12 else { return }
        send(.cpu,
             title: strings.cpuTitle,
             body: String(format: strings.cpuBodyFormat, threshold))
    }

    private func lowDisk(from snapshot: SystemSnapshot,
                         defaults: UserDefaults) -> (name: String, threshold: Int)? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertDiskFreePercent),
                                                  fallback: 10,
                                                  range: 5...30)
        guard let device = snapshot.disk?.devices.first(where: { device in
            guard device.totalBytes >= 10_000_000_000 else { return false }
            let freePercent = Double(device.freeBytes) / Double(device.totalBytes) * 100.0
            return freePercent < Double(threshold)
        }) else { return nil }
        return (device.name, threshold)
    }

    private func highCPUTemperature(from snapshot: SystemSnapshot,
                                    defaults: UserDefaults) -> Int? {
        let threshold = Defaults.sanitizedPercent(defaults.integer(forKey: DefaultsKey.monitorAlertCPUTemperatureThreshold),
                                                  fallback: 90,
                                                  range: 70...105)
        guard let temperature = snapshot.cpuTemperature,
              temperature >= Double(threshold) else { return nil }
        return Int(temperature.rounded())
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
    case cpu, cpuTemperature, memory, disk, battery
}
