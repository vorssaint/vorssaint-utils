// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit.ps
import os

/// The real bridge: the app's shared AppleSMC user client plus the system
/// power sources. Compiled only where the hardware is actually touched.
private let batteryTypeKey = "BatteryType"

/// Read-only hardware capability, safe to call from anywhere: a handful of
/// SMC key queries, no writes, no approval. The catalog and the settings card
/// both read it before a helper ever exists. App-side only: the helper runs
/// its own probe each launch.
enum BatteryControlHardwareProbe {
    static let backend: BatteryControlCore.Backend = {
        let log = Logger(subsystem: FanControlIdentifiers.helperID,
                         category: "probe")
        guard let bridge = AppleSMCBatteryBridge() else {
            log.fault("probe: AppleSMC bridge unavailable in this process")
            return .unsupported
        }
        let backend = BatteryChargeControl.probe(bridge: bridge).backend
        log.notice("probe: backend \(backend.rawValue, privacy: .public)")
        return backend
    }()

    static var isSupported: Bool { backend != .unsupported }
}

final class AppleSMCBatteryBridge {
    private let client: SMCClient
    /// Confirmed keys, as the SMC itself reported them. The key's four-char
    /// code travels with it: a hand-built key with `code: 0` addresses
    /// nothing, so every read answered `nil` and every write was refused.
    private var keyCache: [String: SMCClient.Key] = [:]

    init?() {
        guard let client = SMCClient() else { return nil }
        self.client = client
    }

    func keySize(of name: String) -> Int? {
        resolve(name).map { Int($0.dataSize) }
    }

    /// Absences are never cached: a key list read that raced another
    /// AppleSMC session would otherwise pin "no control" for the daemon's
    /// whole lifetime. Only confirmed keys (with a real size) are sticky.
    private func resolve(_ name: String) -> SMCClient.Key? {
        if let cached = keyCache[name] { return cached }
        guard let key = client.key(named: name), key.dataSize > 0 else { return nil }
        keyCache[name] = key
        return key
    }

    func read(_ name: String) -> [UInt8]? {
        guard let key = resolve(name) else { return nil }
        return client.readBytes(key)
    }

    func write(_ name: String, bytes: [UInt8]) -> Bool {
        guard let key = resolve(name), bytes.count == Int(key.dataSize) else {
            return false
        }
        do {
            try client.writeBytes(bytes, to: key)
            return true
        } catch {
            return false
        }
    }

    var batteryPercentage: Int? {
        Self.internalBatteries().compactMap { $0[kIOPSCurrentCapacityKey] as? Int }.last
    }

    var isCharging: Bool {
        Self.internalBatteries().compactMap { $0[kIOPSIsChargingKey] as? Bool }.first ?? false
    }

    /// One entry per internal battery. The list can sit empty for a moment
    /// around wake; the helpers above answer `nil`/`false` and the caller's
    /// tick simply retries.
    private static func internalBatteries() -> [[String: Any]] {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [AnyObject]
        return sources.compactMap {
            IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue()
                as? [String: Any]
        }.filter {
            ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
        }
    }
}
