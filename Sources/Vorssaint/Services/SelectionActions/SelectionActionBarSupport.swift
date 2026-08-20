// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure placement math for the Selection Actions bar, kept apart from the
/// `NSPanel` mechanics so it stays a plain, deterministic function of its
/// inputs. Adapted from `ScreenshotSupport.quickPreviewFrame`, but
/// vertical-first: a text selection is usually a single line, so the bar
/// reads best hovering directly above it, the way PopClip's own bar does,
/// rather than beside it.
enum SelectionActionBarSupport {
    static func frame(size: CGSize,
                      anchor: CGRect,
                      pointer: CGPoint,
                      visibleFrame: CGRect) -> CGRect {
        let inset: CGFloat = 10
        let usable = visibleFrame.insetBy(dx: inset, dy: inset)
        let gap: CGFloat = 8

        var y = anchor.maxY + gap
        if y + size.height > usable.maxY {
            let below = anchor.minY - size.height - gap
            y = below >= usable.minY ? below : pointer.y - size.height / 2
        }

        var x = anchor.midX - size.width / 2
        if x < usable.minX || x + size.width > usable.maxX {
            x = pointer.x - size.width / 2
        }

        x = min(max(x, usable.minX), max(usable.minX, usable.maxX - size.width))
        y = min(max(y, usable.minY), max(usable.minY, usable.maxY - size.height))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Picks the display holding most of the anchor rectangle, the pointer's
    /// display as fallback — same rule `ScreenshotSupport.quickPreviewVisibleFrame`
    /// uses, since a selection can span close to a display edge.
    static func visibleFrame(anchor: CGRect,
                             pointer: CGPoint,
                             screens: [(frame: CGRect, visibleFrame: CGRect)],
                             fallback: CGRect) -> CGRect {
        var selected: (frame: CGRect, visibleFrame: CGRect)?
        var selectedArea: CGFloat = 0
        for screen in screens {
            let overlap = anchor.intersection(screen.frame)
            let area = overlap.isNull ? 0 : max(0, overlap.width) * max(0, overlap.height)
            if area > selectedArea {
                selected = screen
                selectedArea = area
            }
        }
        if let selected { return selected.visibleFrame }
        return screens.first { $0.frame.contains(pointer) }?.visibleFrame ?? fallback
    }
}
