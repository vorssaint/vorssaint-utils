// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchAccessorySupport {
    static let lowThreshold = 20
    static let recoveryThreshold = 25
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.notchAccessories.isAvailable(in: defaults)
            && AppFeature.monitorPower.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchAccessoriesEnabled)
    }

    static func symbol(for kind: PeripheralBatteryKind, name: String) -> String {
        let kind = kind == .device
            ? PeripheralBatterySupport.kind(product: name, primaryUsagePage: nil, primaryUsage: nil, usagePairs: [])
            : kind
        switch kind {
        case .audio:
            let model = name.lowercased()
            if model.contains("airpods max") { return "airpodsmax" }
            if model.contains("airpods pro") { return "airpodspro" }
            if model.contains("airpods") { return "airpods" }
            return "headphones"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .device: return "dot.radiowaves.left.and.right"
        }
    }

    static func identity(_ device: PeripheralBatteryDevice) -> String {
        // The existing sampler coalesces the same physical accessory by name
        // when its reading moves between HID, system metadata and Bluetooth.
        device.kind.rawValue + ":" + device.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Missing telemetry is not a disconnection or a recharge. A low episode
/// survives both, until an actual reading reaches the recovery threshold.
struct NotchAccessoryBatteryState {
    private var lowEpisodes: [String: Bool] = [:]
    private var insertionOrder: [String] = []
    private var lastObservation: [String: TimeInterval] = [:]

    func isFresh(_ device: PeripheralBatteryDevice, in sample: PeripheralBatterySample,
                 observedAfter activation: TimeInterval) -> Bool {
        let key = NotchAccessorySupport.identity(device)
        guard (0...100).contains(device.percent), let observedAt = sample.observedAt[device.id],
              observedAt.isFinite else { return false }
        return observedAt >= activation && observedAt > (lastObservation[key] ?? -.greatestFiniteMagnitude)
    }

    mutating func consume(_ sample: PeripheralBatterySample, observedAfter activation: TimeInterval) -> [PeripheralBatteryDevice] {
        let fresh = sample.devices.filter { isFresh($0, in: sample, observedAfter: activation) }
        for device in fresh {
            lastObservation[NotchAccessorySupport.identity(device)] = sample.observedAt[device.id]
        }
        return consume(fresh)
    }

    mutating func consume(_ devices: [PeripheralBatteryDevice]) -> [PeripheralBatteryDevice] {
        var alerts: [PeripheralBatteryDevice] = []
        for device in devices where (0...100).contains(device.percent) {
            let key = NotchAccessorySupport.identity(device)
            guard let low = lowEpisodes[key] else {
                lowEpisodes[key] = device.percent <= NotchAccessorySupport.lowThreshold
                insertionOrder.append(key)
                if insertionOrder.count > 128 {
                    let oldest = insertionOrder.removeFirst()
                    lowEpisodes.removeValue(forKey: oldest)
                    lastObservation.removeValue(forKey: oldest)
                }
                continue
            }
            if device.percent >= NotchAccessorySupport.recoveryThreshold {
                lowEpisodes[key] = false
            } else if device.percent <= NotchAccessorySupport.lowThreshold, !low {
                lowEpisodes[key] = true
                alerts.append(device)
            }
        }
        return PeripheralBatterySupport.sorted(alerts)
    }
}

struct NotchAccessoryConnectionState {
    private var connectedIDs: Set<String> = []
    mutating func establishBaseline(_ ids: Set<String>) { connectedIDs = ids }
    mutating func connected(_ id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return connectedIDs.insert(id).inserted
    }
    mutating func disconnected(_ id: String) { connectedIDs.remove(id) }
}
