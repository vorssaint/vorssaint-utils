// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// Coordinates are fractions of the display's *visible* frame, measured from
/// its top left. They survive changes to resolution, scaling and Dock position.
struct WindowCustomZone: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite)
            && x >= 0 && y >= 0 && width >= 0.05 && height >= 0.05
            && x + width <= 1.000001 && y + height <= 1.000001
    }

    func frame(in visibleFrame: CGRect) -> CGRect {
        CGRect(x: visibleFrame.minX + visibleFrame.width * x,
               y: visibleFrame.maxY - visibleFrame.height * (y + height),
               width: visibleFrame.width * width,
               height: visibleFrame.height * height).integral
    }
}

struct WindowCustomZoneScreen {
    let id: String
    let visibleFrame: CGRect
}

struct WindowCustomZoneTarget: Equatable {
    let displayID: String
    let index: Int
    let frame: CGRect
    let visibleFrame: CGRect
}

enum WindowCustomZoneDirection: CaseIterable {
    case left, right, up, down

    var action: WindowLayoutAction {
        switch self {
        case .left: return .customZoneLeft
        case .right: return .customZoneRight
        case .up: return .customZoneUp
        case .down: return .customZoneDown
        }
    }

    var displayDirection: WindowLayoutGeometry.DisplayDirection {
        switch self {
        case .left: return .left
        case .right: return .right
        case .up: return .up
        case .down: return .down
        }
    }
}

/// Only overrides are persisted; disconnected displays retain their layouts.
/// Missing displays receive a two-column layout, or three on ultrawides.
struct WindowCustomZoneLayouts {
    private var byDisplay: [String: [WindowCustomZone]] = [:]

