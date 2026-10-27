// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// The system monitor remains the only battery sampler. Native connection
/// notifications report an actual connection, independently of missing readings.
final class NotchAccessoryService: NSObject {
    static let shared = NotchAccessoryService()
    private var subscription: AnyCancellable?
    private let connectionMonitor = NotchAccessoryConnectionMonitor()
    private var batteryState = NotchAccessoryBatteryState()
    private var active = false
    private var activationTime: TimeInterval = 0
    private var generation = UUID()
    private var pending: [(notice: NotchNotice, device: String, expiresAt: Date)] = []
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
        connectionMonitor.start { [weak self] event in
            guard let self, self.active, self.generation == currentGeneration,
                  NotchAccessorySupport.isEnabled() else { return }
            self.handleConnection(event)
        }
        subscription = SystemMonitor.shared.$snapshot.map(\.peripheralBatterySample)
            .removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] sample in
                guard let self, self.active, self.generation == currentGeneration,
                      NotchAccessorySupport.isEnabled() else { return }
                self.pending.removeAll { queued in
                    queued.notice.level != nil && sample.devices.contains { device in
                        self.batteryState.isFresh(device, in: sample, observedAfter: self.activationTime)
                            && device.name == queued.device
                            && device.percent >= NotchAccessorySupport.recoveryThreshold
                    }
                }
                let text = FeatureStrings.notchActivities(L10n.shared.language)
                for device in self.batteryState.consume(sample, observedAfter: self.activationTime) {
                    self.enqueue(NotchNotice(event: .accessory, title: device.name,
                        detail: text.lowBattery + " · \(device.percent)%",
                        symbol: NotchAccessorySupport.symbol(for: device.kind, name: device.name),
                        level: Double(device.percent) / 100), device: device.name)
                }
            }
        SystemMonitor.shared.setNotchAccessoryMonitoring(true)
    }

    func stop() {
        batteryState = NotchAccessoryBatteryState()
        suspend()
    }

    func suspend() {
        guard active else { return }
        active = false
        generation = UUID()
        subscription = nil
        connectionMonitor.stop()
        noticeWork?.cancel(); noticeWork = nil
        pending.removeAll()
        SystemMonitor.shared.setNotchAccessoryMonitoring(false)
    }

    private func handleConnection(_ event: NotchAccessoryConnectionEvent) {
        switch event {
        case let .connected(name, majorClass, minorClass):
            let text = FeatureStrings.notchActivities(L10n.shared.language)
            // The status stays short beside its icon, so the name gets a
            // whole wing to itself before it has to be shortened.
            self.enqueue(NotchNotice(event: .accessory, title: text.connected, detail: name,
                symbol: NotchAccessorySupport.symbol(name: name, majorClass: majorClass, minorClass: minorClass)),
                         device: name)
        case let .disconnected(name):
            if let name { pending.removeAll { $0.device == name } }
        }
    }

    private func enqueue(_ notice: NotchNotice, device: String) {
        if pending.count >= 8 { pending.removeFirst() }
        pending.append((notice, device, Date().addingTimeInterval(30)))
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
