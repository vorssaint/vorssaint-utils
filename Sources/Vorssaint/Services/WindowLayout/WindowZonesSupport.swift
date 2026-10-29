// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Window zones: layouts of rectangles per display that a window is dropped
/// into, modelled on PowerToys FancyZones. Everything here is pure geometry
/// over integer rectangles in the window server's top-left coordinates, so
/// the zone math, hit testing and keyboard navigation are testable without a
/// display.

/// A rectangle in whole points, edges inclusive on the left/top and
/// exclusive on the right/bottom, like the zone math it comes from.
struct WindowZoneRect: Equatable, Hashable, Codable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int

    init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    init(_ rect: CGRect) {
        let standard = rect.standardized
        self.init(left: Int(standard.minX.rounded()), top: Int(standard.minY.rounded()),
                  right: Int(standard.maxX.rounded()), bottom: Int(standard.maxY.rounded()))
    }

    var width: Int { right - left }
    var height: Int { bottom - top }
    var area: Int { max(width, 0) * max(height, 0) }
    var cgRect: CGRect { CGRect(x: left, y: top, width: width, height: height) }
    var center: CGPoint { CGPoint(x: Double(left + right) / 2, y: Double(top + bottom) / 2) }

    func offsetBy(dx: Int, dy: Int) -> WindowZoneRect {
        WindowZoneRect(left: left + dx, top: top + dy, right: right + dx, bottom: bottom + dy)
    }

    func union(_ other: WindowZoneRect) -> WindowZoneRect {
        WindowZoneRect(left: min(left, other.left), top: min(top, other.top),
                       right: max(right, other.right), bottom: max(bottom, other.bottom))
    }

    func contains(_ other: WindowZoneRect) -> Bool {
        other.left >= left && other.top >= top && other.right <= right && other.bottom <= bottom
    }
}

enum WindowZoneLayoutKind: String, Codable, CaseIterable, Identifiable {
    case blank, focus, columns, rows, grid, priorityGrid, custom

    var id: String { rawValue }

    /// Kinds offered as ready-made templates; custom layouts are listed on
    /// their own.
    static let templates: [WindowZoneLayoutKind] = [.focus, .columns, .rows, .grid, .priorityGrid]

    var usesZoneCount: Bool { self != .blank && self != .custom }
}

/// A grid of cells in ten-thousandths of the work area. Cells sharing an id
/// form one zone, so merged cells are just repeated ids.
struct WindowZoneGrid: Codable, Equatable {
    var rowPercents: [Int]
    var columnPercents: [Int]
    var cells: [[Int]]

    static let multiplier = 10_000

    var rows: Int { rowPercents.count }
    var columns: Int { columnPercents.count }

    var isValid: Bool {
        rows > 0 && columns > 0 && cells.count == rows && cells.allSatisfy { $0.count == columns }
            && rowPercents.allSatisfy { $0 > 0 } && columnPercents.allSatisfy { $0 > 0 }
    }

    var zoneCount: Int { Set(cells.joined()).count }

    /// Evenly spaced rows and columns, one zone per cell.
    static func uniform(rows: Int, columns: Int) -> WindowZoneGrid {
        let rows = max(rows, 1), columns = max(columns, 1)
        var cells: [[Int]] = []
        for row in 0..<rows { cells.append((0..<columns).map { row * columns + $0 }) }
        return WindowZoneGrid(rowPercents: evenPercents(rows), columnPercents: evenPercents(columns),
                              cells: cells)
    }

    static func evenPercents(_ count: Int) -> [Int] {
        (0..<count).map { multiplier * ($0 + 1) / count - multiplier * $0 / count }
    }
}

/// Free-form zones in reference units, scaled to the work area they land on.
struct WindowZoneCanvas: Codable, Equatable {
    var referenceWidth: Int
    var referenceHeight: Int
    var zones: [WindowZoneRect]
}

enum WindowZoneCustomShape: Codable, Equatable {
    case grid(WindowZoneGrid)
    case canvas(WindowZoneCanvas)

    var zoneCount: Int {
        switch self {
        case .grid(let grid): return grid.zoneCount
        case .canvas(let canvas): return canvas.zones.count
        }
    }
}

struct WindowZoneCustomLayout: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var shape: WindowZoneCustomShape
    var spacing: Int = WindowZoneLayout.defaultSpacing
    var showSpacing: Bool = true
    var sensitivityRadius: Int = WindowZoneLayout.defaultSensitivity
}

