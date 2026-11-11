// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The screenshot tool's selection maths, annotations, pixelation and file
/// names, checked without a screen.
enum ScreenshotToolTests {
    private static let screen = ShotRect(x: 0, y: 0, width: 1920, height: 1080)

    static func run(_ suite: TestSuite) {
        geometry(suite)
        toolbars(suite)
        model(suite)
        pixelate(suite)
        files(suite)
        systemShortcuts(suite)
        strings(suite)
    }

    private static func geometry(_ suite: TestSuite) {
        suite.expect(ShotRect.fromCorners(100, 100, 10, 20) == ShotRect(x: 10, y: 20, width: 91, height: 81)
                        && ShotRect.fromCorners(10, 20, 100, 100) == ShotRect(x: 10, y: 20, width: 91, height: 81),
                     "corners in either order span the same rectangle, both corners included")
        suite.expect(ShotRect(x: -50, y: -50, width: 100, height: 100).intersection(screen)
                        == ShotRect(x: 0, y: 0, width: 50, height: 50)
                        && ShotRect(x: 3000, y: 0, width: 10, height: 10).intersection(screen).isEmpty,
                     "an intersection clips to the other rectangle and is empty when apart")
        suite.expect(ShotRect(x: -100, y: 0, width: 100, height: 50).union(screen)
                        == ShotRect(x: -100, y: 0, width: 2020, height: 1080)
                        && ShotRect.zero.union(screen) == screen,
                     "a union spans both rectangles and ignores an empty one")
        suite.expect(ShotRect(storageValue: ShotRect(x: -5, y: 7, width: 30, height: 40).storageValue)
                        == ShotRect(x: -5, y: 7, width: 30, height: 40)
                        && ShotRect(storageValue: "") == nil && ShotRect(storageValue: "1,2,0,4") == nil
                        && ShotRect(storageValue: "1,2,3") == nil && ShotRect(storageValue: "a,b,c,d") == nil,
                     "a remembered selection reads back, and anything else is no selection")

        let sel = ShotRect(x: 100, y: 100, width: 200, height: 200)
        let hits: [(Double, Double, ShotHandle)] = [
            (100, 100, .nw), (300, 100, .ne), (100, 300, .sw), (300, 300, .se),
            (200, 98, .n), (200, 303, .s), (97, 200, .w), (302, 200, .e),
            (200, 200, .inside), (400, 200, .none), (200, 90, .none),
        ]
        for (x, y, expected) in hits {
            suite.expect(ShotGeometry.hitTest(sel, x: x, y: y, grip: 6) == expected,
                         "the handle at \(x), \(y) is \(expected)")
        }
        suite.expect(ShotGeometry.hitTest(.zero, x: 0, y: 0, grip: 6) == .none,
                     "an empty selection has no handles")

        suite.expect(ShotGeometry.drag(sel, handle: .se, dx: 50, dy: 30, bounds: screen)
                        == ShotRect(x: 100, y: 100, width: 250, height: 230)
                        && ShotGeometry.drag(sel, handle: .nw, dx: -20, dy: -10, bounds: screen)
                        == ShotRect(x: 80, y: 90, width: 220, height: 210),
                     "dragging a corner resizes from the opposite corner")
        suite.expect(ShotGeometry.drag(sel, handle: .e, dx: 40, dy: 999, bounds: screen)
                        == ShotRect(x: 100, y: 100, width: 240, height: 200)
                        && ShotGeometry.drag(sel, handle: .n, dx: 999, dy: -40, bounds: screen)
                        == ShotRect(x: 100, y: 60, width: 200, height: 240),
                     "dragging an edge only changes that edge")
        // The right edge (x = 300) dragged to x = 50 goes past the left edge (x = 100).
        suite.expect(ShotGeometry.drag(sel, handle: .e, dx: -250, dy: 0, bounds: screen)
                        == ShotRect(x: 50, y: 100, width: 50, height: 200),
                     "dragging an edge past the opposite one flips the selection")
        suite.expect(ShotGeometry.drag(sel, handle: .nw, dx: -500, dy: -500, bounds: screen)
                        == ShotRect(x: 0, y: 0, width: 300, height: 300)
                        && ShotGeometry.drag(sel, handle: .se, dx: 5000, dy: 5000, bounds: screen)
                        == ShotRect(x: 100, y: 100, width: 1820, height: 980),
                     "resizing stays within the screen")
        suite.expect(ShotGeometry.drag(sel, handle: .inside, dx: 50, dy: -20, bounds: screen)
                        == ShotRect(x: 150, y: 80, width: 200, height: 200)
                        && ShotGeometry.move(sel, dx: 5000, dy: -5000, bounds: screen)
                        == ShotRect(x: 1720, y: 0, width: 200, height: 200),
                     "moving keeps the size and stops at the edges")
        let displays = ShotRect(x: -2560, y: -200, width: 4480, height: 1440)
        suite.expect(ShotGeometry.move(ShotRect(x: -100, y: 100, width: 300, height: 300),
                                       dx: -5000, dy: 0, bounds: displays)
                        == ShotRect(x: -2560, y: 100, width: 300, height: 300),
                     "moving works across displays with negative coordinates")
    }

