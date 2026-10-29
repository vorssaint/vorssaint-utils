// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Geometry for pinned captures, kept apart from the window so it is
/// testable without one.
enum ScreenshotPinSupport {
    /// A pin grows or shrinks with the scroll wheel around the pointer,
    /// keeping its proportions: scrolling up enlarges it. It never goes below
    /// `minimumSize` or past `maximumSize`, usually its screen.
    static func zoomedFrame(_ frame: CGRect, scrollDelta: CGFloat, anchor: CGPoint,
                            minimumSize: CGSize, maximumSize: CGSize) -> CGRect {
        guard frame.width > 0, frame.height > 0, scrollDelta.isFinite, scrollDelta != 0 else { return frame }
        let step = min(max(scrollDelta, -12), 12)
        var factor = 1 + step * 0.025
        let smallest = max(minimumSize.width / frame.width, minimumSize.height / frame.height)
        let largest = min(maximumSize.width / frame.width, maximumSize.height / frame.height)
        factor = min(max(factor, smallest), max(largest, smallest))
        guard abs(factor - 1) > 0.0001 else { return frame }
        let size = CGSize(width: frame.width * factor, height: frame.height * factor)
        // The point under the pointer stays under it.
        let relativeX = (anchor.x - frame.minX) / frame.width
        let relativeY = (anchor.y - frame.minY) / frame.height
        let x = anchor.x - size.width * min(max(relativeX, 0), 1)
        let y = anchor.y - size.height * min(max(relativeY, 0), 1)
        return CGRect(origin: CGPoint(x: x, y: y), size: size).integral
    }

    /// Scroll deltas in wheel lines: a trackpad reports pixels, which would
    /// zoom four times as fast.
    static func wheelLines(_ delta: CGFloat, precise: Bool) -> CGFloat {
        precise ? delta / 4 : delta
    }
}