/// The layout a display (or one of its Spaces) uses: a template with its
/// zone count, or a reference to a custom layout.
struct WindowZoneLayout: Codable, Hashable {
    static let defaultZoneCount = 3
    static let defaultSpacing = 16
    static let defaultSensitivity = 20
    static let maximumZoneCount = 40

    var kind: WindowZoneLayoutKind
    var customID: UUID?
    var zoneCount: Int = defaultZoneCount
    var spacing: Int = defaultSpacing
    var showSpacing: Bool = true
    var sensitivityRadius: Int = defaultSensitivity

    static let standard = WindowZoneLayout(kind: .priorityGrid)

    static func custom(_ layout: WindowZoneCustomLayout) -> WindowZoneLayout {
        WindowZoneLayout(kind: .custom, customID: layout.id, zoneCount: layout.shape.zoneCount,
                         spacing: layout.spacing, showSpacing: layout.showSpacing,
                         sensitivityRadius: layout.sensitivityRadius)
    }

    var effectiveSpacing: Int { showSpacing ? max(spacing, 0) : 0 }

    /// Whether two choices describe the same layout. Spacing and radius are
    /// tuning, so a quick-switch key still matches after they change.
    func isSameLayout(as other: WindowZoneLayout) -> Bool {
        kind == other.kind && customID == other.customID
            && (kind == .custom || zoneCount == other.zoneCount)
    }
}

enum WindowZoneOverlapPolicy: String, Codable, CaseIterable, Identifiable {
    case smallest, largest, positional, closestCenter
    var id: String { rawValue }
}

enum WindowZoneDirection: CaseIterable {
    case left, right, up, down

    var vector: (x: Double, y: Double) {
        switch self {
        case .left: return (-1, 0)
        case .right: return (1, 0)
        case .up: return (0, -1)
        case .down: return (0, 1)
        }
    }
}

enum WindowZoneGeometry {
    /// A zone may stick out of the work area by this much with negative
    /// spacing before the layout is rejected.
    static let maximumNegativeSpacing = -20

    private static func isValid(_ rect: WindowZoneRect) -> Bool {
        rect.left >= maximumNegativeSpacing && rect.top >= maximumNegativeSpacing
            && rect.right >= maximumNegativeSpacing && rect.bottom >= maximumNegativeSpacing
            && rect.width >= 0 && rect.height >= 0
    }

    /// The zones of `layout` on `workArea`, in global coordinates and in zone
    /// id order. Empty when the layout cannot be laid out there.
    static func zones(for layout: WindowZoneLayout,
                      in workArea: WindowZoneRect,
                      customLayouts: [WindowZoneCustomLayout]) -> [WindowZoneRect] {
        relativeZones(for: layout, width: workArea.width, height: workArea.height,
                      customLayouts: customLayouts)?
            .map { $0.offsetBy(dx: workArea.left, dy: workArea.top) } ?? []
    }

    static func relativeZones(for layout: WindowZoneLayout, width: Int, height: Int,
                              customLayouts: [WindowZoneCustomLayout]) -> [WindowZoneRect]? {
        guard width > 0, height > 0 else { return nil }
        let count = min(layout.zoneCount, WindowZoneLayout.maximumZoneCount)
        if layout.kind.usesZoneCount, count <= 0 { return nil }
        let spacing = layout.effectiveSpacing
        switch layout.kind {
        case .blank: return []
        case .focus: return focus(width: width, height: height, count: count)
        case .columns: return columns(width: width, height: height, count: count, spacing: spacing)
        case .rows: return rows(width: width, height: height, count: count, spacing: spacing)
        case .grid:
            return gridTemplate(count).flatMap { grid(width: width, height: height, grid: $0, spacing: spacing) }
        case .priorityGrid:
            let template = count < 11 ? priorityGridTemplate(count) : gridTemplate(count)
            return template.flatMap { grid(width: width, height: height, grid: $0, spacing: spacing) }
        case .custom:
            guard let custom = customLayouts.first(where: { $0.id == layout.customID }) else { return nil }
            switch custom.shape {
            case .grid(let shape): return grid(width: width, height: height, grid: shape, spacing: spacing)
            case .canvas(let shape): return canvas(width: width, height: height, canvas: shape)
            }
        }
    }

    static func focus(width: Int, height: Int, count: Int) -> [WindowZoneRect]? {
        var rect = WindowZoneRect(left: 100, top: 100,
                                  right: 100 + Int(Double(width) * 0.4),
                                  bottom: 100 + Int(Double(height) * 0.4))
        let step = count <= 1 ? 0 : 50
        var zones: [WindowZoneRect] = []
        for _ in 0..<max(count, 0) {
            guard isValid(rect) else { return nil }
            zones.append(rect)
            rect = rect.offsetBy(dx: step, dy: step)
        }
        return zones
    }