    private static func toolbars(_ suite: TestSuite) {
        func place(_ sel: ShotRect) -> (tools: (x: Int, y: Int), actions: (x: Int, y: Int)) {
            ShotGeometry.placeToolbars(selection: sel, display: screen, tools: (40, 340), actions: (200, 40), gap: 6)
        }
        var placed = place(ShotRect(x: 100, y: 100, width: 400, height: 300))
        suite.expect(placed.tools == (506, 60) && placed.actions == (300, 406),
                     "the tools go right of the selection, bottom aligned, and the actions below it, right aligned")
        placed = place(ShotRect(x: 1500, y: 700, width: 418, height: 378))
        suite.expect(placed.tools == (1454, 738) && placed.actions == (1718, 654),
                     "near the display's right and bottom edges both toolbars take the opposite side")
        placed = place(screen)
        suite.expect(placed.tools == (1874, 740) && placed.actions == (1720, 1034),
                     "a selection of the whole display keeps both toolbars inside it")
        placed = place(ShotRect(x: 0, y: 0, width: 20, height: 20))
        suite.expect(placed.tools.y == 0 && placed.actions.x == 0,
                     "a tiny selection in a corner keeps both toolbars on the display")
        suite.expect(ShotGeometry.placeSizeLabel(selection: ShotRect(x: 100, y: 100, width: 50, height: 50),
                                                 display: screen, label: (80, 24), gap: 4) == (100, 72)
                        && ShotGeometry.placeSizeLabel(selection: ShotRect(x: 100, y: 10, width: 50, height: 50),
                                                       display: screen, label: (80, 24), gap: 4) == (100, 14),
                     "the size label sits above the top-left corner, or inside it at the display's top")
    }

    private static func shape(_ tool: ShotTool, _ points: (Double, Double)...) -> ShotShape {
        let shape = ShotShape(tool: tool, color: 0xFF0000, width: 3)
        shape.points = points.map { ShotPoint(x: $0.0, y: $0.1) }
        return shape
    }

    private static func model(_ suite: TestSuite) {
        var shapes = ShotShapes()
        let first = shape(.line, (0, 0), (50, 50))
        shapes.add(first)
        shapes.add(shape(.rectangle, (10, 10), (60, 40)))
        let undone = shapes.undo()
        suite.expect(undone && shapes.count == 1 && shapes.items.first === first,
                     "undo removes the newest shape")
        let again = shapes.undo()
        let empty = shapes.undo()
        suite.expect(again && !empty && shapes.count == 0, "undo stops when nothing is left")

        shapes.add(shape(.rectangle, (10, 10), (11, 11)))
        shapes.add(shape(.text, (10, 10)))
        suite.expect(shapes.count == 0, "a click without a drag and empty text are not kept")
        shapes.add(shape(.pen, (10, 10)))
        suite.expect(shapes.count == 1, "a pen click is a dot")
        let text = shape(.text, (10, 10))
        text.text = "hello"
        shapes.add(text)
        suite.expect(shapes.count == 2, "text with content is kept")
        suite.expect(shape(.blur, (100, 50), (20, 10)).bounds == ShotRect(x: 20, y: 10, width: 81, height: 41),
                     "a shape's bounds span its start and end")
    }

