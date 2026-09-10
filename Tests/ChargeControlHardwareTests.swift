// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Compile this test with the real ChargeControlHardware/Support, without the
/// real SMCClient. These checks never open the controller or change hardware.
final class SMCClient {
    struct Key {
        let name: String
        let dataSize: UInt32
    }

    static var values: [String: [UInt8]] = [:]
    static var writes: [(String, [UInt8])] = []
    static var failingKey: String?

    init?() {}

    func key(named name: String) -> Key? {
        Self.values[name].map { Key(name: name, dataSize: UInt32($0.count)) }
    }

    func readBytes(_ key: Key) -> [UInt8]? { Self.values[key.name] }

    func writeBytes(_ bytes: [UInt8], to key: Key) throws {
        if key.name == Self.failingKey { throw CocoaError(.fileWriteUnknown) }
        Self.writes.append((key.name, bytes))
        Self.values[key.name] = bytes
    }
}

@main
enum ChargeControlHardwareTests {
    static func main() {
        SMCClient.values = ["CHTE": [0, 0, 0, 0], "CHIE": [0], "CH0I": [0]]
        guard let hardware = ChargeControlHardware() else { fatalError("missing test hardware") }
        precondition(hardware.apply(gate: .inhibitCharging, limit: 80))
        precondition(SMCClient.writes.map(\.0) == ["CHTE"], "holding must not rewrite the adapter flag")
        precondition(hardware.apply(gate: .inhibitCharging, limit: 80))
        precondition(SMCClient.writes.count == 1, "unchanged holding must not write again")
        precondition(hardware.restoreNormal())
        precondition(SMCClient.writes.map(\.0) == ["CHTE", "CHTE"], "release only the charging gate on reconnect")

        SMCClient.writes = []
        precondition(hardware.apply(gate: .forceDischarge, limit: 80))
        precondition(SMCClient.writes.map(\.0) == ["CHIE", "CHTE"], "discharge precedes charging inhibition")
        precondition(SMCClient.values["CHIE"] == [8] && hardware.isForceDischarging)
        precondition(SMCClient.values["CH0I"] == [0], "never combine discharge families")
        precondition(hardware.apply(gate: .forceDischarge, limit: 60))
        precondition(SMCClient.writes.count == 2, "changing a software target must not cycle discharge")
        precondition(hardware.apply(gate: .inhibitCharging, limit: 60))
        precondition(SMCClient.writes.map(\.0) == ["CHIE", "CHTE", "CHIE"], "settling discharge keeps charging inhibited")
        precondition(!hardware.isForceDischarging)

        precondition(hardware.restoreNormal())
        SMCClient.writes = []
        SMCClient.failingKey = "CHIE"
        precondition(!hardware.apply(gate: .forceDischarge, limit: 80))
        precondition(SMCClient.writes.isEmpty && SMCClient.values["CHTE"] == [0, 0, 0, 0],
                     "a failed discharge transition must not also change charging")
        SMCClient.failingKey = nil

        precondition(hardware.apply(gate: .forceDischarge, limit: 80))
        SMCClient.writes = []
        precondition(hardware.apply(gate: .allowCharging, limit: 100))
        precondition(SMCClient.writes.map(\.0) == ["CHIE", "CHTE"],
                     "top up exits discharge before opening the charging gate")
        precondition(!hardware.isForceDischarging && SMCClient.values["CHTE"] == [0, 0, 0, 0])
        precondition(hardware.apply(gate: .allowCharging, limit: 100))
        precondition(SMCClient.writes.count == 2, "top up must not repeatedly renegotiate power")

        SMCClient.values = ["CHIE": [0]]
        SMCClient.writes = []
        guard let native = ChargeControlHardware() else { fatalError("missing native discharge hardware") }
        precondition(native.profile.family == .nativePowerUI && !native.profile.supportsInhibit)
        precondition(native.profile.supportsDischarge)
        precondition(!native.apply(gate: .inhibitCharging, limit: 90) && SMCClient.writes.isEmpty,
                     "the helper must not pretend it can enforce a native charge limit")
        precondition(native.apply(gate: .forceDischarge, limit: 90))
        precondition(native.apply(gate: .forceDischarge, limit: 85))
        precondition(SMCClient.writes.count == 1 && SMCClient.values["CHIE"] == [8],
                     "native discharge must not cycle adapter power")
        precondition(native.restoreNormal())
        precondition(native.restoreNormal())
        precondition(SMCClient.writes.map(\.0) == ["CHIE", "CHIE"] && SMCClient.values["CHIE"] == [0])

        SMCClient.values = ["BCLM": [100], "ACEN": [1]]
        SMCClient.writes = []
        guard let intel = ChargeControlHardware() else { fatalError("missing Intel test hardware") }
        precondition(intel.apply(gate: .inhibitCharging, limit: 80))
        precondition(intel.apply(gate: .inhibitCharging, limit: 60))
        precondition(SMCClient.writes.map(\.0) == ["BCLM", "BCLM"] && SMCClient.values["BCLM"] == [60],
                     "Intel limit changes reach firmware without toggling adapter power")
        print("CHARGE HARDWARE TESTS OK")
    }
}