    static func rows(width: Int, height: Int, count: Int, spacing: Int) -> [WindowZoneRect]? {
        let totalWidth = width - spacing * 2
        let totalHeight = height - spacing * (count + 1)
        var top = spacing
        var zones: [WindowZoneRect] = []
        for index in 0..<count {
            let bottom = top + (index + 1) * totalHeight / count - index * totalHeight / count
            let rect = WindowZoneRect(left: spacing, top: top, right: totalWidth + spacing, bottom: bottom)
            guard isValid(rect) else { return nil }
            zones.append(rect)
            top = bottom + spacing
        }
        return zones
    }

    static func columns(width: Int, height: Int, count: Int, spacing: Int) -> [WindowZoneRect]? {
        let totalWidth = width - spacing * (count + 1)
        let totalHeight = height - spacing * 2
        var left = spacing
        var zones: [WindowZoneRect] = []
        for index in 0..<count {
            let right = left + (index + 1) * totalWidth / count - index * totalWidth / count
            let rect = WindowZoneRect(left: left, top: spacing, right: right, bottom: totalHeight + spacing)
            guard isValid(rect) else { return nil }
            zones.append(rect)
            left = right + spacing
        }
        return zones
    }

    /// The grid FancyZones' Grid template builds for `count` zones: as many
    /// rows as fit squarely, the last zone absorbing leftover cells.
    static func gridTemplate(_ count: Int) -> WindowZoneGrid? {
        guard count > 0 else { return nil }
        var rows = 1
        while count / rows >= rows { rows += 1 }
        rows -= 1
        var columns = count / rows
        if count % rows != 0 { columns += 1 }
        var cells = Array(repeating: Array(repeating: 0, count: columns), count: rows)
        var index = 0
        for row in 0..<rows {
            for column in 0..<columns {
                cells[row][column] = index
                index += 1
                if index == count { index -= 1 }
            }
        }
        return WindowZoneGrid(rowPercents: WindowZoneGrid.evenPercents(rows),
                              columnPercents: WindowZoneGrid.evenPercents(columns), cells: cells)
    }

    /// FancyZones' predefined priority grids: a large centre column flanked
    /// by smaller zones, for one to ten zones.
    static func priorityGridTemplate(_ count: Int) -> WindowZoneGrid? {
        let r3 = [3333, 3334, 3333], c3 = [2500, 5000, 2500], c4 = [2500, 2500, 2500, 2500]
        func grid(_ rows: [Int], _ columns: [Int], _ cells: [[Int]]) -> WindowZoneGrid {
            WindowZoneGrid(rowPercents: rows, columnPercents: columns, cells: cells)
        }
        switch count {
        case 1: return grid([10000], [10000], [[0]])
        case 2: return grid([10000], [6667, 3333], [[0, 1]])
        case 3: return grid([10000], c3, [[0, 1, 2]])
        case 4: return grid([5000, 5000], c3, [[0, 1, 2], [0, 1, 3]])
        case 5: return grid([5000, 5000], c3, [[0, 1, 2], [3, 1, 4]])
        case 6: return grid(r3, c3, [[0, 1, 2], [0, 1, 3], [4, 1, 5]])
        case 7: return grid(r3, c3, [[0, 1, 2], [3, 1, 4], [5, 1, 6]])
        case 8: return grid(r3, c4, [[0, 1, 2, 3], [4, 1, 2, 5], [6, 1, 2, 7]])
        case 9: return grid(r3, c4, [[0, 1, 2, 3], [4, 1, 2, 5], [6, 1, 7, 8]])
        case 10: return grid(r3, c4, [[0, 1, 2, 3], [4, 1, 5, 6], [7, 1, 8, 9]])
        default: return nil
        }
    }

