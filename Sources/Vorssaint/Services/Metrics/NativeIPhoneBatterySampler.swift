// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NativeIPhoneBattery: Identifiable, Equatable {
    let id: String
    let name: String
    let percent: Int?
    let charging: Bool?
}

/// Reads paired iPhones directly through the bundled libimobiledevice tools.
/// AirBattery itself is not queried or required at runtime.
final class NativeIPhoneBatterySampler {
    private let interval: TimeInterval = 30
    private let deviceRetentionInterval: TimeInterval = 10 * 60
    private var lastRead = -Double.infinity
    private var cached: [NativeIPhoneBattery] = []
    private var lastSeenAt: [String: TimeInterval] = [:]

    func sampleIfDue(now: TimeInterval) -> (devices: [NativeIPhoneBattery], sampled: Bool) {
        guard now - lastRead >= interval else { return (cached, false) }
        lastRead = now
        guard let resources = Bundle.main.resourceURL else {
            expireMissingDevices(now: now)
            return (cached, true)
        }
        let bin = resources.appendingPathComponent("iOSDevice/libimobiledevice/bin")
        let idTool = bin.appendingPathComponent("idevice_id").path
        let usb = Shell.run(idTool, ["-l"], timeout: 8)
        let network = Shell.run(idTool, ["-n"], timeout: 8)
        func ids(_ output: String) -> (values: [String], succeeded: Bool) {
            let lines = output.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let failed = lines.contains { $0.hasPrefix("ERROR:") }
            return (lines.filter { !$0.isEmpty && !$0.hasPrefix("ERROR:") }, !failed)
        }
        let usbIDs = ids(usb.output)
        let networkIDs = ids(network.output)
        let usbSucceeded = usb.status == 0 && usbIDs.succeeded
        let networkSucceeded = network.status == 0 && networkIDs.succeeded
        guard usbSucceeded || networkSucceeded else {
            expireMissingDevices(now: now)
            return (cached, true)
        }

        var transports = Dictionary(uniqueKeysWithValues: (networkSucceeded ? networkIDs.values : []).map { ($0, true) })
        // Prefer USB when a phone appears in both results.
        for id in (usbSucceeded ? usbIDs.values : []) { transports[id] = false }
        let infoTool = bin.appendingPathComponent("ideviceinfo").path
        let wifiTool = bin.appendingPathComponent("wificonnection").path
        var refreshed: [String: NativeIPhoneBattery] = [:]
        for (id, isNetwork) in transports {
            if !isNetwork { _ = Shell.run(wifiTool, ["-u", id, "true"], timeout: 8) }
            let transportArgs = isNetwork ? ["-n", "-u", id] : ["-u", id]
            let general = Shell.run(infoTool, transportArgs, timeout: 8)
            guard general.status == 0 else { continue }
            let fields = Self.fields(general.output)
            guard fields["DeviceClass"] == "iPhone", let name = fields["DeviceName"] else { continue }
            let battery = Shell.run(infoTool, transportArgs + ["-q", "com.apple.mobile.battery"], timeout: 8)
            let values = Self.fields(battery.output)
            let old = cached.first { $0.id == id }
            let reportedPercent = battery.status == 0
                ? Int(values["BatteryCurrentCapacity"] ?? "").flatMap { (0...100).contains($0) ? $0 : nil }
                : nil
            let reportedCharging = battery.status == 0
                ? Self.boolValue(values["BatteryIsCharging"])
                : nil
            refreshed[id] = NativeIPhoneBattery(id: id, name: name,
                                                percent: reportedPercent ?? old?.percent,
                                                charging: reportedCharging ?? old?.charging)
            lastSeenAt[id] = now
        }

        // Keep last-known readings through temporary discovery misses, but
        // expire them ten minutes after the last successful device read.
        for old in cached where refreshed[old.id] == nil {
            if now - (lastSeenAt[old.id] ?? now) <= deviceRetentionInterval {
                refreshed[old.id] = old
            } else {
                lastSeenAt.removeValue(forKey: old.id)
            }
        }

        cached = refreshed.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return (cached, true)
    }

    private func expireMissingDevices(now: TimeInterval) {
        cached.removeAll { device in
            guard let lastSeen = lastSeenAt[device.id], now - lastSeen > deviceRetentionInterval else {
                return false
            }
            lastSeenAt.removeValue(forKey: device.id)
            return true
        }
    }

    private static func fields(_ output: String) -> [String: String] {
        Dictionary(output.components(separatedBy: .newlines).compactMap { line -> (String, String)? in
            guard let split = line.range(of: ": ") else { return nil }
            return (String(line[..<split.lowerBound]), String(line[split.upperBound...]))
        }, uniquingKeysWith: { _, last in last })
    }

    private static func boolValue(_ value: String?) -> Bool? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        switch value {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }
}
