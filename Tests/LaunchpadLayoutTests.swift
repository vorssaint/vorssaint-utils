// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The arrangement is the one thing Launchpad keeps between openings, so every
/// edit has to leave each app in exactly one place: never lost when a folder
/// goes, never doubled when it moves between a folder and the grid.
enum LaunchpadLayoutTests {
    private static func layout(_ paths: [String]) -> LaunchpadLayout {
        LaunchpadLayout().reconciled(with: paths)
    }

    private static func ids(_ layout: LaunchpadLayout) -> [String] {
        layout.items.map { item in
            if case .folder(let folder) = item { return "[" + folder.apps.joined(separator: ",") + "]" }
            return item.id
        }
    }

    static func run(_ expect: (Bool, String) -> Void) {
        // New installs join the end; removed apps leave, and an emptied folder with them.
        var grid = layout(["a", "b", "c"])
        expect(ids(grid) == ["a", "b", "c"], "a first layout lists every app, got \(ids(grid))")
        grid.drop("c", onto: "b", folderName: "Work")
        grid = grid.reconciled(with: ["a", "d"])
        expect(ids(grid) == ["a", "d"], "missing apps and their emptied folder leave, got \(ids(grid))")

        // Dropping an app on an app makes a folder in the target's place.
        grid = layout(["a", "b", "c", "d"])
        let folderID = grid.drop("d", onto: "b", folderName: "Work")
        expect(ids(grid) == ["a", "[b,d]", "c"], "a folder takes the target's place, got \(ids(grid))")
        expect(grid.folder(folderID ?? "")?.name == "Work", "the folder gets the name it was given")

        // Dropping on a folder files the app there; nothing is doubled.
        grid.drop("a", onto: folderID ?? "", folderName: "unused")
        expect(ids(grid) == ["[b,d,a]", "c"], "an app dropped on a folder joins it, got \(ids(grid))")
        expect(grid.placedApps.sorted() == ["a", "b", "c", "d"], "every app keeps exactly one place")

        // Moving an app out of a folder onto the grid, by its final position.
        grid.move("d", toPosition: 2)
        expect(ids(grid) == ["[b,a]", "c", "d"], "an app moves out of its folder to the grid, got \(ids(grid))")

        // A folder left with one app becomes that app, in its place.
        grid.move("a", toPosition: 0)
        expect(ids(grid) == ["a", "b", "c", "d"], "a folder down to one app becomes the app, got \(ids(grid))")
        expect(grid.folder(folderID ?? "") == nil, "the one-app folder is gone")

        // Positions count the grid once the item has left its place.
        var order = layout(["a", "b", "c", "d"])
        order.move("a", toPosition: 2)
        expect(ids(order) == ["b", "c", "a", "d"], "a move forward lands at its position, got \(ids(order))")
        order.move("d", toPosition: 0)
        expect(ids(order) == ["d", "b", "c", "a"], "a move backwards lands at its position, got \(ids(order))")
        order.move("b", toPosition: 99)
        expect(ids(order) == ["d", "c", "a", "b"], "a position past the end lands last, got \(ids(order))")

        // One app alone is not a folder.
        var lone = layout(["x", "y"])
        expect(lone.createFolder(named: "Solo", apps: ["x"]) == nil && ids(lone) == ["x", "y"],
               "a folder needs two apps")

        // Taking an app out of a two-app folder leaves the other app in its place.
        var out = layout(["a", "b", "c"])
        out.drop("b", onto: "a", folderName: "Pair")
        out.takeOutOfFolder("a")
        expect(ids(out) == ["b", "a", "c"], "taking one of two apps out dissolves the folder, got \(ids(out))")

        // Reordering inside a folder keeps the folder in place.
        var inside = layout(["a", "b", "c", "d"])
        let three = inside.createFolder(named: "F", apps: ["a", "b", "c"]) ?? ""
        inside.moveInFolder("a", toPosition: 2)
        expect(ids(inside) == ["[b,c,a]", "d"], "an app moves to the end of its folder, got \(ids(inside))")
        inside.moveInFolder("a", toPosition: 0)
        expect(ids(inside) == ["[a,b,c]", "d"], "an app moves to the front of its folder, got \(ids(inside))")
        inside.takeOutOfFolder("b")
        expect(ids(inside) == ["[a,c]", "b", "d"], "an app taken out lands after its folder, got \(ids(inside))")

        // Deleting a folder puts its apps where it was.
        inside.deleteFolder(three)
        expect(ids(inside) == ["a", "c", "b", "d"], "a deleted folder's apps take its place, got \(ids(inside))")

        // A folder made from picked apps sits where the first of them was.
        var picked = layout(["a", "b", "c", "d"])
        let made = picked.createFolder(named: "Picked", apps: ["d", "b", "b"]) ?? ""
        expect(ids(picked) == ["a", "[d,b]", "c"], "a new folder sits at the first app's place, got \(ids(picked))")

        // Editing returns removed apps after the folder and takes new ones from the grid.
        picked.editFolder(made, name: "Edited", apps: ["d", "c"])
        expect(ids(picked) == ["a", "[d,c]", "b"], "an edit returns removed apps after the folder, got \(ids(picked))")
        expect(picked.folder(made)?.name == "Edited", "an edit renames the folder")
        picked.editFolder(made, name: "Edited", apps: ["d"])
        expect(ids(picked) == ["a", "d", "c", "b"], "an edit down to one app dissolves the folder, got \(ids(picked))")

        // Hiding takes an app out of folders too; unhiding brings it back once.
        var hiding = layout(["a", "b", "c", "d"])
        let trio = hiding.createFolder(named: "F", apps: ["a", "b", "c"]) ?? ""
        hiding.hide("b")
        hiding.hide("b")
        expect(ids(hiding) == ["[a,c]", "d"] && hiding.hidden == ["b"], "a hidden app leaves its folder, got \(ids(hiding))")
        let reconciled = hiding.reconciled(with: ["a", "b", "c", "d"])
        expect(!reconciled.placedApps.contains("b"), "a hidden app is not added back as new")
        hiding.unhide("b")
        hiding.unhide("b")
        expect(ids(hiding) == ["[a,c]", "d", "b"] && hiding.hidden.isEmpty, "unhiding brings the app back once, got \(ids(hiding))")
        expect(hiding.folder(trio) != nil, "a folder keeps two apps after one is hidden")

        // A layout survives a round trip, and garbage decodes to an empty layout.
        let decoded = LaunchpadLayout.decode(picked.encoded)
        expect(decoded == picked, "a layout survives encoding")
        expect(LaunchpadLayout.decode(Data("nope".utf8)) == LaunchpadLayout(), "a damaged layout starts over")

        // Duplicates in a stored layout keep only their first place.
        var doubled = LaunchpadLayout()
        doubled.items = [.app("a"), .folder(LaunchpadFolder(name: "F", apps: ["a", "b"])), .app("b")]
        expect(ids(doubled.reconciled(with: ["a", "b"])) == ["a", "b"],
               "a duplicate keeps its first place, and a folder left with one app becomes it")

        // Categories.
        expect(LaunchpadCategory(applicationCategoryType: "public.app-category.developer-tools") == .developer,
               "developer tools shelve together")
        expect(LaunchpadCategory(applicationCategoryType: "public.app-category.puzzle-games") == .games,
               "every game genre shelves with games")
        expect(LaunchpadCategory(applicationCategoryType: nil) == .other, "an app with no category goes to Other")

        // Search ranks prefixes, then word starts, then the rest; accents and case are ignored.
        let names = ["Notes", "Sticky Notes", "Keynote", "Calendar"]
        expect(LaunchpadSupport.search("no", in: names) { $0 } == ["Notes", "Sticky Notes", "Keynote"],
               "search ranks a prefix before a word start before a substring")
        expect(LaunchpadSupport.search("CALÉ", in: names) { $0 } == ["Calendar"], "search ignores case and accents")
        expect(LaunchpadSupport.search("  ", in: names) { $0 } == names, "a blank search shows everything")

        // Grid metrics stay in bounds and pages round up.
        let small = LaunchpadSupport.grid(for: CGSize(width: 300, height: 200))
        let huge = LaunchpadSupport.grid(for: CGSize(width: 6000, height: 4000))
        expect(small.columns == 4 && small.rows == 3, "a tiny area still shows a usable grid")
        expect(huge.columns == 7 && huge.rows == 5, "a huge display keeps Launchpad's seven by five")
        expect(LaunchpadSupport.pageCount(items: 41, perPage: 20) == 3, "pages round up")
        expect(LaunchpadSupport.pageCount(items: 0, perPage: 20) == 1, "an empty grid still has a page")
        expect(LaunchpadSupport.Style.sanitized("bogus") == .fullScreen, "an unknown style reads as full screen")
        let laptop = LaunchpadSupport.grid(for: CGSize(width: 1440, height: 940))
        expect(laptop.columns == 7 && laptop.rows == 5, "a laptop screen gets Launchpad's seven by five")

        // The wallpaper comes from the newest slot covering the display.
        func configuration(_ value: [String: Any]) -> Data {
            (try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)) ?? Data()
        }
        func slot(_ value: [String: Any], _ date: TimeInterval) -> [String: Any] {
            ["Desktop": ["LastSet": Date(timeIntervalSince1970: date),
                         "Content": ["Choices": [["Configuration": configuration(value)]]]]]
        }
        let thumbnails = URL(fileURLWithPath: "/thumbs")
        let store: [String: Any] = [
            "AllSpacesAndDisplays": slot(["url": ["relative": "file:///old.heic"]], 1),
            "Displays": ["D1": slot(["assetID": "A1"], 5), "D2": slot(["url": ["relative": "file:///other.heic"]], 9)],
        ]
        expect(LaunchpadSupport.wallpaperFile(inStore: store, displayUUID: "D1", aerialThumbnails: thumbnails)?.path
               == "/thumbs/A1.png", "an Aerial shows its still thumbnail")
        expect(LaunchpadSupport.wallpaperFile(inStore: store, displayUUID: "D3", aerialThumbnails: thumbnails)?.path
               == "/old.heic", "a display without its own slot uses the one for all displays")
        expect(LaunchpadSupport.wallpaperFile(inStore: [:], displayUUID: "D1", aerialThumbnails: thumbnails) == nil,
               "an unreadable store gives no picture")

