// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Reads and writes the built-in display's brightness for closed-lid
/// dimming, over the same DisplayServices route `BrightnessBridge` already
/// resolves for `BrightnessService`. Only the built-in panel: an attached
/// external display is not under the lid and is left exactly as it was.
enum LidDisplayDimmer {
    /// `CGGetOnlineDisplayList` still reports the built-in panel once the lid
    /// closes and it drops out of the active list, which is what lets it be
    /// found and written at all while the lid is shut.
    static func builtInDisplayID() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// Nil when the panel cannot be identified or its reading failed — never
    /// a stand-in zero, which `LidDimmingSupport` would take as a literal
    /// (and wrong) brightness to save.
    static func currentBrightness() -> Double? {
        guard let id = builtInDisplayID(), let getBrightness = BrightnessBridge.getBrightness else { return nil }
        var value: Float = 0
        guard getBrightness(id, &value) == 0 else { return nil }
        return Double(value)
    }

    /// True only when the panel was found in the online list and the write
    /// itself reported success — never assumed from having merely asked.
    @discardableResult
    static func setBrightness(_ value: Double) -> Bool {
        guard let id = builtInDisplayID(), let setBrightness = BrightnessBridge.setBrightness else { return false }
        return setBrightness(id, Float(value)) == 0
    }
}
