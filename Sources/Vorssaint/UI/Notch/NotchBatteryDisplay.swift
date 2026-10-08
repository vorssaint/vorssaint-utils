// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// How the island draws the charge. Both halves of the battery content — the
/// icon in the closed capsule's middle and the one in the open capsule's wing
/// — read these, so the two cannot disagree about the level or the bolt.
///
/// The glyph tables differ because the menu bar and the island name their
/// battery symbols differently: the wing shares the menu bar's set, while the
/// closed capsule keeps the named-percent set it has always drawn.
extension PowerReading {
    /// The closed capsule's icon, whose glyph empties with the charge and
    /// takes the bolt while the Mac runs on its adapter.
    var batterySymbol: String {
        BatteryPowerSupport.capsuleSymbol(percent: chargePercent ?? 100,
                                          isCharging: isCharging,
                                          externalConnected: externalConnected)
    }

    /// The wing's icon, in the menu bar's own naming.
    var menuBarBatterySymbol: String {
        BatteryPowerSupport.menuBarSymbol(percent: chargePercent ?? 100,
                                          isCharging: isCharging,
                                          externalConnected: externalConnected)
    }
}

/// The colour a warning paints the charge, shared by the wing and the capsule.
enum NotchBatteryDisplay {
    static func tint(for warning: BatteryWarning) -> Color {
        switch warning {
        case .low: return .red
        case .early: return .orange
        case .none: return .white.opacity(0.9)
        }
    }
}