        // A drag reads the cell under the pointer: the middle of an icon merges, the rest moves the gap.
        let geometry = LaunchpadGridGeometry(origin: CGPoint(x: 100, y: 50), cell: CGSize(width: 200, height: 180),
                                             columns: 7, rows: 5)
        let iconMiddle = CGPoint(x: 100 + 200 * 2.5, y: 50 + 90 - LaunchpadSupport.labelBlock / 2)
        expect(LaunchpadSupport.dragTarget(at: iconMiddle, in: geometry, page: 0, shownCount: 20, gap: 9,
                                           canMerge: true) == .merge(2), "the middle of an icon asks for a folder")
        expect(LaunchpadSupport.dragTarget(at: iconMiddle, in: geometry, page: 0, shownCount: 20, gap: 9,
                                           canMerge: false) == .gap(2), "a folder in the hand only moves the gap")
        expect(LaunchpadSupport.dragTarget(at: CGPoint(x: 100 + 410, y: 60), in: geometry, page: 1, shownCount: 50,
                                           gap: 0, canMerge: true) == .gap(37), "the edge of a cell on page two moves the gap there")
        expect(LaunchpadSupport.dragTarget(at: CGPoint(x: 100 + 1300, y: 50 + 800), in: geometry, page: 0, shownCount: 12,
                                           gap: 3, canMerge: true) == .gap(11), "past the last item the gap goes last")
        expect(LaunchpadSupport.dragTarget(at: CGPoint(x: 20, y: 20), in: geometry, page: 0, shownCount: 12,
                                           gap: 3, canMerge: true) == nil, "outside the cells nothing changes")
        expect(LaunchpadSupport.shown(["a", "b"], gap: 1) == ["a", nil, "b"], "the gap sits among the items")

