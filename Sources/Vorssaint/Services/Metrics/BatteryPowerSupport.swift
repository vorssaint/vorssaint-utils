// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// How the power connection is read for display. Kept apart from the views and
/// the menu bar renderer so the states they have to tell apart can be checked
/// without AppKit.
enum BatteryPowerSupport {
    /// What the Mac is running on, as the panel reports it.
    enum State: Equatable {
        /// On the adapter, with the battery taking a charge.
        case charging
        /// On the adapter with the charge stopped: full, or held at a limit.
        case externalPower
        case onBattery
        /// No battery and no adapter reading to describe.
        case unavailable
    }

    /// A charge in progress is named first because it already implies external
    /// power. The menu bar glyph has always drawn the bolt for a charge, so
    /// reading the adapter first would let the two describe one reading
    /// differently if a source ever reported a charge without the adapter.
    static func state(isCharging: Bool, externalConnected: Bool, hasBattery: Bool) -> State {
        if isCharging { return .charging }
        if externalConnected { return .externalPower }
        return hasBattery ? .onBattery : .unavailable
    }

    /// The bolt belongs to external power, not to a charge in progress. A Mac
    /// held at a charge limit, and a Mac sitting at full on its adapter, both
    /// report `isCharging` false while still running off the adapter, so a
    /// plain battery there is indistinguishable from an unplugged one.
    ///
    /// A charge in progress keeps the bolt on its own, so an adapter the system
    /// has not reported yet still reads as external power rather than dropping
    /// back to a level.
    static func menuBarSymbol(percent: Int, isCharging: Bool, externalConnected: Bool) -> String {
        if isCharging || externalConnected { return "battery.100.bolt" }
        switch percent {
        case 85...: return "battery.100"
        case 60..<85: return "battery.75"
        case 35..<60: return "battery.50"
        case 10..<35: return "battery.25"
        default: return "battery.0"
        }
    }
}