    init(storageValue: String?) {
        guard let value = storageValue, value.utf8.count <= 100_000,
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [WindowCustomZone]].self, from: data)
        else { return }
        for (id, zones) in decoded where !id.isEmpty && id.count <= 128 {
            guard byDisplay.count < 16, !zones.isEmpty, zones.count <= 16,
                  zones.allSatisfy(\.isValid) else { continue }
            byDisplay[id] = zones
        }
    }

    var storageValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(byDisplay),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }

    func zones(for displayID: String, aspectRatio: CGFloat) -> [WindowCustomZone] {
        byDisplay[displayID] ?? Self.columns(aspectRatio >= 2.4 ? 3 : 2)
    }

    mutating func set(_ zones: [WindowCustomZone], for displayID: String) {
        guard !displayID.isEmpty, displayID.count <= 128, !zones.isEmpty,
              zones.count <= 16, zones.allSatisfy(\.isValid) else { return }
        byDisplay[displayID] = zones
    }

    static func columns(_ count: Int) -> [WindowCustomZone] {
        guard (1...8).contains(count) else { return [] }
        return (0..<count).map { column in
            WindowCustomZone(x: Double(column) / Double(count), y: 0,
                             width: 1 / Double(count), height: 1)
        }
    }

    static func grid(columns: Int, rows: Int) -> [WindowCustomZone] {
        guard (1...8).contains(columns), (1...8).contains(rows),
              columns * rows <= 16 else { return [] }
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                WindowCustomZone(x: Double(column) / Double(columns),
                                 y: Double(row) / Double(rows),
                                 width: 1 / Double(columns), height: 1 / Double(rows))
            }
        }
    }

    static func target(at point: CGPoint, screens: [WindowCustomZoneScreen],
                       layouts: WindowCustomZoneLayouts) -> WindowCustomZoneTarget? {
        for screen in screens where screen.visibleFrame.contains(point) {
            let ratio = screen.visibleFrame.width / max(screen.visibleFrame.height, 1)
            for (index, zone) in layouts.zones(for: screen.id, aspectRatio: ratio).enumerated() {
                let frame = zone.frame(in: screen.visibleFrame)
                guard frame.contains(point) else { continue }
                return WindowCustomZoneTarget(displayID: screen.id, index: index,
                                              frame: frame, visibleFrame: screen.visibleFrame)
            }
        }
        return nil
    }

    /// Which zone a window belongs to, judged by its center. Used by the
    /// keyboard focus walk so the walk continues from where the focused
    /// window actually sits.
    static func zoneIndex(containingCenterOf rect: CGRect, zones: [WindowCustomZone],
                          visibleFrame: CGRect) -> Int? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for (index, zone) in zones.enumerated() where zone.frame(in: visibleFrame).contains(center) {
            return index
        }
        return nil
    }

    /// The zone the focus walk moves to. A window outside every zone starts
    /// at the first zone going forward and the last one going backward.
    static func nextZoneIndex(current: Int?, count: Int, forward: Bool) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return forward ? 0 : count - 1 }
        guard (0..<count).contains(current) else { return forward ? 0 : count - 1 }
        return forward ? (current + 1) % count : (current - 1 + count) % count
    }

    /// Finds the nearest zone whose center lies in the requested direction
    /// from the focused window center. The distance tie-breaker keeps custom
    /// grids predictable when two candidates share the same primary axis.
    static func directionalZoneIndex(from rect: CGRect,
                                     zones: [WindowCustomZone],
                                     visibleFrame: CGRect,
                                     direction: WindowCustomZoneDirection) -> Int? {
        let windowCenter = CGPoint(x: rect.midX, y: rect.midY)
        let origin = zones.firstIndex(where: {
            $0.frame(in: visibleFrame).contains(windowCenter)
        }).map {
            let frame = zones[$0].frame(in: visibleFrame)
            return CGPoint(x: frame.midX, y: frame.midY)
        } ?? windowCenter
        let epsilon: CGFloat = 0.5
        let candidates: [(index: Int, distance: CGFloat, crossAxis: CGFloat)] = zones.enumerated().compactMap {
            index, zone in
            let frame = zone.frame(in: visibleFrame)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - origin.x
            let dy = center.y - origin.y
            let primary: CGFloat
            let crossAxis: CGFloat
            switch direction {
            case .left:
                guard dx < -epsilon else { return nil }
                primary = -dx
                crossAxis = abs(dy)
            case .right:
                guard dx > epsilon else { return nil }
                primary = dx
                crossAxis = abs(dy)
            case .up:
                guard dy > epsilon else { return nil }
                primary = dy
                crossAxis = abs(dx)
            case .down:
                guard dy < -epsilon else { return nil }
                primary = -dy
                crossAxis = abs(dx)
            }
            return (index, hypot(dx, dy), crossAxis + primary * 0.0001)
        }
        return candidates.min {
            if abs($0.distance - $1.distance) > epsilon { return $0.distance < $1.distance }
            if abs($0.crossAxis - $1.crossAxis) > epsilon { return $0.crossAxis < $1.crossAxis }
            return $0.index < $1.index
        }?.index
    }

    /// Finds the zone on an adjacent display that continues the source zone's
    /// relative position. Only zones touching the destination display's edge
    /// facing the source display are eligible.
    static func crossDisplayZoneIndex(from rect: CGRect,
                                      sourceZones: [WindowCustomZone],
                                      sourceVisibleFrame: CGRect,
                                      destinationZones: [WindowCustomZone],
                                      destinationVisibleFrame: CGRect,
                                      direction: WindowCustomZoneDirection) -> Int? {
        guard let sourceIndex = zoneIndex(containingCenterOf: rect,
                                          zones: sourceZones,
                                          visibleFrame: sourceVisibleFrame) else { return nil }
        let sourceFrame = sourceZones[sourceIndex].frame(in: sourceVisibleFrame)
        guard touchesEdge(sourceFrame, visibleFrame: sourceVisibleFrame, direction: direction) else {
            return nil
        }

        let sourceAlignment: CGFloat
        switch direction {
        case .left, .right:
            sourceAlignment = (sourceFrame.midY - sourceVisibleFrame.minY)
                / max(sourceVisibleFrame.height, 1)
        case .up, .down:
            sourceAlignment = (sourceFrame.midX - sourceVisibleFrame.minX)
                / max(sourceVisibleFrame.width, 1)
        }

        let candidates = destinationZones.enumerated().compactMap { index, zone -> (Int, CGFloat, CGFloat)? in
            let frame = zone.frame(in: destinationVisibleFrame)
            guard touchesDestinationEdge(frame,
                                         visibleFrame: destinationVisibleFrame,
                                         direction: direction) else { return nil }
            let alignment: CGFloat
            switch direction {
            case .left, .right:
                alignment = abs((frame.midY - destinationVisibleFrame.minY)
                    / max(destinationVisibleFrame.height, 1) - sourceAlignment)
            case .up, .down:
                alignment = abs((frame.midX - destinationVisibleFrame.minX)
                    / max(destinationVisibleFrame.width, 1) - sourceAlignment)
            }
            let facingDistance: CGFloat
            switch direction {
            case .left:
                facingDistance = abs(frame.maxX - destinationVisibleFrame.maxX)
            case .right:
                facingDistance = abs(frame.minX - destinationVisibleFrame.minX)
            case .up:
                facingDistance = abs(frame.minY - destinationVisibleFrame.minY)
            case .down:
                facingDistance = abs(frame.maxY - destinationVisibleFrame.maxY)
            }
            return (index, alignment, facingDistance)
        }

        return candidates.min { lhs, rhs in
            if abs(lhs.1 - rhs.1) > 0.0001 { return lhs.1 < rhs.1 }
            if abs(lhs.2 - rhs.2) > 0.5 { return lhs.2 < rhs.2 }
            return lhs.0 < rhs.0
        }?.0
    }

    private static func touchesEdge(_ frame: CGRect,
                                    visibleFrame: CGRect,
                                    direction: WindowCustomZoneDirection) -> Bool {
        switch direction {
        case .left:
            return abs(frame.minX - visibleFrame.minX) <= 1.5
        case .right:
            return abs(frame.maxX - visibleFrame.maxX) <= 1.5
        case .up:
            return abs(frame.maxY - visibleFrame.maxY) <= 1.5
        case .down:
            return abs(frame.minY - visibleFrame.minY) <= 1.5
        }
    }

    private static func touchesDestinationEdge(_ frame: CGRect,
                                               visibleFrame: CGRect,
                                               direction: WindowCustomZoneDirection) -> Bool {
        switch direction {
        case .left:
            return abs(frame.maxX - visibleFrame.maxX) <= 1.5
        case .right:
            return abs(frame.minX - visibleFrame.minX) <= 1.5
        case .up:
            return abs(frame.minY - visibleFrame.minY) <= 1.5
        case .down:
            return abs(frame.maxY - visibleFrame.maxY) <= 1.5
        }
    }

    /// CoreGraphics' UUID identifies the physical display across reconnects.
    /// The numeric ID is only a fallback for displays without a UUID.
    static func id(for screen: NSScreen) -> String {
        let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                      as? NSNumber)?.uint32Value ?? 0
        if number != 0, let uuid = CGDisplayCreateUUIDFromDisplayID(number) {
            return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
        }
        return "display-\(number)"
    }
}
