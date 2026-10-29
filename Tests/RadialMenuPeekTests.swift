// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// The radial menu's peek: which slices open one, where the panel lands
/// beside the wheel, and how the pointer and the arrows pick its rows.
enum RadialMenuPeekContract {
    static func run(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuPeekEnabled] as? Bool == true
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.radialMenuPeekEnabled),
                     "the radial peek ships on and travels with the settings backup")

        let clipboard = RadialMenuItem(kind: .tool, payload: RadialMenuTool.clipboardHistory.rawValue)
        suite.expect(clipboard.peek == .clipboardHistory
                     && RadialMenuItem(kind: .tool, payload: RadialMenuTool.screenshot.rawValue).peek == nil
                     && RadialMenuItem(kind: .submenu, children: [clipboard]).peek == nil
                     && RadialMenuItem(kind: .file, payload: "~/Downloads").peek == .folder(path: "~/Downloads")
                     && RadialMenuItem(kind: .app, payload: "/System/Applications/Notes.app").peek == nil
                     && RadialMenuItem(kind: .url, payload: "https://example.com").peek == nil,
                     "the clipboard and file slices open a peek; apps, links, other tools and submenus do not")
        RadialFolderPeekContract.run(suite)

        let screen = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        let center = CGPoint(x: 800, y: 500)
        let rim = RadialMenuLayout.wheelDiameter / 2
        let rows = 5
        let right = RadialMenuPeekLayout.frame(wheelCenter: center, direction: (1, 0),
                                               rowCount: rows, visibleFrame: screen)
        let left = RadialMenuPeekLayout.frame(wheelCenter: center, direction: (-1, 0),
                                              rowCount: rows, visibleFrame: screen)
        suite.expect(right.minX > center.x + rim && left.maxX < center.x - rim
                     && right.minY < center.y && right.maxY > center.y
                     && right.height == RadialMenuPeekLayout.height(rowCount: rows),
                     "the peek opens beside the wheel on the slice's side, level with it")
        let sliceCount = 8
        let clearOfWheel = (0..<sliceCount).allSatisfy { index in
            let frame = RadialMenuPeekLayout.frame(
                wheelCenter: center,
                direction: RadialMenuGeometry.unitPosition(index: index, itemCount: sliceCount),
                rowCount: RadialMenuPeekLayout.visibleRows, visibleFrame: screen)
            let nearestX = min(max(center.x, frame.minX), frame.maxX)
            let nearestY = min(max(center.y, frame.minY), frame.maxY)
            return hypot(nearestX - center.x, nearestY - center.y) > rim
        }
        suite.expect(clearOfWheel, "no slice's peek covers the wheel it belongs to")

        let nearRightEdge = CGPoint(x: screen.maxX - 220, y: 500)
        let flipped = RadialMenuPeekLayout.frame(wheelCenter: nearRightEdge, direction: (1, 0),
                                                 rowCount: rows, visibleFrame: screen)
        suite.expect(flipped.maxX < nearRightEdge.x - rim,
                     "a peek that would leave the screen opens on the wheel's other side")
        let nearTop = CGPoint(x: 800, y: screen.maxY - 200)
        let clamped = RadialMenuPeekLayout.frame(wheelCenter: nearTop, direction: (0.7, 0.7),
                                                 rowCount: RadialMenuPeekLayout.visibleRows, visibleFrame: screen)
        suite.expect(screen.insetBy(dx: RadialMenuPeekLayout.screenMargin,
                                    dy: RadialMenuPeekLayout.screenMargin).contains(clamped),
                     "a peek near the screen's edge stays whole on screen")
        suite.expect(RadialMenuPeekLayout.height(rowCount: 40) == RadialMenuPeekLayout.height(
                        rowCount: RadialMenuPeekLayout.visibleRows),
                     "the peek lists a bounded number of rows")

        let frame = CGRect(x: 100, y: 100, width: RadialMenuPeekLayout.width,
                           height: RadialMenuPeekLayout.height(rowCount: 3))
        let firstRowTop = frame.maxY - RadialMenuPeekLayout.padding - RadialMenuPeekLayout.headerHeight
        func row(at offset: CGFloat) -> Int? {
            RadialMenuPeekLayout.row(at: CGPoint(x: frame.midX, y: firstRowTop - offset), in: frame,
                                     rowCount: 3, firstVisibleRow: 0)
        }
        let rowHeight = RadialMenuPeekLayout.rowHeight
        suite.expect(row(at: -4) == nil && row(at: 1) == 0 && row(at: rowHeight + 1) == 1
                     && row(at: 3 * rowHeight - 1) == 2 && row(at: 3 * rowHeight + 2) == nil
                     && RadialMenuPeekLayout.row(at: CGPoint(x: frame.maxX + 1, y: firstRowTop - 1),
                                                 in: frame, rowCount: 3, firstVisibleRow: 0) == nil,
                     "the pointer picks the row under it, and none over the header, the preview or outside")

        let visible = RadialMenuPeekLayout.visibleRows
        let long = 20
        let tall = CGRect(x: 100, y: 100, width: RadialMenuPeekLayout.width,
                          height: RadialMenuPeekLayout.height(rowCount: long))
        let tallTop = tall.maxY - RadialMenuPeekLayout.padding - RadialMenuPeekLayout.headerHeight
        func scrolledRow(at offset: CGFloat, first: Int) -> Int? {
            RadialMenuPeekLayout.row(at: CGPoint(x: tall.midX, y: tallTop - offset), in: tall,
                                     rowCount: long, firstVisibleRow: first)
        }
        suite.expect(scrolledRow(at: 1, first: 5) == 5
                     && scrolledRow(at: CGFloat(visible) * rowHeight - 1, first: 5) == 5 + visible - 1
                     && scrolledRow(at: CGFloat(visible) * rowHeight + 2, first: 5) == nil,
                     "a scrolled list picks the entry shown under the pointer, and none over the preview below it")
        suite.expect(RadialMenuPeekLayout.scrolledFirstRow(0, by: -3, rowCount: long) == 0
                     && RadialMenuPeekLayout.scrolledFirstRow(0, by: 4, rowCount: long) == 4
                     && RadialMenuPeekLayout.scrolledFirstRow(10, by: 50, rowCount: long) == long - visible
                     && RadialMenuPeekLayout.scrolledFirstRow(0, by: 3, rowCount: visible - 1) == 0,
                     "the list scrolls by rows and stops with its last entry at the bottom")
        suite.expect(RadialMenuPeekLayout.firstRow(revealing: visible, from: 0, rowCount: long) == 1
                     && RadialMenuPeekLayout.firstRow(revealing: 2, from: 5, rowCount: long) == 2
                     && RadialMenuPeekLayout.firstRow(revealing: 6, from: 5, rowCount: long) == 5
                     && RadialMenuPeekLayout.firstRow(revealing: long - 1, from: 0, rowCount: long) == long - visible,
                     "the arrow keys scroll the list just enough to keep their entry on screen")

        suite.expect(RadialMenuPeekLayout.movedRow(nil, by: 1, rowCount: 4) == 0
                     && RadialMenuPeekLayout.movedRow(nil, by: -1, rowCount: 4) == 3
                     && RadialMenuPeekLayout.movedRow(3, by: 1, rowCount: 4) == 3
                     && RadialMenuPeekLayout.movedRow(0, by: -1, rowCount: 4) == 0
                     && RadialMenuPeekLayout.movedRow(1, by: 1, rowCount: 4) == 2
                     && RadialMenuPeekLayout.movedRow(nil, by: 1, rowCount: 0) == nil,
                     "the arrows enter the peek from the side they point to and stop at its ends")

        suite.expect(!RadialMenuPeekLayout.holdsHighlight(pointerDistance: rim - 1)
                     && RadialMenuPeekLayout.holdsHighlight(pointerDistance: rim + 1),
                     "with a peek open, only a pointer past the rim keeps its slice on the way to the panel")
    }
}

