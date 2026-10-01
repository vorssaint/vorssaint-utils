// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One installed app as Launchpad Classic shows it: just enough to draw a
/// tile and launch it, independent of `InstalledApps.InstalledApp`'s own
/// AppKit-backed `icon` property so this stays a plain value type.
struct LaunchpadApp: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    let bundleID: String?
    let path: String
}

/// The app grid's pure logic: which apps show, in what order, and how they
/// split across pages. No file scanning and no AppKit here — see
/// `LaunchpadAppCatalog` for the real installed-app scan this feeds from.
enum LaunchpadAppSupport {
    /// Matches the real Launchpad's default grid (7 columns, 5 rows, 35 per
    /// page); not yet display-size adaptive, since v1 targets the
    /// single-display case like the original did.
    static let columns = 7
    static let rows = 5
    static var perPage: Int { columns * rows }

    static func apps(from installed: [InstalledApps.InstalledApp]) -> [LaunchpadApp] {
        installed.map { LaunchpadApp(id: $0.id, name: $0.name, bundleID: $0.bundleID, path: $0.url.path) }
    }

    static func filtered(_ apps: [LaunchpadApp], query: String) -> [LaunchpadApp] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    static func pages(_ apps: [LaunchpadApp], perPage: Int = perPage) -> [[LaunchpadApp]] {
        guard !apps.isEmpty, perPage > 0 else { return [] }
        return stride(from: 0, to: apps.count, by: perPage).map { Array(apps[$0..<min($0 + perPage, apps.count)]) }
    }

    /// An open folder is a small Launchpad in miniature: its own grid, its
    /// own pages once it holds more than one page can show. Smaller than
    /// the outer grid since the folder tray itself doesn't fill the screen.
    static let folderColumns = 4
    static let folderRows = 3
    static var folderPerPage: Int { folderColumns * folderRows }

    static func folderPages(_ apps: [LaunchpadApp]) -> [[LaunchpadApp]] {
        pages(apps, perPage: folderPerPage)
    }
}

enum LaunchpadArrowDirection {
    case up, down, left, right
}

/// Arrow-key navigation across the current page's tiles: a flat array
/// index moved by one column's worth of tiles for up/down. Clamped rather
/// than wrapping, and clamped rather than crossing into another page — a
/// page change is its own explicit action (⌘←/→), not a side effect of
/// walking off an edge.
enum LaunchpadSelectionSupport {
    static func moved(current: Int?, direction: LaunchpadArrowDirection, count: Int, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current, (0..<count).contains(current) else { return 0 }
        switch direction {
        case .left: return current > 0 ? current - 1 : current
        case .right: return current < count - 1 ? current + 1 : current
        case .up:
            let target = current - columns
            return target >= 0 ? target : current
        case .down:
            let target = current + columns
            return target < count ? target : current
        }
    }
}

/// Turns a trackpad swipe's cumulative horizontal travel into a page step,
/// the same threshold-crossing shape real paged UI (Launchpad, Home Screen)
/// uses: nothing happens until the swipe has gone far enough one way.
enum LaunchpadPagingSupport {
    static let swipeThreshold: CGFloat = 80
    /// How often a drag held over a screen edge advances a page, matching
    /// the original's own "drag to the edge, wait, it pages" pacing.
    static let edgePagingInterval: TimeInterval = 0.6

    /// -1/+1 once `cumulativeX` crosses the threshold in that direction, 0
    /// otherwise. Scroll's own sign convention is a leftward swipe
    /// producing a positive delta, which reads as "reveal the next page".
    static func pageStep(cumulativeX: CGFloat) -> Int {
        guard cumulativeX.isFinite else { return 0 }
        if cumulativeX >= swipeThreshold { return 1 }
        if cumulativeX <= -swipeThreshold { return -1 }
        return 0
    }

    /// Clamps a page step to a valid index, or nil when it doesn't move.
    static func targetPage(current: Int, step: Int, pageCount: Int) -> Int? {
        guard pageCount > 0, step != 0 else { return nil }
        let target = current + step
        guard (0..<pageCount).contains(target) else { return nil }
        return target
    }

    /// The page a horizontal position within the dots row maps to, for
    /// dragging across the dots like a scrubber instead of only tapping one.
    static func scrubbedPage(x: CGFloat, width: CGFloat, pageCount: Int) -> Int {
        guard pageCount > 0, width > 0, x.isFinite else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        return min(Int(fraction * CGFloat(pageCount)), pageCount - 1)
    }
}

/// The four-finger pinch that opened the real Launchpad, detected the same
/// way any multitouch utility reads a pinch: the touches' spread (mean
/// distance from their centroid) shrinking quickly. `MiddleClickSupport`'s
/// own tap detector already treats any spread change past 0.04 as a pinch to
/// stay clear of — this asks for a shrink well past that, so a deliberate
/// close is never confused with a resting-finger tap and vice versa.
enum LaunchpadPinchSupport {
    /// A pinch this slow is fingers resting or drifting apart, not a
    /// deliberate close.
    static let maximumDuration: TimeInterval = 0.6
    /// The spread must shrink by at least this fraction of where it started
    /// to count as a close.
    static let minimumShrinkFraction: Float = 0.3

    static func isPinchClose(startSpread: Float, endSpread: Float, duration: TimeInterval) -> Bool {
        guard startSpread > 0, endSpread.isFinite, duration.isFinite,
              duration > 0, duration <= maximumDuration
        else { return false }
        let shrink = (startSpread - endSpread) / startSpread
        return shrink >= minimumShrinkFraction
    }
}
