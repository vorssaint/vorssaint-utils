// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowMaximizerSupport {
    /// An app on the exception list keeps the green button's own behavior, so
    /// a game, an emulator or a player can still enter macOS full screen.
    static func excludes(bundleIdentifier: String?, excludedBundleIdentifiers: [String]) -> Bool {
        guard let bundleIdentifier else { return false }
        return Defaults.sanitizedBundleIdentifierList(excludedBundleIdentifiers).contains(bundleIdentifier)
    }

    /// Some apps keep a window edge out from under a Dock at the side of the
    /// screen and refuse a size that would put it there: a window dragged in
    /// from another display stays wider than the target, by a few points or by
    /// the whole Dock. Within the frame tolerance that still reads as done while
    /// the window sits under the Dock, so any excess counts, not only one past
    /// the tolerance; half a point absorbs rounding.
    static func overshoots(_ actual: CGSize, target: CGSize) -> Bool {
        actual.width > target.width + 0.5 || actual.height > target.height + 0.5
    }

    /// Taking the target size a tolerance up and to the left keeps the far
    /// edges clear of the Dock, so those apps accept it in full; the move back
    /// onto the target is not limited the same way and lands where native zoom
    /// does. Growing into the target instead stops a point short.
    static func approachOrigin(for target: CGPoint, tolerance: CGFloat) -> CGPoint {
        CGPoint(x: target.x - tolerance, y: target.y - tolerance)
    }
}