    /// Lays a grid out on a work area. Spacing is a full gap at the outer
    /// edges and half a gap on each side of an inner border.
    static func grid(width: Int, height: Int, grid: WindowZoneGrid, spacing: Int) -> [WindowZoneRect]? {
        guard grid.isValid else { return nil }
        func spans(_ percents: [Int], total: Int) -> [(start: Int, end: Int)] {
            var running = 0
            return percents.map { percent in
                let start = running * total / WindowZoneGrid.multiplier
                running += percent
                return (start, running * total / WindowZoneGrid.multiplier)
            }
        }
        let rowSpans = spans(grid.rowPercents, total: height)
        let columnSpans = spans(grid.columnPercents, total: width)
        let cells = grid.cells
        var zones: [Int: WindowZoneRect] = [:]
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let id = cells[row][column]
                guard (row == 0 || cells[row - 1][column] != id),
                      (column == 0 || cells[row][column - 1] != id) else { continue }
                var lastRow = row
                while lastRow + 1 < grid.rows, cells[lastRow + 1][column] == id { lastRow += 1 }
                var lastColumn = column
                while lastColumn + 1 < grid.columns, cells[row][lastColumn + 1] == id { lastColumn += 1 }
                let rect = WindowZoneRect(
                    left: columnSpans[column].start + (column == 0 ? spacing : spacing / 2),
                    top: rowSpans[row].start + (row == 0 ? spacing : spacing / 2),
                    right: columnSpans[lastColumn].end - (lastColumn == grid.columns - 1 ? spacing : spacing / 2),
                    bottom: rowSpans[lastRow].end - (lastRow == grid.rows - 1 ? spacing : spacing / 2))
                guard id >= 0, isValid(rect), zones[id] == nil else { return nil }
                zones[id] = rect
            }
        }
        return zones.keys.sorted().compactMap { zones[$0] }
    }

    static func canvas(width: Int, height: Int, canvas: WindowZoneCanvas) -> [WindowZoneRect]? {
        guard canvas.referenceWidth > 0, canvas.referenceHeight > 0 else { return nil }
        let sx = Double(width) / Double(canvas.referenceWidth)
        let sy = Double(height) / Double(canvas.referenceHeight)
        var zones: [WindowZoneRect] = []
        for zone in canvas.zones {
            let x = Double(zone.left) * sx, y = Double(zone.top) * sy
            let rect = WindowZoneRect(left: Int(x), top: Int(y),
                                      right: Int(x + Double(zone.width) * sx),
                                      bottom: Int(y + Double(zone.height) * sy))
            guard isValid(rect) else { return nil }
            zones.append(rect)
        }
        return zones
    }

    // MARK: - Hit testing

    /// The zones under `point`. Zones within the sensitivity radius that do
    /// not overlap are all returned, which is how a drop on the border
    /// between two zones takes both; overlapping zones are settled by
    /// `policy`.
    static func zones(at point: CGPoint, in zones: [WindowZoneRect], sensitivity: Int,
                      policy: WindowZoneOverlapPolicy) -> [Int] {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        var captured: [Int] = []
        var strictlyInside = 0
        for (index, zone) in zones.enumerated() {
            if zone.left - sensitivity <= x, x <= zone.right + sensitivity,
               zone.top - sensitivity <= y, y <= zone.bottom + sensitivity {
                captured.append(index)
            }
            if zone.left <= x, x < zone.right, zone.top <= y, y < zone.bottom {
                strictlyInside += 1
            }
        }
        if captured.count == 1, strictlyInside == 0 { return [] }
        var overlapping = false
        search: for i in captured.indices {
            for j in captured.indices where j > i {
                let a = zones[captured[i]], b = zones[captured[j]]
                if max(a.top, b.top) + sensitivity < min(a.bottom, b.bottom),
                   max(a.left, b.left) + sensitivity < min(a.right, b.right) {
                    overlapping = true
                    break search
                }
            }
        }
        guard overlapping else { return captured }
        func pick(_ better: (WindowZoneRect, WindowZoneRect) -> Bool) -> [Int] {
            var chosen = captured[0]
            for index in captured.dropFirst() where better(zones[index], zones[chosen]) { chosen = index }
            return [chosen]
        }
        switch policy {
        case .smallest: return pick { $0.area < $1.area }
        case .largest: return pick { $0.area > $1.area }
        case .closestCenter:
            func distance(_ rect: WindowZoneRect) -> Double {
                let center = rect.center
                return pow(center.x - Double(x), 2) + pow(center.y - Double(y), 2)
            }
            return pick { distance($0) < distance($1) }
        case .positional:
            let half = sensitivity / 2
            var overlap = zones[captured[0]]
            overlap = WindowZoneRect(left: overlap.left - half, top: overlap.top - half,
                                     right: overlap.right + half, bottom: overlap.bottom + half)
            for index in captured.dropFirst() {
                let zone = zones[index]
                overlap.left = max(overlap.left, zone.left - half)
                overlap.top = max(overlap.top, zone.top - half)
                overlap.right = min(overlap.right, zone.right + half)
                overlap.bottom = min(overlap.bottom, zone.bottom + half)
            }
            let width = max(overlap.width, 1), height = max(overlap.height, 1)
            let n = captured.count
            let slot = height > width ? (y - overlap.top) * n / height : (x - overlap.left) * n / width
            return [captured[min(max(slot, 0), n - 1)]]
        }
    }

    /// Every zone inside the bounding box of `initial` and `final`: spanning
    /// from one zone to another takes everything in between.
    static func combinedRange(_ initial: [Int], _ final: [Int], in zones: [WindowZoneRect]) -> [Int] {
        let ids = Set(initial + final).filter { zones.indices.contains($0) }
        guard let bounds = ids.map({ zones[$0] }).reduce(nil, { (result: WindowZoneRect?, rect) in
            result.map { $0.union(rect) } ?? rect
        }) else { return [] }
        return zones.indices.filter { bounds.contains(zones[$0]) }
    }

    static func bounds(of ids: [Int], in zones: [WindowZoneRect]) -> WindowZoneRect? {
        ids.filter { zones.indices.contains($0) }.map { zones[$0] }
            .reduce(nil) { result, rect in result.map { $0.union(rect) } ?? rect }
    }

    /// Whether a window still covers the zones it was put in. Apps with a
    /// minimum size or size steps land a little off, hence the tolerance.
    static func window(_ window: WindowZoneRect, fills ids: [Int], of zones: [WindowZoneRect],
                       tolerance: Int = 40) -> Bool {
        guard let bounds = bounds(of: ids, in: zones) else { return false }
        return abs(window.left - bounds.left) <= tolerance && abs(window.top - bounds.top) <= tolerance
            && abs(window.right - bounds.right) <= tolerance && abs(window.bottom - bounds.bottom) <= tolerance
    }

    // MARK: - Keyboard navigation

    /// The zone whose centre lies best in `direction` from the window's
    /// centre, by FancyZones' elliptical estimate: straight ahead beats a
    /// nearer zone off to the side.
    static func nextZone(from window: WindowZoneRect, direction: WindowZoneDirection,
                         among candidates: [WindowZoneRect]) -> Int? {
        let eccentricity = 2.0
        let arrow = direction.vector
        let origin = window.center
        var best: Int?
        var smallest = Double.infinity
        for (index, zone) in candidates.enumerated() {
            let center = zone.center
            let dx = center.x + 0.001 * Double(index + 1) - origin.x
            let dy = center.y - origin.y
            let scalar = arrow.x * dx + arrow.y * dy
            guard scalar > 0 else { continue }
            let tangent = abs(tan(acos(scalar / (dx * dx + dy * dy).squareRoot())))
            guard tangent <= 10 else { continue }
            let distance = scalar / (2 * eccentricity / (1 + eccentricity * eccentricity * tangent * tangent))
            if distance.isFinite, distance < smallest {
                smallest = distance
                best = index
            }
        }
        return best
    }

    /// The window moved one work area against the arrow, so a search past
    /// the last zone wraps around to the first.
    static func wrapped(_ window: WindowZoneRect, in area: WindowZoneRect,
                        direction: WindowZoneDirection) -> WindowZoneRect {
        switch direction {
        case .up: return window.offsetBy(dx: 0, dy: area.height)
        case .down: return window.offsetBy(dx: 0, dy: -area.height)
        case .left: return window.offsetBy(dx: area.width, dy: 0)
        case .right: return window.offsetBy(dx: -area.width, dy: 0)
        }
    }
}