/// The folder list: what a read returns and never touches, the order it
/// shows, how the basket keeps picks across folders, and where its back
/// arrow, basket and clear button sit for the pointer.
enum RadialFolderPeekContract {
    static func run(_ suite: TestSuite) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("vorssaint-radial-folder-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let locked = root.appendingPathComponent("Locked", isDirectory: true)
        do {
            try fileManager.createDirectory(at: root.appendingPathComponent("Sub", isDirectory: true),
                                            withIntermediateDirectories: true)
            try fileManager.createDirectory(at: root.appendingPathComponent("Thing.app/Contents", isDirectory: true),
                                            withIntermediateDirectories: true)
            try fileManager.createDirectory(at: locked, withIntermediateDirectories: true)
            try Data("a".utf8).write(to: root.appendingPathComponent("note.txt"))
            try Data("b".utf8).write(to: root.appendingPathComponent(".secret"))
        } catch {
            suite.expect(false, "the folder fixture could be created: \(error)")
            return
        }
        let before = (try? fileManager.contentsOfDirectory(atPath: root.path))?.sorted()

        guard case let .entries(listed) = RadialFolderListing.read(root, limit: 50) else {
            suite.expect(false, "a readable folder lists its contents")
            return
        }
        let names = listed.map(\.name)
        suite.expect(!names.contains(".secret") && names.contains("note.txt"),
                     "the folder list leaves hidden files out")
        suite.expect(listed.first(where: { $0.name == "Sub" })?.isFolder == true
                     && listed.first(where: { $0.url.lastPathComponent == "Thing.app" })?.isFolder == false,
                     "a folder can be gone into, while a package such as an app is a file")
        suite.expect(listed.prefix(while: \.isFolder).count == listed.filter(\.isFolder).count,
                     "folders come before files")
        suite.expect((try? fileManager.contentsOfDirectory(atPath: root.path))?.sorted() == before,
                     "listing a folder leaves it exactly as it was")
        if case let .entries(limited) = RadialFolderListing.read(root, limit: 1) {
            suite.expect(limited.count == 1, "a folder list stops at its limit")
        } else {
            suite.expect(false, "a limited read still lists")
        }
        suite.expect(RadialFolderListing.read(root.appendingPathComponent("note.txt"), limit: 50) == .notAFolder
                     && RadialFolderListing.read(root.appendingPathComponent("gone"), limit: 50) == .notAFolder
                     && RadialFolderListing.read(root.appendingPathComponent("Thing.app"), limit: 50) == .notAFolder,
                     "a file, a package or a missing path opens no list")
        try? fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        suite.expect(RadialFolderListing.read(locked, limit: 50) == .unreadable,
                     "a folder the app may not read says so instead of looking empty")
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)

