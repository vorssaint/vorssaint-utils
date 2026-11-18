// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Reads the adjustment feedback BetterDisplay broadcasts when its Settings >
/// Application > Integration > Dispatch OSD notifications option is on.
/// https://betterdisplay.pro/guide/integration/third-party-apps/
enum BetterDisplayOSD {
    /// BetterDisplay also broadcasts under the legacy `com.` prefix; only the
    /// current name is observed so each adjustment arrives once.
    static let notificationName = Notification.Name("pro.betterdisplay.BetterDisplay.osd")
    static let brightnessTargets: Set<String> = ["combinedBrightness", "hardwareBrightness", "softwareBrightness"]
    static let brightnessIconID = 1

    /// Every field is optional in the protocol; unknown ones are ignored.
    struct Payload: Decodable {
        var displayID: Int?
        var systemIconID: Int?
        var controlTarget: String?
        var value: Double?
        var maxValue: Double?
    }

    struct BrightnessReading: Equatable {
        let displayID: CGDirectDisplayID?
        let level: Double
    }

    /// The brightness a broadcast reports as a 0...1 fraction, or nil for any
    /// other control, a missing value or an unusable maximum. A known control
    /// target decides; without one, the brightness system icon does.
    static func brightness(fromJSON json: String) -> BrightnessReading? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8)) else { return nil }
        let isBrightness = payload.controlTarget.map { brightnessTargets.contains($0) }
            ?? (payload.systemIconID == brightnessIconID)
        guard isBrightness, let value = payload.value, value.isFinite,
              let maxValue = payload.maxValue, maxValue.isFinite, maxValue > 0 else { return nil }
        let displayID = payload.displayID.flatMap { $0 > 0 && $0 <= Int(UInt32.max) ? CGDirectDisplayID($0) : nil }
        return BrightnessReading(displayID: displayID, level: min(max(value / maxValue, 0), 1))
    }
}