/// One display's zones as the keyboard moves see them.
struct WindowZoneArea: Equatable {
    var displayKey: String
    var workArea: WindowZoneRect
    var zones: [WindowZoneRect]
}

/// A window's place: which display and which of its zones.
struct WindowZoneAssignment: Codable, Equatable {
    var displayKey: String
    var zones: [Int]
}

enum WindowZoneNavigation {
    /// Where a snap in `direction` takes the window. Zones it already fills
    /// are skipped; past the last zone the search continues on the other
    /// displays when `acrossDisplays`, and otherwise wraps on this one.
    static func snap(window: WindowZoneRect, current: Int, areas: [WindowZoneArea],
                     assigned: WindowZoneAssignment?, direction: WindowZoneDirection,
                     acrossDisplays: Bool) -> WindowZoneAssignment? {
        guard areas.indices.contains(current) else { return nil }
        let area = areas[current]
        let taken = assigned?.displayKey == area.displayKey ? Set(assigned?.zones ?? []) : []
        let free = area.zones.indices.filter { !taken.contains($0) }
        if let pick = WindowZoneGeometry.nextZone(from: window, direction: direction,
                                                  among: free.map { area.zones[$0] }) {
            return WindowZoneAssignment(displayKey: area.displayKey, zones: [free[pick]])
        }
        if acrossDisplays, areas.count > 1 {
            var rects: [WindowZoneRect] = []
            var owners: [(Int, Int)] = []
            for (index, other) in areas.enumerated() where index != current {
                for (zone, rect) in other.zones.enumerated() {
                    rects.append(rect)
                    owners.append((index, zone))
                }
            }
            if let pick = WindowZoneGeometry.nextZone(from: window, direction: direction, among: rects) {
                return WindowZoneAssignment(displayKey: areas[owners[pick].0].displayKey,
                                            zones: [owners[pick].1])
            }
            for (zone, rect) in area.zones.enumerated() {
                rects.append(rect)
                owners.append((current, zone))
            }
            let everything = areas.map(\.workArea).reduce(area.workArea) { $0.union($1) }
            let moved = WindowZoneGeometry.wrapped(window, in: everything, direction: direction)
            return WindowZoneGeometry.nextZone(from: moved, direction: direction, among: rects).map {
                WindowZoneAssignment(displayKey: areas[owners[$0].0].displayKey, zones: [owners[$0].1])
            }
        }
        let moved = WindowZoneGeometry.wrapped(window, in: area.workArea, direction: direction)
        return WindowZoneGeometry.nextZone(from: moved, direction: direction, among: area.zones).map {
            WindowZoneAssignment(displayKey: area.displayKey, zones: [$0])
        }
    }

