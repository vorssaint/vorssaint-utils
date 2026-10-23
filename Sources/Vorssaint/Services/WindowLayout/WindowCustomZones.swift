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
