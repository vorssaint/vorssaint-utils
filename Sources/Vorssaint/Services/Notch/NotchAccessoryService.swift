// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import IOBluetooth

/// The system monitor remains the only battery sampler. Native connection
/// notifications report an actual connection, independently of missing readings.
final class NotchAccessoryService: NSObject {
    static let shared = NotchAccessoryService()
    private var subscription: AnyCancellable?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var batteryState = NotchAccessoryBatteryState()
    private var connectionState = NotchAccessoryConnectionState()
    private var active = false
    private var activationTime: TimeInterval = 0
    private var generation = UUID()
    private var pending: [(notice: NotchNotice, expiresAt: Date)] = []
    private var noticeWork: DispatchWorkItem?
    private override init() { super.init() }

    func syncWithPreferences() {
        guard NotchAccessorySupport.isEnabled() else { stop(); return }
        guard !active else { return }
        active = true
        activationTime = ProcessInfo.processInfo.systemUptime
        generation = UUID()
        let currentGeneration = generation
        // The baseline is silent, including devices that were already low
        // before the user enabled this feature. Connection baselines are
        // rebuilt silently after lock/sleep; battery episodes survive both.
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }
        connectionState.establishBaseline(Set(devices.compactMap { $0.addressString }))
        devices.forEach(observeDisconnect)
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:)))
        subscription = SystemMonitor.shared.$snapshot.map(\.peripheralBatterySample)
            .removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] sample in
                guard let self, self.active, self.generation == currentGeneration,
                      NotchAccessorySupport.isEnabled() else { return }
                self.pending.removeAll { queued in
                    queued.notice.level != nil && sample.devices.contains { device in
                        self.batteryState.isFresh(device, in: sample, observedAfter: self.activationTime)
                            && device.name == queued.notice.title
                            && device.percent >= NotchAccessorySupport.recoveryThreshold
                    }
                }
                let text = FeatureStrings.notchActivities(L10n.shared.language)
                for device in self.batteryState.consume(sample, observedAfter: self.activationTime) {
                    self.enqueue(NotchNotice(event: .accessory, title: device.name,
                        detail: text.lowBattery + " · \(device.percent)%",
                        symbol: NotchAccessorySupport.symbol(for: device.kind, name: device.name),
                        level: Double(device.percent) / 100))
                }
            }
        SystemMonitor.shared.setNotchAccessoryMonitoring(true)
    }

    func stop() {
        batteryState = NotchAccessoryBatteryState()
        connectionState = NotchAccessoryConnectionState()
        suspend()
    }

    func suspend() {
        guard active else { return }
        active = false
        generation = UUID()
        subscription = nil
        connectNotification?.unregister(); connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        noticeWork?.cancel(); noticeWork = nil
        pending.removeAll()
        SystemMonitor.shared.setNotchAccessoryMonitoring(false)
    }

    private func observeDisconnect(_ device: IOBluetoothDevice) {
        guard let id = device.addressString, disconnectNotifications[id] == nil else { return }
        disconnectNotifications[id] = device.register(forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:)))
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, NotchAccessorySupport.isEnabled(), device.isConnected(),
                  let id = device.addressString, self.connectionState.connected(id) else { return }
            self.observeDisconnect(device)
            guard let name = device.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            let text = FeatureStrings.notchActivities(L10n.shared.language)
            let kind = PeripheralBatterySupport.kind(product: name,
                primaryUsagePage: nil, primaryUsage: nil, usagePairs: [])
            self.enqueue(NotchNotice(event: .accessory, title: name,
                detail: text.connected, symbol: NotchAccessorySupport.symbol(for: kind, name: name)))
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.active, !device.isConnected(), let id = device.addressString else { return }
            self.connectionState.disconnected(id)
            if let name = device.name { self.pending.removeAll { $0.notice.title == name } }
            self.disconnectNotifications.removeValue(forKey: id)?.unregister()
        }
    }

    private func enqueue(_ notice: NotchNotice) {
        if pending.count >= 8 { pending.removeFirst() }
        pending.append((notice, Date().addingTimeInterval(30)))
        if noticeWork == nil { presentNext() }
    }

    private func presentNext() {
        noticeWork = nil
        pending.removeAll { $0.expiresAt <= Date() }
        guard active, NotchAccessorySupport.isEnabled(), let first = pending.first else { return }
        let notch = NotchService.shared
        if !notch.expanded, notch.captureControls == nil, notch.show(first.notice) { pending.removeFirst() }
        let work = DispatchWorkItem { [weak self] in self?.presentNext() }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchEvent.accessory.duration + 0.1, execute: work)
    }
}
