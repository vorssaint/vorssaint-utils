// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// JSON over XPC, like every other call to the helper: a single
/// deterministic fallback keeps a broken reply from ever wedging a caller.
/// The calls themselves live on `FanControlXPCProtocol`; charging shares the
/// fan-control daemon rather than shipping a second one.
enum BatteryControlIPC {
    static func encode(_ snapshot: BatteryControlSnapshot) -> Data {
        (try? JSONEncoder().encode(snapshot)) ?? Data()
    }

    static func decodeSnapshot(_ data: Data) -> BatteryControlSnapshot? {
        try? JSONDecoder().decode(BatteryControlSnapshot.self, from: data)
    }

    static func decodeLimits(_ data: Data) -> BatteryLimitState? {
        try? JSONDecoder().decode(BatteryLimitState.self, from: data)
    }

    static func encode(_ limits: BatteryLimitState) -> Data {
        (try? JSONEncoder().encode(limits)) ?? Data()
    }
}

struct BatteryControlSnapshot: Codable, Equatable, Sendable {
    var backend: BatteryControlCore.Backend
    var adapterKeyPresent: Bool
    /// Whether wall power reaches the Mac right now; `nil` when the Mac has no
    /// adapter key (or an older daemon answered).
    var adapterConnected: Bool?
    var limits: BatteryLimitState
    /// Battery percent, or `nil` while the power sources have not answered.
    var percentage: Int?
    var isCharging: Bool
    var lastFault: String

    static var empty = BatteryControlSnapshot(
        backend: .unsupported,
        adapterKeyPresent: false,
        limits: BatteryLimitState(enabled: false,
                                  upper: BatteryControlCore.defaultUpper,
                                  lowerDelta: BatteryControlCore.defaultLowerDelta),
        percentage: nil,
        isCharging: false,
        lastFault: "none")
}