    /// Growing a window's zones one step at a time. The anchor is the set it
    /// started from and `reach` the zone the last step added.
    struct Extension: Equatable {
        var windowID: CGWindowID
        var anchor: [Int]
        var reach: Int?
    }

    static func extend(window: WindowZoneRect, windowID: CGWindowID, area: WindowZoneArea,
                       assigned: [Int], state: inout Extension?,
                       direction: WindowZoneDirection) -> [Int]? {
        guard !area.zones.isEmpty else { return nil }
        var used = Set<Int>()
        var origin = window
        if let current = state, current.windowID == windowID, let reach = current.reach,
           area.zones.indices.contains(reach) {
            used.insert(reach)
            origin = area.zones[reach]
        } else {
            used.formUnion(assigned.filter { area.zones.indices.contains($0) })
            state = Extension(windowID: windowID, anchor: [], reach: nil)
        }
        let free = area.zones.indices.filter { !used.contains($0) }
        guard let pick = WindowZoneGeometry.nextZone(from: origin, direction: direction,
                                                     among: free.map { area.zones[$0] })
        else { return nil }
        let target = free[pick]
        if state?.reach == nil {
            state?.anchor = assigned.isEmpty ? [target] : assigned
        }
        state?.reach = target
        return WindowZoneGeometry.combinedRange(state?.anchor ?? [], [target], in: area.zones)
    }
}

// MARK: - Grid editing

/// Splitting and merging the zones of a custom grid, the way the zone
/// editor offers it. Every result is renumbered so zone ids stay in reading
/// order, and rows or columns that no longer separate anything are folded.
enum WindowZoneGridEditor {
    /// Splits `zone` in two at `fraction` (0…1 across the work area) along a
    /// horizontal line when `horizontal`, else a vertical one.
    static func split(_ grid: WindowZoneGrid, zone: Int, at fraction: Double,
                      horizontal: Bool) -> WindowZoneGrid {
        var grid = grid
        guard grid.isValid, Set(grid.cells.joined()).contains(zone) else { return grid }
        let percents = horizontal ? grid.rowPercents : grid.columnPercents
        let target = Int((fraction * Double(WindowZoneGrid.multiplier)).rounded())
        // Lines of the zone along the split direction.
        let lines: [Int] = horizontal
            ? grid.cells.indices.filter { grid.cells[$0].contains(zone) }
            : (0..<grid.columns).filter { column in grid.cells.contains { $0[column] == zone } }
        guard let first = lines.first, let last = lines.last else { return grid }
        var start = percents[..<first].reduce(0, +)
        let end = percents[...last].reduce(0, +)
        guard target > start + 100, target < end - 100 else { return grid }
        // Split the track that holds the line, unless it already ends there.
        var splitAfter = first
        for line in first...last {
            let lineEnd = start + percents[line]
            if target == lineEnd { splitAfter = line; break }
            if target < lineEnd {
                let before = target - start, after = lineEnd - target
                if horizontal {
                    grid.rowPercents.replaceSubrange(line...line, with: [before, after])
                    grid.cells.insert(grid.cells[line], at: line + 1)
                } else {
                    grid.columnPercents.replaceSubrange(line...line, with: [before, after])
                    for row in grid.cells.indices { grid.cells[row].insert(grid.cells[row][line], at: line + 1) }
                }
                splitAfter = line
                break
            }
            start = lineEnd
        }
        let newID = (grid.cells.joined().max() ?? 0) + 1
        for row in grid.cells.indices {
            for column in grid.cells[row].indices where grid.cells[row][column] == zone {
                if (horizontal ? row : column) > splitAfter { grid.cells[row][column] = newID }
            }
        }
        return normalized(grid)
    }

