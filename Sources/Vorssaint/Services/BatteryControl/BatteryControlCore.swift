// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure battery-charge-limit contracts. Nothing here touches the SMC or
/// IOKit: the hysteresis decision, the capability selection and the
/// firmware-limit encoding are all decided from values, so both the helper
/// and the tests can check them without any hardware.
///
/// Key names and value encodings follow the platform-researched charge
/// control surface: direct charging keys `CH0B`/`CH0C` (and `CHTE` on newer
/// firmware) and the adapter-side keys `CH0I`/`CH0J`/`CHIE`. Presence
/// selects the backend; the macOS version never does.
enum BatteryControlCore {
    static let minimumUpper = 50
    static let maximumUpper = 100
    /// Below the upper limit the battery stops charging, and this many
    /// points lower it is allowed to charge again, so a Mac on the adapter
    /// is not pushed through micro-charges.
    static let defaultUpper = 80
    static let defaultLowerDelta = 2
    /// How deep the resume edge may go. 10 % keeps a margin above the point
    /// where macOS starts forcing sleep, so a missed tick cannot strand the Mac.
    static let minimumLower = 10
    static let maximumLowerDelta = maximumUpper - minimumLower

    /// The control surface this Mac offers, decided purely from which keys
    /// exist.
    enum Backend: String, Codable, Sendable, CaseIterable {
        case legacy
        case unsupported
    }
}

/// Charge-control key surface: which keys exist right now, and at what
/// data size. Presence selects the backend; the macOS version never does.
struct Probe {
    var keySizes: [String: Int] = [:]

    func has(_ name: String, size: Int) -> Bool { keySizes[name] == size }

    var backend: BatteryControlCore.Backend {
        if has("CH0B", size: 1) && has("CH0C", size: 1) { return .legacy }
        if has("CHTE", size: 4) { return .legacy }
        return .unsupported
    }

    /// The wall-power key, where it lives on its own: cut the adapter and
    /// the Mac runs on the battery even though the brick stays plugged in.
    /// Not entitlement-gated so far, which keeps the feature usable below
    /// the firmware's own 80 % floor.
    var adapterKeyName: String? {
        if has("CH0I", size: 1) { return "CH0I" }
        if has("CH0J", size: 1) { return "CH0J" }
        if has("CHIE", size: 1) { return "CHIE" }
        return nil
    }
}

struct BatteryLimitState: Codable, Equatable, Sendable {
    var enabled: Bool
    var upper: Int
    var lowerDelta: Int
    /// Cycle mode: at the upper limit the adapter is cut as well, so the Mac
    /// runs from the battery while still plugged in and drains to the lower
    /// edge before wall power returns. Needs the adapter key; without it the
    /// limit just holds.
    var discharge = false

    static func valid(_ value: BatteryLimitState) -> Bool {
        value.upper >= BatteryControlCore.minimumUpper
            && value.upper <= BatteryControlCore.maximumUpper
            && value.lowerDelta >= 0
            && value.lowerDelta <= BatteryControlCore.maximumLowerDelta
    }

    /// The lower edge never dips under `minimumLower`: a deeper band is
    /// clamped rather than refused.
    var lower: Int { max(BatteryControlCore.minimumLower, upper - lowerDelta) }

    /// What the wall-power side should do for one battery reading.
    enum Adapter: Equatable {
        /// Wall power must reach the Mac.
        case connect
        /// Wall power must be cut so the battery carries the Mac.
        case disconnect
        /// Inside the band: whatever is in place stands.
        case hold
    }

    /// Outside discharge mode (or with the limit off or invalid) the adapter
    /// is never ours to hold back, so the answer is `.connect`: a mode switch
    /// mid-discharge hands wall power straight back.
    static func adapter(for state: BatteryLimitState, percentage: Int) -> Adapter {
        guard state.enabled, state.discharge, BatteryLimitState.valid(state) else {
            return .connect
        }
        switch charging(enabled: state, percentage: percentage) {
        case .inhibit: return .disconnect
        case .enable: return .connect
        case nil: return .hold
        }
    }

    /// The hysteresis verdict for one battery reading. Between the limits
    /// the current charging state stands: the battery is neither pulled
    /// up nor pushed down.
    enum Charging: Equatable {
        case enable
        case inhibit
    }

    static func charging(enabled state: BatteryLimitState, percentage: Int) -> Charging? {
        guard state.enabled, BatteryLimitState.valid(state), percentage >= 0,
              percentage <= 100 else { return nil }
        if percentage >= state.upper { return .inhibit }
        if percentage <= state.lower { return .enable }
        return nil
    }
}
