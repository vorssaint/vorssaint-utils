// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowZonesTests {
    static func run(_ suite: TestSuite) {
        layouts(suite)
        hitTesting(suite)
        navigation(suite)
        gridEditing(suite)
        preferences(suite)
        dragClassification(suite)
    }

    private static let area = WindowZoneRect(left: 0, top: 0, right: 1920, bottom: 1080)

    private static func layout(_ kind: WindowZoneLayoutKind, _ count: Int, spacing: Int = 0) -> WindowZoneLayout {
        WindowZoneLayout(kind: kind, zoneCount: count, spacing: spacing, showSpacing: spacing != 0)
    }

    private static func layouts(_ suite: TestSuite) {
        let columns = WindowZoneGeometry.zones(for: layout(.columns, 3), in: area, customLayouts: [])
        suite.expect(columns == [
            WindowZoneRect(left: 0, top: 0, right: 640, bottom: 1080),
            WindowZoneRect(left: 640, top: 0, right: 1280, bottom: 1080),
            WindowZoneRect(left: 1280, top: 0, right: 1920, bottom: 1080),
        ], "three columns split the work area evenly")

        let spaced = WindowZoneGeometry.zones(for: layout(.rows, 2, spacing: 10), in: area, customLayouts: [])
        suite.expect(spaced.first == WindowZoneRect(left: 10, top: 10, right: 1910, bottom: 535)
                        && spaced.last == WindowZoneRect(left: 10, top: 545, right: 1910, bottom: 1070),
                     "rows keep a full gap at the edges and between zones")

        let grid = WindowZoneGeometry.zones(for: layout(.grid, 5), in: area, customLayouts: [])
        suite.expect(grid.count == 5 && grid[4] == WindowZoneRect(left: 639, top: 540, right: 1920, bottom: 1080),
                     "the grid template gives leftover cells to its last zone")

        let priority = WindowZoneGeometry.zones(for: layout(.priorityGrid, 3), in: area, customLayouts: [])
        suite.expect(priority.map(\.width) == [480, 960, 480],
                     "the priority grid puts a wide zone in the middle")
        suite.expect(WindowZoneGeometry.zones(for: layout(.priorityGrid, 12), in: area, customLayouts: []).count == 12,
                     "priority grids past the table fall back to the plain grid")

        let shifted = WindowZoneGeometry.zones(for: layout(.columns, 2),
                                               in: WindowZoneRect(left: 1920, top: 25, right: 3840, bottom: 1105),
                                               customLayouts: [])
        suite.expect(shifted.first?.left == 1920 && shifted.first?.top == 25,
                     "zones are placed in the display's global coordinates")

        let canvas = WindowZoneCustomLayout(id: UUID(), name: "Canvas",
                                            shape: .canvas(WindowZoneCanvas(
                                                referenceWidth: 100, referenceHeight: 100,
                                                zones: [WindowZoneRect(left: 0, top: 0, right: 50, bottom: 100),
                                                        WindowZoneRect(left: 25, top: 25, right: 75, bottom: 75)])))
        let canvasZones = WindowZoneGeometry.zones(for: .custom(canvas), in: area, customLayouts: [canvas])
        suite.expect(canvasZones == [WindowZoneRect(left: 0, top: 0, right: 960, bottom: 1080),
                                     WindowZoneRect(left: 480, top: 270, right: 1440, bottom: 810)],
                     "canvas zones scale from their reference size")
        suite.expect(WindowZoneGeometry.zones(for: .custom(canvas), in: area, customLayouts: []).isEmpty,
                     "a layout whose custom shape is gone lays out no zones")
        suite.expect(WindowZoneGeometry.zones(for: layout(.columns, 0), in: area, customLayouts: []).isEmpty
                        && WindowZoneGeometry.zones(for: layout(.columns, 3),
                                                    in: WindowZoneRect(left: 0, top: 0, right: 0, bottom: 0),
                                                    customLayouts: []).isEmpty,
                     "an empty count or an empty work area yields no zones")
    }

    private static func hitTesting(_ suite: TestSuite) {
        let zones = WindowZoneGeometry.zones(for: layout(.columns, 2), in: area, customLayouts: [])
        suite.expect(WindowZoneGeometry.zones(at: CGPoint(x: 300, y: 500), in: zones, sensitivity: 20,
                                              policy: .smallest) == [0],
                     "a point inside one zone picks that zone")
        suite.expect(WindowZoneGeometry.zones(at: CGPoint(x: 955, y: 500), in: zones, sensitivity: 20,
                                              policy: .smallest) == [0, 1],
                     "a drop on the border between two zones takes both")
        let overlapping = [WindowZoneRect(left: 0, top: 0, right: 1000, bottom: 1000),
                           WindowZoneRect(left: 200, top: 200, right: 600, bottom: 600)]
        suite.expect(WindowZoneGeometry.zones(at: CGPoint(x: 400, y: 400), in: overlapping, sensitivity: 20,
                                              policy: .smallest) == [1]
                        && WindowZoneGeometry.zones(at: CGPoint(x: 400, y: 400), in: overlapping, sensitivity: 20,
                                                    policy: .largest) == [0],
                     "overlapping zones are settled by the chosen policy")
        let quarters = WindowZoneGeometry.zones(for: layout(.grid, 4), in: area, customLayouts: [])
        suite.expect(WindowZoneGeometry.combinedRange([0], [3], in: quarters) == [0, 1, 2, 3]
                        && WindowZoneGeometry.combinedRange([0], [1], in: quarters) == [0, 1],
                     "spanning takes every zone inside the bounding box")
    }

    private static func navigation(_ suite: TestSuite) {
        let zones = [WindowZoneRect(left: 100, top: 0, right: 200, bottom: 100),
                     WindowZoneRect(left: 0, top: 100, right: 100, bottom: 200)]
        let window = WindowZoneRect(left: 0, top: 0, right: 100, bottom: 100)
        suite.expect(WindowZoneGeometry.nextZone(from: window, direction: .right, among: zones) == 0
                        && WindowZoneGeometry.nextZone(from: window, direction: .down, among: zones) == 1
                        && WindowZoneGeometry.nextZone(from: window, direction: .left, among: zones) == nil,
                     "the next zone lies ahead of the window, never behind it")

        let left = WindowZoneArea(displayKey: "left", workArea: area,
                                  zones: WindowZoneGeometry.zones(for: layout(.columns, 2), in: area, customLayouts: []))
        let rightArea = area.offsetBy(dx: 1920, dy: 0)
        let right = WindowZoneArea(displayKey: "right", workArea: rightArea,
                                   zones: WindowZoneGeometry.zones(for: layout(.columns, 2), in: rightArea,
                                                                   customLayouts: []))
        let inSecond = left.zones[1]
        let assigned = WindowZoneAssignment(displayKey: "left", zones: [1])
        suite.expect(WindowZoneNavigation.snap(window: inSecond, current: 0, areas: [left, right], assigned: assigned,
                                               direction: .right, acrossDisplays: true)
                        == WindowZoneAssignment(displayKey: "right", zones: [0]),
                     "moving right from the last zone continues on the next display")
        suite.expect(WindowZoneNavigation.snap(window: inSecond, current: 0, areas: [left, right], assigned: assigned,
                                               direction: .right, acrossDisplays: false)
                        == WindowZoneAssignment(displayKey: "left", zones: [0]),
                     "without crossing displays the move wraps around")

        suite.expect(WindowZoneGeometry.window(left.zones[1].offsetBy(dx: 6, dy: -4), fills: [1], of: left.zones)
                        && !WindowZoneGeometry.window(WindowZoneRect(left: 520, top: 300, right: 1020, bottom: 700),
                                                      fills: [1], of: left.zones)
                        && !WindowZoneGeometry.window(left.zones[1], fills: [7], of: left.zones),
                     "a window keeps its zones only while it still sits in them")

        var state: WindowZoneNavigation.Extension?
        let grown = WindowZoneNavigation.extend(window: left.zones[0], windowID: 7, area: left, assigned: [0],
                                                state: &state, direction: .right)
        suite.expect(grown == [0, 1] && state?.anchor == [0] && state?.reach == 1,
                     "extending grows the window into the neighbouring zone")
    }

    private static func gridEditing(_ suite: TestSuite) {
        let single = WindowZoneGrid.uniform(rows: 1, columns: 1)
        let halves = WindowZoneGridEditor.split(single, zone: 0, at: 0.5, horizontal: false)
        suite.expect(halves.columnPercents == [5000, 5000] && halves.cells == [[0, 1]],
                     "a vertical split adds a column")
        let three = WindowZoneGridEditor.split(halves, zone: 1, at: 0.25, horizontal: true)
        suite.expect(three.rowPercents == [2500, 7500] && three.cells == [[0, 1], [0, 2]],
                     "a horizontal split in one zone leaves its neighbour whole")
        let merged = WindowZoneGridEditor.merge(three, zones: [1, 2])
        suite.expect(merged == halves, "merging folds the rows that no longer separate anything")
        let lShape = WindowZoneGrid(rowPercents: [5000, 5000], columnPercents: [5000, 5000],
                                    cells: [[0, 0], [1, 2]])
        suite.expect(WindowZoneGridEditor.merge(lShape, zones: [0, 1]).cells == [[0]],
                     "a merge grows until it holds whole zones")
        let moved = WindowZoneGridEditor.moveBorder(halves, after: 0, horizontal: false, delta: 9000)
        suite.expect(moved.columnPercents == [9500, 500], "a border stops short of collapsing a track")
        suite.expect(WindowZoneGridEditor.split(single, zone: 0, at: 0.001, horizontal: true) == single,
                     "a split too close to the edge does nothing")
    }

    private static func preferences(_ suite: TestSuite) {
        var configuration = WindowZonesConfiguration()
        let custom = WindowZoneCustomLayout(id: UUID(), name: "Mine", shape: .grid(.uniform(rows: 2, columns: 2)))
        configuration.customLayouts = [custom]
        configuration.setLayout(.custom(custom), forDisplay: "A", space: 5, perSpace: true)
        configuration.setLayout(layout(.rows, 2), forDisplay: "A", space: 5, perSpace: false)
        suite.expect(configuration.layout(forDisplay: "A", space: 5, perSpace: true).kind == .rows,
                     "a layout picked for the display applies on all of its Spaces")
        configuration.setLayout(.custom(custom), forDisplay: "A", space: 9, perSpace: true)
        suite.expect(configuration.layout(forDisplay: "A", space: 9, perSpace: true).kind == .custom
                        && configuration.layout(forDisplay: "A", space: 9, perSpace: false).kind == .rows,
                     "a Space keeps its own layout only while layouts follow Spaces")
        configuration.quickLayouts = ["1": layout(.rows, 2), "2": .custom(custom)]
        suite.expect(configuration.cycled(from: layout(.rows, 2), forward: true)?.customID == custom.id
                        && configuration.cycled(from: .custom(custom), forward: true)?.kind == .rows,
                     "the scroll wheel cycles through the quick-switch layouts")
        configuration.removeCustomLayout(custom.id)
        suite.expect(configuration.spaceLayouts["A"]?.isEmpty == true && configuration.quickLayouts.count == 1,
                     "removing a custom layout drops every reference to it")
        let decoded = WindowZonesConfiguration.decode(configuration.encoded)
        suite.expect(decoded == configuration, "the configuration survives a round trip")
        suite.expect(WindowZonesConfiguration.decode(Data("not json".utf8)) == WindowZonesConfiguration(),
                     "unreadable data falls back to an empty configuration")

        var history = WindowZoneHistory()
        for index in 0...WindowZoneHistory.limit {
            history.record(.init(displayKey: "A", layout: .standard, zones: [0]), for: "app\(index)")
        }
        suite.expect(history.apps.count == WindowZoneHistory.limit
                        && history.apps["app\(WindowZoneHistory.limit)"] != nil,
                     "the new-window history stays bounded and keeps the latest app")
        suite.expect(WindowZoneColors.hex(red: 0, green: 0.4706, blue: 0.8431) == "#0078D7"
                        && WindowZoneColors.components("#0078D7").map { Int(($0.blue * 255).rounded()) } == 215
                        && WindowZoneColors.components("nope") == nil,
                     "zone colors round-trip through hex")
    }

    private static func dragClassification(_ suite: TestSuite) {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let titleBar = WindowZoneDragClassifier.pressIsInTitleBar(CGPoint(x: 400, y: 110), frame: frame)
        suite.expect(titleBar && !WindowZoneDragClassifier.pressIsInTitleBar(CGPoint(x: 103, y: 110), frame: frame)
                        && !WindowZoneDragClassifier.pressIsInTitleBar(CGPoint(x: 400, y: 300), frame: frame),
                     "only the strip at the top, away from the resize edges, is the title bar")
        let resizedOnPress = CGRect(x: 100, y: 100, width: 700, height: 500)
        suite.expect(WindowZoneDragClassifier.classify(start: frame, now: resizedOnPress, pressInTitleBar: true) == .moving,
                     "a tiled window macOS resizes at the start of a title-bar drag still counts as moving")
        suite.expect(WindowZoneDragClassifier.classify(start: frame, now: resizedOnPress, pressInTitleBar: false) == .resizing,
                     "a size change from anywhere else is a resize")
        suite.expect(WindowZoneDragClassifier.classify(start: frame, now: frame, pressInTitleBar: true) == .undecided,
                     "a window that has not changed yet leaves the drag undecided")
    }
}
