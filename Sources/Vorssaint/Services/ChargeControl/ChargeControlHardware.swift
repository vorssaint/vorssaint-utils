// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Discovers the charging-control SMC keys this Mac actually exposes and writes
/// only those keys. Apple Silicon generations differ (CH0B/CH0C vs CHTE, CH0I
/// vs CHIE); Intel uses BCLM plus optional ACEN for a forced discharge.
final class ChargeControlHardware {
    private struct ChargePath {
        let family: ChargeControlFamily
        let enable: [(key: SMCClient.Key, bytes: [UInt8])]
        let inhibit: [(key: SMCClient.Key, bytes: [UInt8])]
    }

    private struct DischargePath {
        let on: [(key: SMCClient.Key, bytes: [UInt8])]
        let off: [(key: SMCClient.Key, bytes: [UInt8])]
    }

    private let client: SMCClient
    private let chargePath: ChargePath
    private let dischargePath: DischargePath?
    private let bclm: SMCClient.Key?
    let profile: ChargeControlHardwareProfile

    init?() {
        guard let client = SMCClient() else { return nil }
        self.client = client

        let ch0b = Self.namedKey("CH0B", in: client)
        let ch0c = Self.namedKey("CH0C", in: client)
        let chte = Self.namedKey("CHTE", in: client)
        let ch0i = Self.namedKey("CH0I", in: client)
        let chie = Self.namedKey("CHIE", in: client)
        let bclmKey = Self.namedKey("BCLM", in: client)
        let acen = Self.namedKey("ACEN", in: client)
        self.bclm = bclmKey.flatMap { $0.dataSize == 1 ? $0 : nil }

        if self.bclm != nil {
            chargePath = ChargePath(family: .intelBCLM, enable: [], inhibit: [])
            if let acen {
                dischargePath = DischargePath(on: [(acen, [0x00])], off: [(acen, [0x01])])
            } else {
                dischargePath = nil
            }
            _ = (ch0b, ch0c, chte, ch0i, chie)
        } else if let chte {
            chargePath = ChargePath(
                family: .appleSiliconCHT,
                enable: [(chte, ChargeControlPolicy.paddedSMCBytes([0x00, 0x00, 0x00, 0x00], to: chte.dataSize))],
                inhibit: [(chte, ChargeControlPolicy.paddedSMCBytes([0x01, 0x00, 0x00, 0x00], to: chte.dataSize))])
            dischargePath = Self.appleSiliconDischarge(key: chie, enabledByte: 0x08)
            _ = (ch0b, ch0c)
        } else if ch0b != nil || ch0c != nil {
            var enable: [(key: SMCClient.Key, bytes: [UInt8])] = []
            var inhibit: [(key: SMCClient.Key, bytes: [UInt8])] = []
            // CH0B on M1 uses 0x02 to inhibit; later CH0C firmware uses 0x01.
            if let ch0b {
                enable.append((ch0b, ChargeControlPolicy.paddedSMCBytes([0x00], to: ch0b.dataSize)))
                inhibit.append((ch0b, ChargeControlPolicy.paddedSMCBytes([0x02], to: ch0b.dataSize)))
            }
            if let ch0c {
                enable.append((ch0c, ChargeControlPolicy.paddedSMCBytes([0x00], to: ch0c.dataSize)))
                inhibit.append((ch0c, ChargeControlPolicy.paddedSMCBytes([0x01], to: ch0c.dataSize)))
            }
            chargePath = ChargePath(family: .appleSiliconCH0, enable: enable, inhibit: inhibit)
            dischargePath = Self.appleSiliconDischarge(key: ch0i, enabledByte: 0x01)
        } else if let chie, chie.dataSize == 1 {
            // New firmware gates charge inhibition, but still permits adapter
            // control. The app must enforce its limit through PowerUI first.
            chargePath = ChargePath(family: .nativePowerUI, enable: [], inhibit: [])
            dischargePath = Self.appleSiliconDischarge(key: chie, enabledByte: 0x08)
        } else {
            return nil
        }

        profile = ChargeControlHardwareProfile(
            family: chargePath.family,
            supportsInhibit: chargePath.family != .nativePowerUI,
            supportsDischarge: dischargePath != nil)
    }

    func apply(gate: ChargeControlGate, limit: Int) -> Bool {
        let cap = ChargeControlPolicy.sanitizedLimit(limit)
        if chargePath.family == .nativePowerUI {
            // Never claim the helper inhibited charging: it only owns CHIE.
            guard gate != .inhibitCharging else { return false }
            return setDischarge(gate == .forceDischarge)
        }
        switch gate {
        case .allowCharging:
            return setDischarge(false) && setChargingEnabled(true, limit: cap)
        case .inhibitCharging:
            return setDischarge(false) && setChargingEnabled(false, limit: cap)
        case .forceDischarge:
            guard profile.supportsDischarge else { return false }
            return setDischarge(true) && setChargingEnabled(false, limit: cap)
        }
    }

    func restoreNormal() -> Bool {
        setDischarge(false) && setChargingEnabled(true, limit: ChargeControlPolicy.maximumLimit)
    }

    var isForceDischarging: Bool {
        guard let dischargePath else { return false }
        return dischargePath.on.contains { pair in
            client.readBytes(pair.key) == pair.bytes
        }
    }

    private func setChargingEnabled(_ enabled: Bool, limit: Int) -> Bool {
        if let bclm {
            let value = UInt8(enabled ? ChargeControlPolicy.maximumLimit : limit)
            return write(bclm, bytes: [value])
        }
        let pairs = enabled ? chargePath.enable : chargePath.inhibit
        return writeAll(pairs)
    }

    private func setDischarge(_ enabled: Bool) -> Bool {
        guard let dischargePath else { return !enabled }
        return writeAll(enabled ? dischargePath.on : dischargePath.off)
    }

    private func writeAll(_ pairs: [(key: SMCClient.Key, bytes: [UInt8])]) -> Bool {
        guard !pairs.isEmpty else { return true }
        var allSucceeded = true
        for pair in pairs {
            if !write(pair.key, bytes: pair.bytes) { allSucceeded = false }
        }
        return allSucceeded
    }

    private func write(_ key: SMCClient.Key, bytes: [UInt8], attempts: Int = 3) -> Bool {
        let payload = ChargeControlPolicy.paddedSMCBytes(bytes, to: key.dataSize)
        // Writing an unchanged adapter/discharge flag can still cause a power
        // renegotiation. Only touch the controller when the value must change.
        if client.readBytes(key) == payload { return true }
        for attempt in 0..<attempts {
            do {
                try client.writeBytes(payload, to: key)
                if client.readBytes(key) == payload { return true }
            } catch {
                if attempt + 1 == attempts { return false }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    private static func appleSiliconDischarge(key: SMCClient.Key?, enabledByte: UInt8) -> DischargePath? {
        guard let key else { return nil }
        return DischargePath(
            on: [(key, ChargeControlPolicy.paddedSMCBytes([enabledByte], to: key.dataSize))],
            off: [(key, ChargeControlPolicy.paddedSMCBytes([0x00], to: key.dataSize))])
    }

    private static func namedKey(_ name: String, in client: SMCClient) -> SMCClient.Key? {
        guard let key = client.key(named: name), key.dataSize > 0, key.dataSize <= 32 else { return nil }
        return key
    }
}
