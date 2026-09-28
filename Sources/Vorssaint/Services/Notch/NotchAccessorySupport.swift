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

    /// A name says what an accessory is only until someone renames it. The
    /// Bluetooth class of device it announces still does, from a phone or a
    /// speaker down to the trackpad that sets a pointer's digitizer bits.
    /// Major and minor classes as the Bluetooth assigned numbers define them.
    static func symbol(name: String, majorClass: UInt32, minorClass: UInt32) -> String {
        let named = PeripheralBatterySupport.kind(product: name, primaryUsagePage: nil, primaryUsage: nil, usagePairs: [])
        guard named == .device else { return symbol(for: named, name: name) }
        switch (majorClass, minorClass) {
        case (0x01, 0x03): return "laptopcomputer"
        case (0x01, 0x04), (0x01, 0x05): return "ipad"
        case (0x01, 0x06): return "applewatch"
        case (0x01, _): return "desktopcomputer"
        case (0x02, _): return "iphone"
        case (0x04, 0x04): return "mic"
        case (0x04, 0x05), (0x04, 0x07), (0x04, 0x0A): return "hifispeaker"
        case (0x04, 0x08): return "car"
        case (0x04, 0x0E), (0x04, 0x0F): return "tv"
        case (0x04, 0x12): return "gamecontroller"
        case (0x04, 0x01), (0x04, 0x02), (0x04, 0x06): return symbol(for: .audio, name: name)
        case (0x05, let minor) where [0x01, 0x02].contains(minor & 0x0F): return "gamecontroller"
        case (0x05, let minor) where minor & 0x0F == 0x03: return "av.remote"
        case (0x05, let minor) where minor & 0x30 == 0x20:
            return minor & 0x0F == 0x05 ? symbol(for: .trackpad, name: name) : symbol(for: .mouse, name: name)
        case (0x05, let minor) where minor & 0x10 != 0: return symbol(for: .keyboard, name: name)
        case (0x06, let minor) where minor & 0x20 != 0: return "printer"
        case (0x07, 0x01): return "applewatch"
        case (0x07, 0x05): return "eyeglasses"
        case (0x08, _): return "gamecontroller"
        default: return symbol(for: .device, name: name)
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
