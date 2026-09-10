// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// Live controller flags, independent of AppleSmartBattery's cached telemetry.
/// Unknown keys/read failures remain nil so unsupported Macs use system data.
struct BatteryPowerState: Equatable {
    var adapterConnected: Bool?
    var isCharging: Bool?
    var isDischarging: Bool?

    static func adapterConnected(bytes: [UInt8]?) -> Bool? {
        guard let bytes, bytes.count == 1 else { return nil }
        let port = Int8(bitPattern: bytes[0])
        guard port >= -1 else { return nil }
        return port >= 0
    }

    static func flag(bytes: [UInt8]?, enabledValue: UInt8 = 1) -> Bool? {
        guard let bytes, bytes.count == 1 else { return nil }
        if bytes[0] == 0 { return false }
        return bytes[0] == enabledValue ? true : nil
    }

    func resolve(externalConnected: Bool, isCharging: Bool) -> (externalConnected: Bool, isCharging: Bool) {
        // Forced discharge leaves the physical cable/data link connected,
        // but the Mac is powered by its battery during that mode.
        let connected = adapterConnected.map { $0 && isDischarging != true } ?? externalConnected
        return (connected, connected && (self.isCharging ?? isCharging))
    }
}