    private static func pixelate(_ suite: TestSuite) {
        // 4×2 image: left 2×2 block black and white, right block all grey.
        var w = 4, h = 2, rowBytes = 16
        var px = [UInt8](repeating: 0, count: rowBytes * h)
        func set(_ x: Int, _ y: Int, _ v: UInt8) {
            let i = y * rowBytes + x * 4
            px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
        }
        set(0, 0, 0); set(1, 0, 255); set(0, 1, 255); set(1, 1, 0)
        set(2, 0, 100); set(3, 0, 100); set(2, 1, 100); set(3, 1, 100)
        var result = ShotImage.pixelate(px, stride: rowBytes, region: ShotRect(x: 0, y: 0, width: w, height: h), block: 2)
        suite.expect(result[0] == 127 && result[4] == 127 && result[(w + 1) * 4] == 127
                        && result[2 * 4] == 100 && result[3] == 255,
                     "each block becomes its average colour")

        w = 5; h = 3; rowBytes = 20
        px = [UInt8](repeating: 0, count: rowBytes * h)
        for i in stride(from: 0, to: px.count, by: 4) { px[i] = UInt8(i / 4) } // first channel = pixel index
        result = ShotImage.pixelate(px, stride: rowBytes, region: ShotRect(x: 1, y: 1, width: 3, height: 2), block: 2)
        suite.expect(result.count == 3 * 2 * 4 && result[0] == UInt8((6 + 7 + 11 + 12) / 4)
                        && result[2 * 4] == UInt8((8 + 13) / 2),
                     "a region pixelates on its own, with a leftover column averaged by itself")
        suite.expect(ShotImage.pixelate(px, stride: rowBytes, region: .zero, block: 2).isEmpty,
                     "an empty region has no pixels")
    }

    private static func files(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "UTC") ?? .current
        calendar.timeZone = zone
        let when = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9, minute: 5, second: 7))
            ?? Date()
        func name(_ pattern: String?, taken: Set<String> = []) -> String {
            ShotFiles.name(pattern: pattern, time: when, fileExtension: ".png", timeZone: zone) { taken.contains($0) }
        }
        suite.expect(name(ShotFiles.defaultPattern) == "Screenshot 2026-11-01 09.05.07",
                     "the default pattern uses the capture time")
        suite.expect(name("  ") == "Screenshot 2026-11-01 09.05.07" && name(nil) == "Screenshot 2026-11-01 09.05.07",
                     "an empty pattern falls back to the default")
        suite.expect(name("Shot_{n}", taken: ["Shot_1.png", "Shot_2.png"]) == "Shot_3",
                     "the counter picks the first unused number")
        suite.expect(name("Same", taken: ["Same.png", "Same (2).png"]) == "Same (3)",
                     "a taken name without a counter gets a number appended")
        suite.expect(name("a/b:c {HH:mm}") == "a-b-c 09-05", "characters a file name cannot hold are replaced")
        suite.expect(name("x {yyyy") == "x {yyyy", "an unclosed brace is literal")
        suite.expect(name("...") == "Screenshot", "a name of dots alone falls back to a plain one")

        let extensions = [("png", ".png"), ("jpg", ".jpg"), ("JPEG", ".jpg"), ("bmp", ".bmp"), ("whatever", ".png")]
        for (format, expected) in extensions {
            suite.expect(ShotFiles.fileExtension(format) == expected, "\(format) saves as \(expected)")
        }
        let paths = [("/a/b.JPEG", "jpg"), ("/a/b.png", "png"), ("/a/b.bmp", "bmp"), ("/a/b.gif", "png"), ("/a/b", "png")]
        for (path, expected) in paths {
            suite.expect(ShotFiles.format(fromPath: path, fallback: "png") == expected,
                         "\(path) is written as \(expected)")
        }
    }

    private static func systemShortcuts(_ suite: TestSuite) {
        suite.expect(ShotSystemShortcut.enabled(in: nil) == ShotSystemShortcut.allCases
                        && ShotSystemShortcut.enabled(in: [:]) == ShotSystemShortcut.allCases,
                     "a shortcut the system table does not list is on from the factory")
        let table: [String: Any] = [
            "28": ["enabled": false], "29": ["enabled": NSNumber(value: 0)],
            "30": ["enabled": true], "31": ["enabled": false], "184": ["enabled": false],
        ]
        suite.expect(ShotSystemShortcut.enabled(in: table) == [.saveArea],
                     "only the shortcuts still switched on are reported")
        let allOff = Dictionary(uniqueKeysWithValues: ShotSystemShortcut.allCases.map {
            (String($0.rawValue), ["enabled": false] as Any)
        })
        suite.expect(ShotSystemShortcut.enabled(in: allOff).isEmpty,
                     "with every screenshot shortcut off nothing is left for the system to answer")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.shot(language)
            let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(values.count == 25 && values.allSatisfy { !$0.isEmpty },
                         "\(language.rawValue) has every screenshot tool string")
            suite.expect(text.exampleFormat.components(separatedBy: "%@").count == 2
                            && text.sizeHintFormat.components(separatedBy: "%d").count == 2
                            && text.textSizeHintFormat.components(separatedBy: "%d").count == 2,
                         "\(language.rawValue) keeps one placeholder in each format")
        }
    }
}