    /// Merges `zones` with everything their bounding box covers into one zone.
    static func merge(_ grid: WindowZoneGrid, zones: Set<Int>) -> WindowZoneGrid {
        guard grid.isValid, zones.count > 1 else { return grid }
        var rows = Set<Int>(), columns = Set<Int>()
        for (row, line) in grid.cells.enumerated() {
            for (column, id) in line.enumerated() where zones.contains(id) {
                rows.insert(row)
                columns.insert(column)
            }
        }
        guard let top = rows.min(), let bottom = rows.max(),
              let left = columns.min(), let right = columns.max() else { return grid }
        var merged = grid
        // A zone half inside the box would no longer be a rectangle, so the
        // box grows until it holds whole zones only.
        var box = (top: top, bottom: bottom, left: left, right: right)
        var changed = true
        while changed {
            changed = false
            let inside = Set((box.top...box.bottom).flatMap { row in
                (box.left...box.right).map { grid.cells[row][$0] }
            })
            for (row, line) in grid.cells.enumerated() {
                for (column, id) in line.enumerated() where inside.contains(id) {
                    if row < box.top { box.top = row; changed = true }
                    if row > box.bottom { box.bottom = row; changed = true }
                    if column < box.left { box.left = column; changed = true }
                    if column > box.right { box.right = column; changed = true }
                }
            }
        }
        let id = grid.cells[box.top][box.left]
        for row in box.top...box.bottom {
            for column in box.left...box.right { merged.cells[row][column] = id }
        }
        return normalized(merged)
    }

    /// Moves the border after track `index` by `delta` ten-thousandths,
    /// keeping every track at least 5% wide.
    static func moveBorder(_ grid: WindowZoneGrid, after index: Int, horizontal: Bool,
                           delta: Int) -> WindowZoneGrid {
        var grid = grid
        var percents = horizontal ? grid.rowPercents : grid.columnPercents
        guard percents.indices.contains(index), percents.indices.contains(index + 1) else { return grid }
        let minimum = 500
        let total = percents[index] + percents[index + 1]
        let first = min(max(percents[index] + delta, minimum), total - minimum)
        percents[index] = first
        percents[index + 1] = total - first
        if horizontal { grid.rowPercents = percents } else { grid.columnPercents = percents }
        return grid
    }

    /// Folds tracks that repeat their neighbour and renumbers zones in
    /// reading order.
    static func normalized(_ grid: WindowZoneGrid) -> WindowZoneGrid {
        var grid = grid
        var row = 1
        while row < grid.cells.count {
            if grid.cells[row] == grid.cells[row - 1] {
                grid.rowPercents[row - 1] += grid.rowPercents[row]
                grid.rowPercents.remove(at: row)
                grid.cells.remove(at: row)
            } else { row += 1 }
        }
        var column = 1
        while column < grid.columnPercents.count {
            if grid.cells.allSatisfy({ $0[column] == $0[column - 1] }) {
                grid.columnPercents[column - 1] += grid.columnPercents[column]
                grid.columnPercents.remove(at: column)
                for index in grid.cells.indices { grid.cells[index].remove(at: column) }
            } else { column += 1 }
        }
        var renumber: [Int: Int] = [:]
        for line in grid.cells {
            for id in line where renumber[id] == nil { renumber[id] = renumber.count }
        }
        grid.cells = grid.cells.map { $0.map { renumber[$0] ?? 0 } }
        return grid
    }
}

// MARK: - Preferences

/// Everything about zones that is set up rather than toggled: custom
/// layouts, the layout of each display and Space, and quick-switch keys.
/// Saved as one JSON value so a backup carries it whole.
struct WindowZonesConfiguration: Codable, Equatable {
    var customLayouts: [WindowZoneCustomLayout] = []
    /// By display UUID.
    var displayLayouts: [String: WindowZoneLayout] = [:]
    /// By display UUID, then Space id. Consulted only while layouts follow
    /// Spaces; a layout picked for the display applies to its other Spaces.
    var spaceLayouts: [String: [String: WindowZoneLayout]] = [:]
    /// Number key ("0"…"9") to the layout it applies.
    var quickLayouts: [String: WindowZoneLayout] = [:]

