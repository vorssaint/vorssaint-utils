// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

enum DockLockSupport {
    struct Zone: Equatable { let rect: CGRect; let dx: CGFloat; let dy: CGFloat }
    /// Only exposed edges can summon the Dock. A shared edge must remain
    /// traversable, including when another screen covers only part of it.
    static func exposed(_ frame: CGRect, screens: [CGRect], orientation: DockPreviewOrientation) -> [ClosedRange<CGFloat>] {
        let horizontal = orientation == .bottom
        let start = horizontal ? frame.minX : frame.minY
        let end = horizontal ? frame.maxX : frame.maxY
        var covered: [ClosedRange<CGFloat>] = []
        for other in screens where other != frame {
            let adjacent: Bool
            switch orientation {
            case .bottom: adjacent = abs(other.minY - frame.maxY) <= 2
            case .left: adjacent = abs(other.maxX - frame.minX) <= 2
            case .right: adjacent = abs(other.minX - frame.maxX) <= 2
            }
            let a = max(start, horizontal ? other.minX : other.minY)
            let b = min(end, horizontal ? other.maxX : other.maxY)
            if adjacent && b > a { covered.append(a...b) }
        }
        var cursor = start, result: [ClosedRange<CGFloat>] = []
        for interval in covered.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if interval.lowerBound > cursor { result.append(cursor...interval.lowerBound) }
            cursor = max(cursor, interval.upperBound)
        }
        if cursor < end { result.append(cursor...end) }
        return result
    }
    static func relocationPath(frame: CGRect, screens: [CGRect], orientation: DockPreviewOrientation) -> (CGPoint, CGPoint)? {
        guard let interval = exposed(frame, screens: screens, orientation: orientation).max(by: { $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound }) else { return nil }
        let along = interval.lowerBound + min(60, (interval.upperBound - interval.lowerBound) / 2)
        switch orientation {
        case .bottom: return (CGPoint(x: along, y: frame.maxY - 80), CGPoint(x: along, y: frame.maxY - 1))
        case .left: return (CGPoint(x: frame.minX + 80, y: along), CGPoint(x: frame.minX + 1, y: along))
        case .right: return (CGPoint(x: frame.maxX - 80, y: along), CGPoint(x: frame.maxX - 1, y: along))
        }
    }
    static func zones(screens: [CGRect], locked: Int, orientation: DockPreviewOrientation) -> [Zone] {
        guard screens.indices.contains(locked), screens.count > 1,
              !exposed(screens[locked], screens: screens, orientation: orientation).isEmpty else { return [] }
        return screens.enumerated().filter { $0.offset != locked }.flatMap { _, frame in
            exposed(frame, screens: screens, orientation: orientation).map { interval in
                switch orientation {
                case .bottom: return Zone(rect: CGRect(x: interval.lowerBound, y: frame.maxY - 7, width: interval.upperBound - interval.lowerBound, height: 7), dx: 0, dy: -7)
                case .left: return Zone(rect: CGRect(x: frame.minX, y: interval.lowerBound, width: 7, height: interval.upperBound - interval.lowerBound), dx: 7, dy: 0)
                case .right: return Zone(rect: CGRect(x: frame.maxX - 7, y: interval.lowerBound, width: 7, height: interval.upperBound - interval.lowerBound), dx: -7, dy: 0)
                }
            }
        }
    }
}