        func entry(_ name: String, folder: Bool = false, age: TimeInterval) -> RadialFolderEntry {
            RadialFolderEntry(url: root.appendingPathComponent(name), name: name, isFolder: folder,
                              date: Date(timeIntervalSince1970: 1_000_000 - age), size: folder ? nil : 1,
                              contentType: nil, typeDescription: nil)
        }
        let order = RadialFolderListing.sorted([
            entry("old.pdf", age: 500), entry("Projects", folder: true, age: 900),
            entry("b.png", age: 10), entry("a.png", age: 10), entry("Archive", folder: true, age: 5),
        ]).map(\.name)
        suite.expect(order == ["Archive", "Projects", "a.png", "b.png", "old.pdf"],
                     "folders first, then the newest arrival, and same-moment files by name")

        let sub = entry("Sub", folder: true, age: 0)
        let note = root.appendingPathComponent("note.txt")
        let deep = root.appendingPathComponent("Sub/deep.txt")
        var browser = RadialFolderBrowser(root: root, name: "Downloads")
        suite.expect(!browser.canGoUp && browser.current == root && browser.pathNames == ["Downloads"],
                     "the folder list starts at the folder on the wheel")
        browser.enter(entry("note.txt", age: 0))
        suite.expect(browser.trail.isEmpty, "a file cannot be gone into")
        browser.toggle(note)
        browser.enter(sub)
        browser.toggle(deep)
        suite.expect(browser.canGoUp && browser.current == sub.url && browser.pathNames == ["Downloads", "Sub"]
                     && browser.basket == [note, deep],
                     "picks are kept, in order, across the folders the list goes into")
        suite.expect(browser.dragged(grabbing: deep) == [note, deep]
                     && browser.dragged(grabbing: root.appendingPathComponent("other.txt"))
                        == [root.appendingPathComponent("other.txt")],
                     "dragging a picked file takes every pick; dragging another takes only that one")
        suite.expect(browser.copied(highlighted: nil) == [note, deep],
                     "⌘C copies the picked files")
        browser.toggle(note)
        suite.expect(browser.basket == [deep], "picking a file again unpicks it")
        browser.goUp()
        browser.goUp()
        suite.expect(browser.current == root && browser.basket == [deep],
                     "going back up keeps the picks and stops at the folder on the wheel")
        browser.clearBasket()
        suite.expect(browser.basket.isEmpty && browser.copied(highlighted: note) == [note]
                     && browser.copied(highlighted: nil).isEmpty,
                     "with nothing picked, ⌘C copies the row under the pointer, or nothing")
        var full = RadialFolderBrowser(root: root, name: "Downloads")
        for index in 0...RadialFolderBrowser.basketLimit {
            full.toggle(root.appendingPathComponent("\(index).txt"))
        }
        suite.expect(full.basket.count == RadialFolderBrowser.basketLimit, "the basket holds a bounded number of picks")

