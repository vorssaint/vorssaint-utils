// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension AppFeature {
    /// Whether this feature can run on the Mac's hardware
    var isHardwareSupported: Bool {
        switch self {
        case .fanControl:
            return FanControlHardware.hasControllableFan
        default:
            return true
        }
    }

    /// Why `isHardwareSupported` is false for display in the Features hub
    /// `nil` when the feature is supported or has no hardware dependency
    var hardwareUnsupportedReason: String? {
        guard !isHardwareSupported else { return nil }

        switch self {
        case .fanControl:
            return FeatureStrings.fanControl(L10n.shared.language).noFans
        default:
            return nil
        }
    }
}