        // A released swipe settles on the nearest page, or a page on with a flick.
        func settled(_ began: CGFloat, _ position: CGFloat, _ velocity: CGFloat) -> Int {
            LaunchpadSupport.settledPage(began: began, position: position, velocity: velocity,
                                         pageWidth: 1000, pageCount: 4)
        }
        expect(settled(1000, 1600, 0) == 2, "a slow pull past half a page turns it")
        expect(settled(1000, 1200, 0) == 1, "a short slow pull springs back")
        expect(settled(1000, 1040, 900) == 2, "a short flick turns the next page in")
        expect(settled(1000, 960, -900) == 0, "a short flick back turns back a page")
        expect(settled(1850, 1900, 900) == 3, "a page caught as it settles flicks on to the one after")
        expect(settled(1400, 1500, 900) == 2, "a page caught early flicks on to where it was going")
        expect(settled(3000, 3100, 900) == 3 && settled(0, -80, -900) == 0, "a flick past either end stays on it")

        // Past the ends the pages give less the further they are pulled.
        let first = LaunchpadSupport.rubberBand(10, overshoot: 0, pageWidth: 1000)
        let later = LaunchpadSupport.rubberBand(10, overshoot: 400, pageWidth: 1000)
        expect(first > later && later > 0 && first < 10, "the rubber band stiffens as it stretches")
        expect(LaunchpadSupport.rubberBand(10, overshoot: 1000, pageWidth: 1000) == 0, "it never stretches a page")

        // The glide comes to rest without passing its page, and keeps a throw going.
        var glide = (offset: CGFloat(-1000), velocity: CGFloat(0))
        var passed = false
        for _ in 0..<60 {
            glide = LaunchpadSupport.springStep(offset: glide.offset, velocity: glide.velocity, elapsed: 1 / 120)
            passed = passed || glide.offset > 0
        }
        expect(!passed && abs(glide.offset) < 1 && abs(glide.velocity) < 20, "a glide settles in half a second")
        let thrown = LaunchpadSupport.springStep(offset: 0, velocity: 2000, elapsed: 1 / 120)
        expect(thrown.offset > 0 && thrown.velocity > 0, "a page thrown at rest keeps moving for a moment")
    }
}
