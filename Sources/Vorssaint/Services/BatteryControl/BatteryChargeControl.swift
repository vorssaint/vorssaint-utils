// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// All charging control for one backend, settled as `apply` plus one
/// verification read per written key. Half-applied states (a key written,
/// its twin refused) are treated as a control failure: the caller restores
/// instead of assuming.
enum BatteryChargeControl {

    /// Cases run from mildest to worst: `max` keeps the later one.
    enum ErrorKind: String, Codable, Sendable, CaseIterable {
        case none
        case unverifiable
        /// The platform resists the write, e.g. the firmware gates charge
        /// keys behind an Apple-private entitlement: reads work and writes
        /// answer `kIOReturnNotPrivileged`.
        case refused
        case unsupported
    }

    static func probe(bridge: AppleSMCBatteryBridge) -> Probe {
        var result = Probe()
        for name in ["CH0B", "CH0C", "CHTE",
                     "CH0I", "CH0J", "CHIE"] {
            if let size = bridge.keySize(of: name) { result.keySizes[name] = size }
        }
        return result
    }

    // MARK: Legacy direct charging (CH0B/CH0C, CHTE on newer firmware)

    static func isLegacyChargingEnabled(_ bridge: AppleSMCBatteryBridge,
                                        _ probe: Probe) -> Bool? {
        if probe.has("CH0B", size: 1) && probe.has("CH0C", size: 1) {
            guard let bytes = bridge.read("CH0B") else { return nil }
            // 0x00 charges; 0x02 keeps the charge stopped.
            return bytes.count == 1 && bytes[0] == 0x00
        }
        if probe.has("CHTE", size: 4) {
            guard let bytes = bridge.read("CHTE") else { return nil }
            return bytes.count == 4 && bytes == [0x00, 0x00, 0x00, 0x00]
        }
        return nil
    }

    static func legacySetCharging(_ bridge: AppleSMCBatteryBridge,
                                  _ probe: Probe, _ enabled: Bool) -> ErrorKind {
        if probe.has("CH0B", size: 1) && probe.has("CH0C", size: 1) {
            let value: [UInt8] = enabled ? [0x00] : [0x02]
            guard bridge.write("CH0B", bytes: value) else { return .refused }
            guard bridge.write("CH0C", bytes: value) else { return .refused }
            guard bridge.read("CH0B") == value else { return .unverifiable }
            return bridge.read("CH0C") == value ? .none : .unverifiable
        }
        if probe.has("CHTE", size: 4) {
            let value: [UInt8] = enabled ? [0x00, 0x00, 0x00, 0x00]
                                         : [0x01, 0x00, 0x00, 0x00]
            guard bridge.write("CHTE", bytes: value) else { return .refused }
            return bridge.read("CHTE") == value ? .none : .unverifiable
        }
        return .unsupported
    }

    // MARK: Adapter (wall power) control

    /// `true` means wall power reaching the Mac. `CHIE` on Tahoe-family
    /// firmware encodes its disabled state as `0x8`, not `0x1`.
    static func adapterEnabled(_ bridge: AppleSMCBatteryBridge,
                               _ probe: Probe) -> Bool? {
        guard let name = probe.adapterKeyName, let bytes = bridge.read(name),
              bytes.count == 1 else { return nil }
        return bytes[0] == 0x00
    }

    static func adapterSet(_ bridge: AppleSMCBatteryBridge,
                           _ probe: Probe, _ enabled: Bool) -> ErrorKind {
        guard let name = probe.adapterKeyName else { return .unsupported }
        let value: [UInt8]
        if name == "CHIE" {
            value = enabled ? [0x00] : [0x08]
        } else {
            value = enabled ? [0x00] : [0x01]
        }
        guard bridge.write(name, bytes: value) else { return .refused }
        return bridge.read(name) == value ? .none : .unverifiable
    }

    /// Puts charging back the way macOS found it: charge allowed, wall
    /// power connected, firmware limits off.
    static func restoreSafe(_ bridge: AppleSMCBatteryBridge, _ probe: Probe) -> ErrorKind {
        var worst = ErrorKind.none
        switch probe.backend {
        case .legacy:
            let result = legacySetCharging(bridge, probe, true)
            worst = max(worst, result)
        case .unsupported:
            return .unsupported
        }
        if let adapter = adapterEnabled(bridge, probe), !adapter {
            worst = max(worst, adapterSet(bridge, probe, true))
        }
        return worst
    }

    static func max(_ a: ErrorKind, _ b: ErrorKind) -> ErrorKind {
        let order = ErrorKind.allCases
        return order.firstIndex(of: a)! >= order.firstIndex(of: b)! ? a : b
    }
}
