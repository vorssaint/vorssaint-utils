// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One display that can run HDR in its current mode, as the switches show it.
struct HDRDisplay: Identifiable, Equatable {
    let id: UInt32
    let name: String
    let isEnabled: Bool
}

/// Pure rules behind the HDR switches, kept free of AppKit and SkyLight so the
/// unit harness pins them down.
enum HDRControlSupport {
    /// How long a switch may take to show up. macOS reconfigures the link to
    /// the display, which takes a second or two on a typical monitor.
    static let settleTimeout: TimeInterval = 4
    static let settlePollInterval: TimeInterval = 0.25

    /// What the one Quick Toggles tile does across every HDR display: with any
    /// display already in HDR it turns HDR off everywhere, otherwise on. That
    /// way the tile never leaves a mix it cannot show as one state.
    static func quickToggleTarget(_ displays: [HDRDisplay]) -> Bool {
        !displays.contains(where: \.isEnabled)
    }

    /// The tile reads as on while any display is in HDR.
    static func quickToggleIsOn(_ displays: [HDRDisplay]) -> Bool {
        displays.contains(where: \.isEnabled)
    }

    /// The tile's caption: the display it switches, or every one of them.
    static func quickToggleCaption(_ displays: [HDRDisplay]) -> String {
        displays.map(\.name).joined(separator: ", ")
    }

    /// The setter returns nothing reliable, so a switch counts only once the
    /// display reports the requested state.
    static func didSettle(requested: Bool, reported: Bool?) -> Bool {
        reported == requested
    }

    /// Displays in a stable order: the main display first, then by ID, so a
    /// reconfiguration that reorders the online list does not shuffle rows.
    static func ordered(_ displays: [HDRDisplay], mainID: UInt32) -> [HDRDisplay] {
        displays.sorted { lhs, rhs in
            if (lhs.id == mainID) != (rhs.id == mainID) { return lhs.id == mainID }
            return lhs.id < rhs.id
        }
    }

    /// The name shown for a display, falling back when macOS reports none.
    static func displayName(_ localizedName: String?, fallback: String) -> String {
        let trimmed = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