        let visible = RadialMenuPeekLayout.visibleRows
        let panel = CGRect(x: 200, y: 100, width: RadialMenuPeekLayout.width,
                           height: RadialMenuPeekLayout.height(rowCount: visible, basket: true))
        suite.expect(panel.height - RadialMenuPeekLayout.height(rowCount: visible)
                        == RadialMenuPeekLayout.basketHeight,
                     "the folder list is the clipboard list's height plus its basket")
        let back = RadialMenuPeekLayout.backButtonFrame(in: panel)
        let basket = RadialMenuPeekLayout.basketFrame(in: panel)
        let clear = RadialMenuPeekLayout.clearButtonFrame(in: panel)
        let lastRowBottom = panel.maxY - RadialMenuPeekLayout.padding - RadialMenuPeekLayout.headerHeight
            - RadialMenuPeekLayout.rowHeight * CGFloat(visible)
        suite.expect(panel.contains(back) && panel.contains(basket) && basket.contains(clear)
                     && back.minY >= lastRowBottom && basket.maxY <= lastRowBottom
                     && basket.minY >= panel.minY + RadialMenuPeekLayout.padding + RadialMenuPeekLayout.previewHeight
                     && clear.maxX == basket.maxX,
                     "the back arrow sits in the header, and the basket with its clear button between the rows and the preview")
        suite.expect(RadialMenuPeekLayout.row(at: CGPoint(x: basket.midX, y: basket.midY), in: panel,
                                              rowCount: 50, firstVisibleRow: 0) == nil,
                     "a press on the basket is never read as a press on a row")

        let plist = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        suite.expect(["NSDownloadsFolderUsageDescription", "NSDesktopFolderUsageDescription",
                      "NSDocumentsFolderUsageDescription", "NSNetworkVolumesUsageDescription",
                      "NSRemovableVolumesUsageDescription"].allSatisfy {
                         (plist?[$0] as? String ?? "").contains("The radial menu also lists")
                     },
                     "every folder permission prompt says the radial menu may list a folder")
    }
}