    func layout(forDisplay display: String, space: UInt64?, perSpace: Bool) -> WindowZoneLayout {
        if perSpace, let space, let layout = spaceLayouts[display]?[String(space)] { return layout }
        return displayLayouts[display] ?? .standard
    }

    mutating func setLayout(_ layout: WindowZoneLayout, forDisplay display: String,
                            space: UInt64?, perSpace: Bool) {
        if perSpace, let space {
            spaceLayouts[display, default: [:]][String(space)] = layout
        } else {
            displayLayouts[display] = layout
            spaceLayouts[display] = nil
        }
    }

    /// Drops references to a removed custom layout.
    mutating func removeCustomLayout(_ id: UUID) {
        customLayouts.removeAll { $0.id == id }
        displayLayouts = displayLayouts.filter { $0.value.customID != id }
        spaceLayouts = spaceLayouts.mapValues { $0.filter { $0.value.customID != id } }
        quickLayouts = quickLayouts.filter { $0.value.customID != id }
    }

    /// Custom layouts carry the zone count of their current shape.
    func refreshed(_ layout: WindowZoneLayout) -> WindowZoneLayout {
        guard layout.kind == .custom,
              let custom = customLayouts.first(where: { $0.id == layout.customID }) else { return layout }
        var layout = layout
        layout.zoneCount = custom.shape.zoneCount
        return layout
    }

    static func decode(_ data: Data?) -> WindowZonesConfiguration {
        guard let data, let value = try? JSONDecoder().decode(WindowZonesConfiguration.self, from: data)
        else { return WindowZonesConfiguration() }
        return value
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }

    /// The next layout in the quick-switch keys after `current`, for the
    /// scroll wheel while zones show.
    func cycled(from current: WindowZoneLayout, forward: Bool) -> WindowZoneLayout? {
        let keys = quickLayouts.keys.sorted()
        guard !keys.isEmpty else { return nil }
        let layouts = keys.compactMap { quickLayouts[$0] }
        let index = layouts.firstIndex { $0.isSameLayout(as: current) }
        let next: Int
        if let index {
            next = (index + (forward ? 1 : layouts.count - 1)) % layouts.count
        } else {
            next = forward ? 0 : layouts.count - 1
        }
        return refreshed(layouts[next])
    }
}

/// Where each app's windows last went, so a new window opens there. Kept
/// per Mac, outside backups, since it names this Mac's displays.
struct WindowZoneHistory: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var displayKey: String
        var layout: WindowZoneLayout
        var zones: [Int]
    }

    var apps: [String: Entry] = [:]
    static let limit = 200

    mutating func record(_ entry: Entry, for bundleID: String) {
        apps[bundleID] = entry
        if apps.count > Self.limit, let stale = apps.keys.first(where: { $0 != bundleID }) {
            apps[stale] = nil
        }
    }

    static func decode(_ data: Data?) -> WindowZoneHistory {
        guard let data, let value = try? JSONDecoder().decode(WindowZoneHistory.self, from: data)
        else { return WindowZoneHistory() }
        return value
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
}

/// How the press that started a drag reads: only a window that moved, or
/// changed size while held by its title bar, counts as a move. macOS resizes
/// a tiled window the moment its drag starts, which must not read as a resize.
enum WindowZoneDragClassifier {
    static let titleBarHeight: CGFloat = 32
    static let resizeEdge: CGFloat = 6

    enum Verdict: Equatable { case undecided, moving, resizing }

    static func pressIsInTitleBar(_ point: CGPoint, frame: CGRect) -> Bool {
        point.y >= frame.minY + 2 && point.y < frame.minY + titleBarHeight
            && point.x >= frame.minX + resizeEdge && point.x < frame.maxX - resizeEdge
    }

    static func classify(start: CGRect, now: CGRect, pressInTitleBar: Bool) -> Verdict {
        let resized = abs(now.width - start.width) >= 1 || abs(now.height - start.height) >= 1
        let moved = abs(now.minX - start.minX) >= 1 || abs(now.minY - start.minY) >= 1
        if resized, !pressInTitleBar { return .resizing }
        return moved || resized ? .moving : .undecided
    }
}

/// Zone colors, stored as `#RRGGBB` so the settings can show and share them.
struct WindowZoneColors: Equatable {
    var fill: String
    var border: String
    var highlight: String
    var opacity: Double

    static let standard = WindowZoneColors(fill: "#F5FCFF", border: "#FFFFFF",
                                           highlight: "#0078D7", opacity: 0.5)

    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
