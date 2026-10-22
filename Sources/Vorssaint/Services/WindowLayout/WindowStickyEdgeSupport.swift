// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Which side of the first window touches the second one.
enum WindowStickyEdge: Equatable {
    case right, left, bottom, top
}

/// What a neighbour does when the window next to it changed its edge.
enum WindowStickyFollow: Equatable {
    case follow(CGRect)
    /// The shared edge did not move, so the neighbour stays as it is.
    case unaffected
    /// The neighbour would drop below the minimum size; it stays as it is.
    case tooSmall
}

/// Pure decisions of the coupled resize; no windows, no Accessibility calls.
/// Frames are in Accessibility space (origin top left, y grows down).
enum WindowStickyEdgeSupport {
    /// The edge of `a` that lies on an edge of `b`, or nil. Windows count as
    /// neighbours when the facing edges are within `tolerance` of each other
    /// (a small gap or a small overlap) and the other axis overlaps by at
    /// least `minimumOverlap` points, so corner contact does not couple.
    static func sharedEdge(of a: CGRect, with b: CGRect,
                           tolerance: CGFloat = 4,
                           minimumOverlap: CGFloat = 40) -> WindowStickyEdge? {
        guard a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return nil }
        let verticalOverlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let horizontalOverlap = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        var best: (edge: WindowStickyEdge, distance: CGFloat)?
        func consider(_ edge: WindowStickyEdge, distance: CGFloat, overlap: CGFloat) {
            guard distance <= tolerance, overlap >= minimumOverlap else { return }
            if let current = best, current.distance <= distance { return }
            best = (edge, distance)
        }
        consider(.right, distance: abs(a.maxX - b.minX), overlap: verticalOverlap)
        consider(.left, distance: abs(a.minX - b.maxX), overlap: verticalOverlap)
        consider(.bottom, distance: abs(a.maxY - b.minY), overlap: horizontalOverlap)
        consider(.top, distance: abs(a.minY - b.maxY), overlap: horizontalOverlap)
        return best?.edge
    }

    /// True when the window changed position but not size: a drag, not a
    /// resize. A dragged window has left its layout slot.
    static func isPureMove(old: CGRect, new: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(old.width - new.width) <= tolerance && abs(old.height - new.height) <= tolerance
            && (abs(old.minX - new.minX) > tolerance || abs(old.minY - new.minY) > tolerance)
    }

    /// What the follower `b` does when `a` went from `old` to `new` while
    /// sharing `edge` with `b`. Only the facing edge of `b` moves, by the
    /// distance the edge of `a` moved, so a gap between the two is kept and
    /// the far side of `b` (and any third window beyond it) stays put.
    static func followerFrame(edge: WindowStickyEdge,
                              old: CGRect, new: CGRect, follower b: CGRect,
                              tolerance: CGFloat = 1,
                              minimumSize: CGFloat = 80) -> WindowStickyFollow {
        let resized: Bool
        let delta: CGFloat
        switch edge {
        case .right:
            resized = abs(old.width - new.width) > tolerance
            delta = new.maxX - old.maxX
        case .left:
            resized = abs(old.width - new.width) > tolerance
            delta = new.minX - old.minX
        case .bottom:
            resized = abs(old.height - new.height) > tolerance
            delta = new.maxY - old.maxY
        case .top:
            resized = abs(old.height - new.height) > tolerance
            delta = new.minY - old.minY
        }
        guard resized, abs(delta) > tolerance else { return .unaffected }
        var result = b
        switch edge {
        case .right:
            result.origin.x += delta
            result.size.width -= delta
        case .left:
            result.size.width += delta
        case .bottom:
            result.origin.y += delta
            result.size.height -= delta
        case .top:
            result.size.height += delta
        }
        let length = (edge == .left || edge == .right) ? result.width : result.height
        return length >= minimumSize ? .follow(result) : .tooSmall
    }

    /// True when both frames sit mostly on the same display. `displays` are
    /// the display frames in Accessibility space; without any, nothing is
    /// known and the answer is true so a missing list never disables coupling.
    static func shareDisplay(_ a: CGRect, _ b: CGRect, displays: [CGRect]) -> Bool {
        guard !displays.isEmpty else { return true }
        func index(of frame: CGRect) -> Int? {
            var best: (index: Int, area: CGFloat)?
            for (position, display) in displays.enumerated() {
                let overlap = display.intersection(frame)
                let area = overlap.isNull ? 0 : overlap.width * overlap.height
                if area > (best?.area ?? 0) { best = (position, area) }
            }
            return best?.index
        }
        return index(of: a) == index(of: b)
    }
}
