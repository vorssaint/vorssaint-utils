// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A rectangle in whole screen points, in one space shared by every display:
/// the origin is the main display's top-left corner and y grows downwards, so
/// a display to the left of or above the main one has negative coordinates.
struct ShotRect: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    static let zero = ShotRect(x: 0, y: 0, width: 0, height: 0)

    var right: Int { x + width }
    var bottom: Int { y + height }
    var isEmpty: Bool { width <= 0 || height <= 0 }

    /// The rectangle spanned by two corners, in either order. Both corners are inside it.
    static func fromCorners(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> ShotRect {
        let (l, r) = x1 <= x2 ? (x1, x2) : (x2, x1)
        let (t, b) = y1 <= y2 ? (y1, y2) : (y2, y1)
        return ShotRect(x: l, y: t, width: r - l + 1, height: b - t + 1)
    }

    func contains(_ px: Double, _ py: Double) -> Bool {
        px >= Double(x) && px < Double(right) && py >= Double(y) && py < Double(bottom)
    }

    func intersection(_ other: ShotRect) -> ShotRect {
        let l = max(x, other.x), t = max(y, other.y)
        let r = min(right, other.right), b = min(bottom, other.bottom)
        return r <= l || b <= t ? .zero : ShotRect(x: l, y: t, width: r - l, height: b - t)
    }

    func union(_ other: ShotRect) -> ShotRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let l = min(x, other.x), t = min(y, other.y)
        let r = max(right, other.right), b = max(bottom, other.bottom)
        return ShotRect(x: l, y: t, width: r - l, height: b - t)
    }

    /// "x,y,w,h", as the last selection is remembered.
    var storageValue: String { "\(x),\(y),\(width),\(height)" }

    init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ",").map { Int($0) }
        guard parts.count == 4, let x = parts[0], let y = parts[1],
              let width = parts[2], let height = parts[3], width > 0, height > 0
        else { return nil }
        self.init(x: x, y: y, width: width, height: height)
    }
}

/// What part of the selection the pointer is over.
enum ShotHandle: Equatable {
    case none, inside, n, s, e, w, ne, nw, se, sw
}

/// Selection maths for the capture overlay: hit testing, moving and resizing
/// by handles, and where the two toolbars go.
enum ShotGeometry {
    /// Which handle (or the inside) is under the point. Handles sit on the
    /// edges and corners and reach `grip` points either side of them.
    static func hitTest(_ sel: ShotRect, x: Double, y: Double, grip: Double) -> ShotHandle {
        if sel.isEmpty { return .none }
        let l = Double(sel.x), t = Double(sel.y), r = Double(sel.right), b = Double(sel.bottom)
        if x < l - grip || x > r + grip || y < t - grip || y > b + grip { return .none }
        let nearL = abs(x - l) <= grip, nearR = abs(x - r) <= grip
        let nearT = abs(y - t) <= grip, nearB = abs(y - b) <= grip
        if nearT && nearL { return .nw }
        if nearT && nearR { return .ne }
        if nearB && nearL { return .sw }
        if nearB && nearR { return .se }
        if nearT { return .n }
        if nearB { return .s }
        if nearL { return .w }
        if nearR { return .e }
        return sel.contains(x, y) ? .inside : .none
    }

    /// The selection after dragging `handle` by (dx, dy) from `start`.
    /// Dragging an edge past the opposite one flips the selection. Inside
    /// moves the whole selection, kept within `bounds`.
    static func drag(_ start: ShotRect, handle: ShotHandle, dx: Int, dy: Int, bounds: ShotRect) -> ShotRect {
        if handle == .inside { return move(start, dx: dx, dy: dy, bounds: bounds) }
        var l = start.x, t = start.y, r = start.right, b = start.bottom
        if handle == .w || handle == .nw || handle == .sw { l += dx }
        if handle == .e || handle == .ne || handle == .se { r += dx }
        if handle == .n || handle == .nw || handle == .ne { t += dy }
        if handle == .s || handle == .sw || handle == .se { b += dy }
        if l > r { swap(&l, &r) }
        if t > b { swap(&t, &b) }
        l = max(l, bounds.x)
        t = max(t, bounds.y)
        r = min(r, bounds.right)
        b = min(b, bounds.bottom)
        return ShotRect(x: l, y: t, width: max(1, r - l), height: max(1, b - t))
    }

    /// Moves the selection by (dx, dy) without leaving `bounds`.
    static func move(_ sel: ShotRect, dx: Int, dy: Int, bounds: ShotRect) -> ShotRect {
        var moved = sel
        moved.x = min(max(sel.x + dx, bounds.x), max(bounds.x, bounds.right - sel.width))
        moved.y = min(max(sel.y + dy, bounds.y), max(bounds.y, bounds.bottom - sel.height))
        return moved
    }

    /// The tools run down the right side of the selection, bottom aligned,
    /// and the actions run along its bottom edge, right aligned. A toolbar
    /// that doesn't fit outside on the display goes to the opposite side, and
    /// inside the selection if neither fits. Returns the top-left corners.
    static func placeToolbars(selection sel: ShotRect, display: ShotRect,
                              tools: (width: Int, height: Int),
                              actions: (width: Int, height: Int),
                              gap: Int) -> (tools: (x: Int, y: Int), actions: (x: Int, y: Int)) {
        // Actions bar: below, else above, else inside the bottom edge.
        let ay: Int
        if sel.bottom + gap + actions.height <= display.bottom {
            ay = sel.bottom + gap
        } else if sel.y - gap - actions.height >= display.y {
            ay = sel.y - gap - actions.height
        } else {
            ay = sel.bottom - gap - actions.height
        }
        let ax = min(max(sel.right - actions.width, display.x),
                     max(display.x, display.right - actions.width))

        // Tools bar: right, else left, else inside the right edge; bottom
        // aligned with the selection.
        let tx: Int
        if sel.right + gap + tools.width <= display.right {
            tx = sel.right + gap
        } else if sel.x - gap - tools.width >= display.x {
            tx = sel.x - gap - tools.width
        } else {
            tx = sel.right - gap - tools.width
        }
        let ty = min(max(sel.bottom - tools.height, display.y),
                     max(display.y, display.bottom - tools.height))
        return ((tx, ty), (ax, ay))
    }

    /// Where the W×H label goes: just above the top-left corner, or inside it
    /// when that is off the display.
    static func placeSizeLabel(selection sel: ShotRect, display: ShotRect,
                               label: (width: Int, height: Int), gap: Int) -> (x: Int, y: Int) {
        let y = sel.y - gap - label.height >= display.y ? sel.y - gap - label.height : sel.y + gap
        let x = min(max(sel.x, display.x), max(display.x, display.right - label.width))
        return (x, y)
    }
}
