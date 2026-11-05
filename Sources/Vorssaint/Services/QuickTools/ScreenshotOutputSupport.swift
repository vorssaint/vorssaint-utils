// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The decisions behind changing what a capture becomes: resizing it, for
/// now. Pure geometry, so each rule is testable without a window.
enum ScreenshotOutputSupport {
    // MARK: - Resize

    /// Neither side may end up below this or above the largest bitmap the
    /// renderer is asked to draw.
    static let resizeSideLimits: ClosedRange<CGFloat> = 8...16_384

    /// The new pixel size for a typed width or height, keeping the capture's
    /// proportions. Nil when nothing usable was typed, when the size would
    /// not change, or when either side would leave the limits.
    static func resizedSize(original: CGSize, width: Int? = nil, height: Int? = nil) -> CGSize? {
        guard original.width > 0, original.height > 0 else { return nil }
        let factor: CGFloat
        if let width, width > 0 {
            factor = CGFloat(width) / original.width
        } else if let height, height > 0 {
            factor = CGFloat(height) / original.height
        } else {
            return nil
        }
        return resizedSize(original: original, factor: factor)
    }

    static func resizedSize(original: CGSize, percent: Int) -> CGSize? {
        guard percent > 0 else { return nil }
        return resizedSize(original: original, factor: CGFloat(percent) / 100)
    }

    private static func resizedSize(original: CGSize, factor: CGFloat) -> CGSize? {
        guard factor.isFinite, factor > 0 else { return nil }
        let size = CGSize(width: max(1, (original.width * factor).rounded()),
                          height: max(1, (original.height * factor).rounded()))
        guard size != original,
              resizeSideLimits.contains(size.width), resizeSideLimits.contains(size.height)
        else { return nil }
        return size
    }

    /// The other side of a typed one, for the field that follows along.
    static func proportionalSide(_ typed: Int, of original: CGFloat, other: CGFloat) -> Int {
        guard original > 0 else { return 0 }
        return max(1, Int((CGFloat(typed) * other / original).rounded()))
    }
}
