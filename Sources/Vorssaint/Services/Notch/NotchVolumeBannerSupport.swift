// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// macOS raises its own volume banner for a level set outside the volume keys,
/// such as a swipe on AirPods, so taking the keys alone never kept it away.
/// The island shows that level too. While it does, the banner leaves the screen.
enum NotchVolumeBannerSupport {
    /// The menu bar process that draws the banner, on macOS 27 and later.
    static let host = "com.apple.MenuBarAgent"
    static let identifier = "volume-system-banner"

    static func isBanner(_ identifier: String?) -> Bool {
        identifier == self.identifier
    }

    static func isOffScreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        let union = screens.reduce(CGRect.null) { $0.union($1) }
        return !union.isNull && !frame.intersects(union)
    }

    /// Beyond every display, the same way hidden notification banners go.
    /// Nil once the banner is out of sight or no display can be read.
    static func hiddenOrigin(for frame: CGRect, screens: [CGRect]) -> CGPoint? {
        let union = screens.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull, frame.intersects(union) else { return nil }
        return CGPoint(x: union.minX - frame.width - 1_000, y: union.minY - frame.height - 1_000)
    }
}
