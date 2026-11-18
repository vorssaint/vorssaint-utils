// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BrowserPickerSupport {
    // Match the flat Simple List window row at the switcher's Small size.
    // Keep it independent of the user's current switcher size preference.
    static let scale = PreviewSizing.scale(for: "small")
    static let itemWidth: CGFloat = 120 * scale + 12
    static let itemSpacing: CGFloat = 12 * scale
    static let horizontalPadding: CGFloat = (20 + 8) * scale
    static let verticalPadding: CGFloat = 20 * scale + 3
    static let iconSize: CGFloat = 68 * scale
    static let selectedIconSize: CGFloat = 78 * scale
    static let itemHeight: CGFloat = selectedIconSize + 5 + 14 + 10
    static let height: CGFloat = itemHeight + verticalPadding * 2

    /// Drop onto a row moves before it when moving up, after it when moving down.
    /// Invalid or stale drag identities leave the order untouched.
    static func reorderedIDs(_ ids: [String], moving source: String, onto target: String) -> [String] {
        guard source != target, let from = ids.firstIndex(of: source),
              let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        let moving = result.remove(at: from)
        result.insert(moving, at: to)
        return result
    }

    static func hiddenIDs(_ saved: String) -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(saved.utf8))) ?? [])
    }

    /// AppKit uses screen points. Keep the requested size at ordinary scales,
    /// and scroll horizontally only when the available screen is narrower.
    static func windowFrame(browserCount: Int, visibleFrame: CGRect,
                            cursor: CGPoint, placement: String) -> CGRect {
        let count = max(0, browserCount)
        let requestedWidth = count == 0 ? 320
            : CGFloat(count) * itemWidth + CGFloat(max(0, count - 1)) * itemSpacing + horizontalPadding * 2
        let bounds = visibleFrame.insetBy(dx: 8, dy: 8)
        let size = CGSize(width: min(requestedWidth, max(1, bounds.width)),
                          height: min(height, max(1, bounds.height)))
        var origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        if placement == "cursor" {
            origin.x = cursor.x + 12
            if origin.x + size.width > bounds.maxX { origin.x = cursor.x - size.width - 12 }
            origin.y = cursor.y - size.height - 12
            if origin.y < bounds.minY { origin.y = cursor.y + 12 }
        }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    static func orderedIDs(available: [String], saved: String) -> [String] {
        let stored = (try? JSONDecoder().decode([String].self, from: Data(saved.utf8))) ?? []
        let installed = Set(available)
        var seen = Set<String>()
        return (stored + available).filter { installed.contains($0) && seen.insert($0).inserted }
    }

    static func encodedOrder(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func webURLs(_ urls: [URL]) -> [URL] {
        urls.filter {
            ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host?.isEmpty == false
        }
    }

    static func isPicker(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier
            || bundleID == "com.vorssaint.utils" || bundleID == "com.vorssaint.utils.dev"
    }
}
