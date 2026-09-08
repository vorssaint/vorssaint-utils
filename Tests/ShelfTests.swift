// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Darwin
import Foundation

enum ShelfTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            expect(actual == expected, "\(label): got \"\(actual)\", expected \"\(expected)\"")
        }

        // MARK: Shelf persistence

        expect(ShelfSelectionSupport.rangeSelectionIDs(
            allIDs: ["a", "b", "c", "d"], anchorID: "b", targetID: "d") == ["b", "c", "d"],
               "shelf shift-click selects the forward visible range")
        expect(ShelfSelectionSupport.rangeSelectionIDs(
            allIDs: ["a", "b", "c", "d"], anchorID: "d", targetID: "b") == ["b", "c", "d"],
               "shelf shift-click selects the reverse visible range")
        expect(ShelfSelectionSupport.rangeSelectionIDs(
            allIDs: ["a", "b"], anchorID: nil, targetID: "b") == ["b"],
               "shelf shift-click without an anchor starts at the clicked tile")
        expect(ShelfSelectionSupport.rangeSelectionIDs(
            allIDs: ["a", "b"], anchorID: "a", targetID: "missing").isEmpty,
               "shelf shift-click ignores a tile outside the visible list")
        expect(ShelfSelectionSupport.isClearSelectionShortcut(
            keyCode: 53, hasSelectionModifiers: false),
               "shelf Escape clears the current selection")
        expect(!ShelfSelectionSupport.isClearSelectionShortcut(
            keyCode: 53, hasSelectionModifiers: true),
               "shelf keeps modified Escape available for other shortcuts")
        expect(!ShelfSelectionSupport.isClearSelectionShortcut(
            keyCode: 36, hasSelectionModifiers: false),
               "shelf does not clear selection for an unrelated key")

        expect(ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: "com.example.Editor",
            excludedBundleIdentifiers: ["com.example.Browser"]),
               "shelf automatic opening allows apps outside the exclusion list")
        expect(!ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: "com.example.Browser",
            excludedBundleIdentifiers: ["com.example.Browser"]),
               "shelf automatic opening stays off for an excluded source app")
        expect(ShelfInteractionSupport.allowsAutomaticOpen(
            sourceBundleIdentifier: nil,
            excludedBundleIdentifiers: ["com.example.Browser"]),
               "shelf automatic opening does not false-block an unknown drag source")
        expect(ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: true, draggedItemCount: 2, closeAfterDrop: true, pinned: false),
               "shelf closes after a real accepted external drag")
        expect(!ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: false, draggedItemCount: 2, closeAfterDrop: true, pinned: false),
               "shelf stays open after a cancelled drag")
        expect(!ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: true, draggedItemCount: 0, closeAfterDrop: true, pinned: false),
               "shelf internal merges do not dismiss the panel")
        expect(!ShelfInteractionSupport.shouldCloseAfterDrag(
            dropAccepted: true, draggedItemCount: 2, closeAfterDrop: true, pinned: true),
               "shelf pin overrides close after drop")
        expect(ShelfInteractionSupport.shouldRemoveAfterDrag(
            dropAccepted: true, draggedItemCount: 1, removeAfterDrop: true),
               "shelf removes an accepted item when automatic removal is on")
        expect(!ShelfInteractionSupport.shouldRemoveAfterDrag(
            dropAccepted: true, draggedItemCount: 1, removeAfterDrop: false),
               "shelf retains an accepted item when automatic removal is off")

        expect(!ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 5, beganInDock: false,
            hasDroppableContent: { true }),
               "moving a window past retained pasteboard content is not a content drag")
        expect(!ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 6, beganInDock: false,
            hasDroppableContent: { false }),
               "a pasteboard bump without droppable content is not a content drag")
        expect(ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 6, beganInDock: false,
            hasDroppableContent: { true }),
               "content published during the gesture is a content drag")
        expect(ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 5, beganInDock: true,
            hasDroppableContent: { true }),
               "dock stacks may publish the drag contents before the mouse-down")
        expect(!ShelfInteractionSupport.isContentDrag(
            baselineChangeCount: 5, changeCount: 5, beganInDock: false,
            hasDroppableContent: { fatalError("droppable check must stay lazy") }),
               "an unchanged pasteboard outside the Dock skips the content inspection")

        // MARK: Shelf reveal

        let revealChildA = UUID()
        let revealChildB = UUID()
        let revealNested = UUID()
        let revealPile = UUID()
        let revealDeepPile = UUID()
        let revealLoose = UUID()
        let revealTree = [
            ShelfRevealNode(id: revealLoose),
            ShelfRevealNode(id: revealPile, children: [
                ShelfRevealNode(id: revealChildA),
                ShelfRevealNode(id: revealDeepPile, children: [
                    ShelfRevealNode(id: revealNested),
                ]),
            ]),
            ShelfRevealNode(id: revealChildB),
        ]

        expect(ShelfRevealSupport.visibleAncestorID(of: revealLoose,
                                                    in: revealTree,
                                                    expanded: []) == revealLoose,
               "a top level item reveals itself")
        expect(ShelfRevealSupport.visibleAncestorID(of: revealChildA,
                                                    in: revealTree,
                                                    expanded: []) == revealPile,
               "a child of a collapsed pile reveals the pile, since the child has no tile")
        expect(ShelfRevealSupport.visibleAncestorID(of: revealChildA,
                                                    in: revealTree,
                                                    expanded: [revealPile]) == revealChildA,
               "a child of an expanded pile reveals the child itself")
        expect(ShelfRevealSupport.visibleAncestorID(of: revealNested,
                                                    in: revealTree,
                                                    expanded: []) == revealPile,
               "an item two levels down reveals the outermost collapsed ancestor")
        expect(ShelfRevealSupport.visibleAncestorID(of: revealNested,
                                                    in: revealTree,
                                                    expanded: [revealPile]) == revealDeepPile,
               "expanding only the outer pile reveals the inner pile, not the item inside it")
        expect(ShelfRevealSupport.visibleAncestorID(of: revealNested,
                                                    in: revealTree,
                                                    expanded: [revealPile, revealDeepPile]) == revealNested,
               "expanding every ancestor reveals the item itself")
        expect(ShelfRevealSupport.visibleAncestorID(of: UUID(),
                                                    in: revealTree,
                                                    expanded: []) == nil,
               "an id that is not on the shelf reveals nothing")

        expect(ShelfRevealSupport.shouldReveal(serial: 1, lastHonored: nil),
               "the shelf's first ever add is always revealed")
        expect(!ShelfRevealSupport.shouldReveal(serial: 1, lastHonored: 1),
               "an already honored serial does not reveal again, e.g. a pile expanding with nothing added")
        expect(ShelfRevealSupport.shouldReveal(serial: 2, lastHonored: 1),
               "a new serial reveals even when the resolved target repeats, e.g. two drops into the same collapsed pile")

        expect(ShelfTileLayout.columnCount(contentWidth: 276,
                                           tileWidth: 78,
                                           spacing: 10,
                                           inset: 4) == 3,
               "the shelf's own width fits three tile columns")
        expect(ShelfTileLayout.columnCount(contentWidth: 40,
                                           tileWidth: 78,
                                           spacing: 10,
                                           inset: 4) == 1,
               "a width too small for one tile still reports a single column")

        let revealTile = CGSize(width: 78, height: 88)
        expect(ShelfTileLayout.tileFrame(index: 0,
                                         columns: 3,
                                         tileSize: revealTile,
                                         spacing: 10,
                                         inset: 4) == CGRect(x: 4, y: 4, width: 78, height: 88),
               "the first tile sits at the inset")
        expect(ShelfTileLayout.tileFrame(index: 2,
                                         columns: 3,
                                         tileSize: revealTile,
                                         spacing: 10,
                                         inset: 4) == CGRect(x: 180, y: 4, width: 78, height: 88),
               "the last tile of the first row advances by the column stride")
        expect(ShelfTileLayout.tileFrame(index: 3,
                                         columns: 3,
                                         tileSize: revealTile,
                                         spacing: 10,
                                         inset: 4) == CGRect(x: 4, y: 102, width: 78, height: 88),
               "the fourth tile wraps to the second row")
        expect(ShelfTileLayout.tileFrame(index: 6,
                                         columns: 3,
                                         tileSize: revealTile,
                                         spacing: 10,
                                         inset: 4) == CGRect(x: 4, y: 200, width: 78, height: 88),
               "the seventh tile lands on the third row, the case this change exists for")
        expect(ShelfTileLayout.tileFrame(index: 2,
                                         columns: 1,
                                         tileSize: revealTile,
                                         spacing: 10,
                                         inset: 4) == CGRect(x: 4, y: 200, width: 78, height: 88),
               "a single column puts every tile in its own row")

        let singleScreen = [ShelfEdgeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 10, y: 500), screens: singleScreen,
                                          distance: 24)?.edge == .left,
               "a point near the left edge of the only screen is a left-edge match")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 1910, y: 500), screens: singleScreen,
                                          distance: 24)?.edge == .right,
               "a point near the right edge of the only screen is a right-edge match")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 960, y: 500), screens: singleScreen,
                                          distance: 24) == nil,
               "a point in the middle of the screen matches no edge")

        let sideBySide = [ShelfEdgeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                          ShelfEdgeScreen(frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                                          visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))]
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 1918, y: 500), screens: sideBySide,
                                          distance: 24) == nil,
               "a seam shared by two adjacent screens counts as neither screen's own edge")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 10, y: 500), screens: sideBySide,
                                          distance: 24)?.edge == .left,
               "the true outer left edge of the first screen still matches with a second screen present")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 3830, y: 500), screens: sideBySide,
                                          distance: 24)?.edge == .right,
               "the true outer right edge of the second screen still matches")

        let leftDockScreen = [ShelfEdgeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                              visibleFrame: CGRect(x: 70, y: 0, width: 1850, height: 1080))]
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 30, y: 500), screens: leftDockScreen,
                                          distance: 200) == nil,
               "a point resting inside a left-mounted Dock's reserved margin does not trigger a peek")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 150, y: 500), screens: leftDockScreen,
                                          distance: 200)?.edge == .left,
               "a point past the Dock's margin, still within the trigger distance, matches normally")
        let rightDockScreen = [ShelfEdgeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                               visibleFrame: CGRect(x: 0, y: 0, width: 1850, height: 1080))]
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 1890, y: 500), screens: rightDockScreen,
                                          distance: 200) == nil,
               "a point resting inside a right-mounted Dock's reserved margin does not trigger a peek")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 1770, y: 500), screens: rightDockScreen,
                                          distance: 200)?.edge == .right,
               "a point past the right Dock's margin, still within the trigger distance, matches normally")
        let noDockScreen = [ShelfEdgeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: 0, y: 40, width: 1920, height: 1040))]
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 10, y: 500), screens: noDockScreen,
                                          distance: 200)?.edge == .left,
               "a Dock or menu bar that only narrows the visible frame vertically (bottom Dock, menu bar) leaves left/right matching unaffected")

        let leftMatch = ShelfEdgeMatch(edge: .left, screen: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        expect(ShelfEdgeDragSupport.stillNear(leftMatch, point: CGPoint(x: 30, y: 500), distance: 40),
               "a point within the wider retreat distance of the peeking edge is still near it")
        expect(!ShelfEdgeDragSupport.stillNear(leftMatch, point: CGPoint(x: 960, y: 500), distance: 40),
               "a point back in the middle of the screen is no longer near the peeking edge")
        expect(!ShelfEdgeDragSupport.stillNear(leftMatch, point: CGPoint(x: 1910, y: 500), distance: 40),
               "a point near the right side of the same screen does not count as still near a left-edge peek")

        expect(ShelfEdgeDragSupport.hasDwelled(since: 100.0, now: 100.16, required: 0.15),
               "a dwell longer than the required duration counts as sustained")
        expect(!ShelfEdgeDragSupport.hasDwelled(since: 100.0, now: 100.05, required: 0.15),
               "a dwell shorter than the required duration does not count yet")

        expect(ShelfEdgeDragSupport.triggerDistance == 200 && ShelfEdgeDragSupport.retreatDistance == 330
               && ShelfEdgeDragSupport.dwell == 0.15,
               "the shipped trigger distance, retreat distance, and dwell are pinned, so a future retune has to update this test")
        expect(ShelfEdgeDragSupport.match(at: CGPoint(x: 1918, y: 500), screens: sideBySide,
                                          distance: ShelfEdgeDragSupport.triggerDistance) == nil,
               "the seam stays safe at the shipped trigger distance, not just the smaller distance the earlier cases use")
        let shippedLeftMatch = ShelfEdgeMatch(edge: .left, screen: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // x: 100 sits safely inside the peeking panel's own on-screen strip
        // (ShelfView.panelWidth / 3, rounded: 304 / 3 ≈ 101), which the
        // retreat check relies on covering instead of a separate panel-frame
        // check.
        expect(ShelfEdgeDragSupport.stillNear(shippedLeftMatch, point: CGPoint(x: 100, y: 500),
                                              distance: ShelfEdgeDragSupport.retreatDistance),
               "the shipped retreat distance comfortably covers the peeking panel's own on-screen strip")

        // MARK: Shelf dock drag support

        expect(ShelfDockDragSupport.dwell == 0.15, "dock drag dwell is 150ms")
        expect(ShelfDockDragSupport.triggerMargin == 16, "dock trigger margin is 16pt")
        expect(ShelfDockDragSupport.retreatMargin == 32, "dock retreat margin is 32pt")

        let testAnchor = CGRect(x: 1200, y: 954, width: 28, height: 28)
        let testPill = CGRect(x: 1178, y: 920, width: 72, height: 30)
        let testCard = CGRect(x: 1094, y: 690, width: 240, height: 260)
        let testScreen = CGRect(x: 0, y: 0, width: 1512, height: 982)

        let resolvedTrigger = ShelfDockDragSupport.triggerFrame(pillFrame: testPill,
                                                               anchorFrame: testAnchor,
                                                               screenFrame: testScreen)
        expect(resolvedTrigger != nil, "trigger frame resolves with pill and anchor")
        if let trigger = resolvedTrigger {
            expect(trigger.minX == testPill.minX - 16, "trigger frame left margin")
            expect(trigger.maxX == testPill.maxX + 16, "trigger frame right margin")
            expect(trigger.minY == testPill.minY - 16, "trigger frame bottom margin")
            expect(trigger.maxY == testAnchor.maxY, "trigger frame top margin covers menu bar anchor")
        }

        let fallbackTrigger = ShelfDockDragSupport.triggerFrame(pillFrame: nil,
                                                                anchorFrame: testAnchor,
                                                                screenFrame: testScreen)
        expect(fallbackTrigger != nil, "trigger frame resolves with anchor alone")

        expect(ShelfDockDragSupport.triggerFrame(pillFrame: nil, anchorFrame: nil, screenFrame: testScreen) == nil,
               "trigger frame returns nil when neither pill nor anchor is available")

        expect(ShelfDockDragSupport.isPointNearDock(point: CGPoint(x: 1200, y: 930),
                                                   isProximate: false,
                                                   panelFrame: testPill,
                                                   anchorFrame: testAnchor,
                                                   screenFrame: testScreen),
               "point over the collapsed pill is near dock")

        expect(!ShelfDockDragSupport.isPointNearDock(point: CGPoint(x: 1200, y: 800),
                                                    isProximate: false,
                                                    panelFrame: testPill,
                                                    anchorFrame: testAnchor,
                                                    screenFrame: testScreen),
               "point 120pt below the pill is outside the calibrated trigger area")
        expect(!ShelfDockDragSupport.isPointNearDock(point: CGPoint(x: 1050, y: 930),
                                                    isProximate: false,
                                                    panelFrame: testPill,
                                                    anchorFrame: testAnchor,
                                                    screenFrame: testScreen),
               "point 150pt to the left of the pill is outside the calibrated trigger area")

        expect(ShelfDockDragSupport.isPointNearDock(point: CGPoint(x: 1200, y: 800),
                                                   isProximate: true,
                                                   panelFrame: testCard,
                                                   anchorFrame: testAnchor,
                                                   screenFrame: testScreen),
               "point inside the expanded card is near dock when proximate")
        expect(ShelfDockDragSupport.isPointNearDock(point: CGPoint(x: 1080, y: 800),
                                                   isProximate: true,
                                                   panelFrame: testCard,
                                                   anchorFrame: testAnchor,
                                                   screenFrame: testScreen),
               "point within retreat margin of expanded card remains near dock")
        expect(!ShelfDockDragSupport.isPointNearDock(point: CGPoint(x: 1000, y: 800),
                                                    isProximate: true,
                                                    panelFrame: testCard,
                                                    anchorFrame: testAnchor,
                                                    screenFrame: testScreen),
               "point outside retreat margin of expanded card leaves near dock")

        expect(!ShelfDockDragSupport.hasDwelled(since: 100.0, now: 100.08, required: 0.15),
               "short drag pass under 150ms does not count as dwelled")
        expect(ShelfDockDragSupport.hasDwelled(since: 100.0, now: 100.16, required: 0.15),
               "sustained hover over 150ms counts as dwelled")
        let shelfServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Shelf/ShelfService.swift",
            encoding: .utf8)) ?? ""
        let dockedWatchdog = shelfServiceSource
            .components(separatedBy: "private func startDockedWatchdog()")
            .dropFirst().first?.components(separatedBy: "\n    private func ").first ?? ""
        expect(dockedWatchdog.contains("updateDockedProximity(")
                && dockedWatchdog.contains("handleDragForEdge(at:"),
               "the drag watchdog finishes dock and edge dwells after pointer movement stops")
        let explicitShelfClose = shelfServiceSource
            .components(separatedBy: "func close()")
            .dropFirst().first?.components(separatedBy: "\n    func noteInteraction").first ?? ""
        let ordinaryShelfHide = shelfServiceSource
            .components(separatedBy: "func hide()")
            .dropFirst().first?.components(separatedBy: "\n    func close").first ?? ""
        let shelfViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Shelf/ShelfView.swift",
            encoding: .utf8)) ?? ""
        let dockedShelfViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Shelf/ShelfDropZoneView.swift",
            encoding: .utf8)) ?? ""
        expect(explicitShelfClose.contains("DefaultsKey.shelfClearOnClose")
                && explicitShelfClose.contains("clear()")
                && explicitShelfClose.contains("hide()")
                && !ordinaryShelfHide.contains("DefaultsKey.shelfClearOnClose"),
               "only an explicit shelf close consults the optional clearing preference")
        expect(shelfViewSource.contains("onDismiss ?? { shelf.close() }")
                && dockedShelfViewSource.contains("onDismiss: { shelf.collapseDocked() }"),
               "the floating close clears when requested while docked collapse keeps items")

        let shelfFile = ShelfPersistedItem(id: UUID(), kind: .file, title: "notes.pdf",
                                           path: "/tmp/notes.pdf")
        let shelfText = ShelfPersistedItem(id: UUID(), kind: .text, title: "Hello", text: "Hello world")
        let shelfLink = ShelfPersistedItem(id: UUID(), kind: .link, title: "example.com",
                                           url: "https://example.com/page")
        let shelfRoundTrip = [shelfFile, shelfText, shelfLink,
                              ShelfPersistedItem(id: UUID(), kind: .batch, title: "batch",
                                                 children: [shelfFile, shelfText])]
        if let encoded = try? JSONEncoder().encode(shelfRoundTrip),
           let decoded = try? JSONDecoder().decode([ShelfPersistedItem].self, from: encoded) {
            expect(decoded == shelfRoundTrip, "shelf items survive an encode and decode round trip")
        } else {
            expect(false, "shelf items must encode and decode")
        }

        // Every field at once, none left at its default. `CodingKeys` is written
        // out by hand next to the stored properties, and a property missing from
        // it is silently dropped by both the custom decoder and the synthesized
        // encoder, so a ninth field added without a case would stop being saved
        // and read with nothing else complaining.
        let shelfFullItem = ShelfPersistedItem(id: UUID(), kind: .file, title: "t", text: "x",
                                               url: "https://example.com/u", path: "/tmp/p",
                                               bookmark: Data([1]), children: [])
        let shelfFullRound = (try? JSONEncoder().encode(shelfFullItem))
            .flatMap { try? JSONDecoder().decode(ShelfPersistedItem.self, from: $0) }
        expect(shelfFullRound == shelfFullItem,
               "every persisted shelf field survives an encode and decode round trip")

        expect(ShelfPersistenceSupport.sanitized([shelfFile, shelfText, shelfLink]) { _ in true }
                   == [shelfFile, shelfText, shelfLink],
               "healthy shelf items pass sanitizing untouched")
        expect(ShelfPersistenceSupport.sanitized([shelfFile, shelfText]) { _ in false } == [shelfText],
               "shelf files that no longer exist are dropped at load")
        let bookmarkedShelfFile = ShelfPersistedItem(id: shelfFile.id, kind: .file,
                                                     title: "notes.pdf", path: "/tmp/notes.pdf",
                                                     bookmark: Data([1, 2, 3]))
        let healedShelf = ShelfPersistenceSupport.sanitized(
            [bookmarkedShelfFile],
            fileExists: { $0 == "/tmp/moved/renamed.pdf" },
            resolveBookmark: { _ in "/tmp/moved/renamed.pdf" })
        expect(healedShelf.count == 1
                && healedShelf.first?.path == "/tmp/moved/renamed.pdf"
                && healedShelf.first?.title == "renamed.pdf"
                && healedShelf.first?.id == shelfFile.id
                && healedShelf.first?.bookmark == bookmarkedShelfFile.bookmark,
               "a moved shelf file heals through its bookmark with its new path and name")
        expect(ShelfPersistenceSupport.sanitized(
                   [bookmarkedShelfFile],
                   fileExists: { _ in false },
                   resolveBookmark: { _ in "/tmp/also-gone.pdf" })
                   .isEmpty,
               "a bookmark that resolves to another dead path still drops the item")
        expect(ShelfPersistenceSupport.sanitized(
                   [bookmarkedShelfFile],
                   fileExists: { $0 == "/tmp/notes.pdf" },
                   resolveBookmark: { _ in
                       expect(false, "a living shelf path never pays for bookmark resolution")
                       return nil
                   }).first?.path == "/tmp/notes.pdf",
               "a living shelf file keeps its path without touching the bookmark")
        expect(ShelfPersistenceSupport.unmountedVolumeRoot(of: "/Volumes/NAS/docs/a.txt") == "/Volumes/NAS",
               "files under /Volumes report their volume root")
        expect(ShelfPersistenceSupport.unmountedVolumeRoot(of: "/Users/me/a.txt") == nil,
               "boot volume files have no volume root to wait for")
        expect(ShelfPersistenceSupport.sanitized(
                   [ShelfPersistedItem(id: UUID(), kind: .text, title: "", text: "  \n ")]) { _ in true }
                   .isEmpty,
               "whitespace-only shelf text is dropped at load")
        expect(ShelfPersistenceSupport.sanitized(
                   [ShelfPersistedItem(id: UUID(), kind: .link, title: "x", url: "not a url##"),
                    ShelfPersistedItem(id: UUID(), kind: .link, title: "x", url: "file:///etc/hosts"),
                    ShelfPersistedItem(id: UUID(), kind: .link, title: "x", url: "relative/path")]) { _ in true }
                   .isEmpty,
               "invalid, file and schemeless shelf links are dropped at load")
        let shelfBatch = ShelfPersistedItem(id: UUID(), kind: .batch, title: "batch",
                                            children: [shelfFile, shelfText])
        expect(ShelfPersistenceSupport.sanitized([shelfBatch]) { _ in false } == [shelfText],
               "a shelf batch left with one child collapses to that child")
        expect(ShelfPersistenceSupport.sanitized(
                   [ShelfPersistedItem(id: UUID(), kind: .batch, title: "batch",
                                       children: [shelfFile])]) { _ in false }
                   .isEmpty,
               "a shelf batch left empty is dropped")
        let oversizedShelf = (0..<(ShelfPersistenceSupport.maxLeaves + 20)).map { index in
            ShelfPersistedItem(id: UUID(), kind: .text, title: "t\(index)", text: "t\(index)")
        }
        expect(ShelfPersistenceSupport.sanitized(oversizedShelf) { _ in true }.count
                   == ShelfPersistenceSupport.maxLeaves,
               "shelf restore caps the number of items")
        expect(ShelfPersistenceSupport.boundedLiveText(
            String(repeating: "x", count: ShelfPersistenceSupport.maxTextLength + 1))?.count
                == ShelfPersistenceSupport.maxTextLength
                && ShelfPersistenceSupport.boundedLiveText("  \n") == nil
                && ShelfPersistenceSupport.boundedLiveText(
                    String(repeating: " ", count: ShelfPersistenceSupport.maxTextLength) + "x") == nil,
               "live shelf text follows the same bound and empty policy as restore")
        expect(ShelfPersistenceSupport.canAdd(existingLeaves: 199, newLeaves: 1)
                && !ShelfPersistenceSupport.canAdd(existingLeaves: 200, newLeaves: 1)
                && !ShelfPersistenceSupport.canAdd(existingLeaves: 199, newLeaves: 2),
               "live shelf additions cannot cross the persisted leaf ceiling")
        expect(ShelfPersistenceSupport.discardablePayloadPaths(
            candidatePaths: ["/owned/current.png", "/owned/new.png"],
            referencedPaths: ["/owned/current.png"]) == ["/owned/new.png"],
               "a rejected shelf drop never deletes a payload still referenced by a live item")
        expect(ShelfPersistenceSupport.needsPersistAfterRestore(
            restoredIsEmpty: false, liveItemCount: 1)
                && ShelfPersistenceSupport.needsPersistAfterRestore(
                    restoredIsEmpty: true, liveItemCount: 0)
                && !ShelfPersistenceSupport.needsPersistAfterRestore(
                    restoredIsEmpty: false, liveItemCount: 0),
               "shelf additions made during restore schedule the merged state for persistence")

        expect(ShelfBatchSupport.orderedItems(from: [(Int, String)]()).isEmpty,
               "shelf batch resolve with nothing resolved produces nothing")
        expect(ShelfBatchSupport.orderedItems(from: [(0, "a"), (1, "b"), (2, "c")]) == ["a", "b", "c"],
               "shelf batch resolve keeps drop order when providers finish in order")
        expect(ShelfBatchSupport.orderedItems(from: [(2, "c"), (0, "a"), (1, "b")]) == ["a", "b", "c"],
               "shelf batch resolve restores drop order when providers finish out of order")
        expect(ShelfBatchSupport.orderedItems(from: [(3, "z")]) == ["z"],
               "shelf batch resolve with a single provider produces that one item")

        expect(ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: 2)
                   && !ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: 0),
               "the list only claims command-C over an explicit selection")
        expect(ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 0, queryIsEmpty: true)
                   && !ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 0, queryIsEmpty: false)
                   && ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 1, queryIsEmpty: false),
               "the list claims command-A over a selection or an empty search field")
        expect(ClipboardHistoryBatch.listOwnsDeleteShortcut(batchCount: 2)
                   && !ClipboardHistoryBatch.listOwnsDeleteShortcut(batchCount: 0),
               "the list only claims command-delete over an explicit selection")
        expect(String(format: FeatureStrings.clipboard(.enUS).deleteSelectedFormat, 3) == "Delete 3",
               "English bulk delete string formats count correctly")
        expect(String(format: FeatureStrings.clipboard(.ptBR).deleteSelectedFormat, 3) == "Apagar 3",
               "Portuguese bulk delete string formats count correctly")

        // The switcher's header names the app and then the window under it. A
        // window titled after its own app made that header say the same word
        // twice, which reads as a bug. The model already knew the rule the
        // other way round, in displaySubtitle, and now the header asks it too.
        func switcherItem(title: String, appName: String, windowID: CGWindowID?) -> SwitcherItem {
            SwitcherItem(id: "\(appName).\(title)", title: title, appName: appName,
                         pid: 1, windowOwnerPID: 1, windowID: windowID,
                         isOnScreen: true, isAppHidden: false, isMinimized: false,
                         isFullscreen: false, isOnHiddenSpace: false, frame: .zero)
        }
        let sameName = switcherItem(title: "Example App", appName: "Example App", windowID: 7)
        expect(sameName.windowDetail(noOpenWindow: "No window") == nil,
               "the header says nothing under an app whose window carries the app's own name")
        let realTitle = switcherItem(title: "Untitled.txt", appName: "TextEdit", windowID: 7)
        expect(realTitle.windowDetail(noOpenWindow: "No window") == "Untitled.txt",
               "a window with a name of its own still gets its line")
        let noWindow = switcherItem(title: "", appName: "Finder", windowID: nil)
        expect(noWindow.windowDetail(noOpenWindow: "No window") == "No window",
               "an app with nothing open still says so")
        let cased = switcherItem(title: "example app", appName: "Example App", windowID: 7)
        expect(cased.windowDetail(noOpenWindow: "No window") == nil,
               "the same name in another case is still the same name")


        // MARK: Shelf tile tooltip

        let tooltipStrings = ShelfTooltipStrings(itemsFormat: "%d items", itemsFew: "%d items",
                                                 imageSingular: "%d image", imageFew: "%d images",
                                                 imagePlural: "%d images",
                                                 fileSingular: "%d file", fileFew: "%d files",
                                                 filePlural: "%d files",
                                                 noteSingular: "%d note", noteFew: "%d notes",
                                                 notePlural: "%d notes",
                                                 linkSingular: "%d link", linkFew: "%d links",
                                                 linkPlural: "%d links",
                                                 usesFewForm: false)
        // Russian agrees a noun with the number in front of it three ways, and
        // the rule is the number's last digits, not its size: 1 and 21 take the
        // first, 2 and 22 the middle, 11 and 25 the last. A two-way choice put
        // "2 файлов" on screen, which a reader sees as a mistake.
        let slavicStrings = ShelfTooltipStrings(itemsFormat: "many", itemsFew: "few",
                                                imageSingular: "one", imageFew: "few",
                                                imagePlural: "many",
                                                fileSingular: "one", fileFew: "few",
                                                filePlural: "many",
                                                noteSingular: "one", noteFew: "few",
                                                notePlural: "many",
                                                linkSingular: "one", linkFew: "few",
                                                linkPlural: "many",
                                                usesFewForm: true)
        for (count, wanted) in [(1, ShelfTooltipStrings.Form.one), (2, .few), (4, .few), (5, .many),
                                (11, .many), (12, .many), (14, .many), (15, .many),
                                (21, .one), (22, .few), (25, .many), (101, .one), (111, .many)] {
            expect(slavicStrings.form(for: count) == wanted,
                   "a language with a middle form asks for the right one at \(count)")
        }
        for count in [1, 2, 5, 11, 21, 22] {
            let wanted: ShelfTooltipStrings.Form = count == 1 ? .one : .many
            expect(tooltipStrings.form(for: count) == wanted,
                   "a language without a middle form still only chooses between one and many at \(count)")
        }
        expect(AppLanguage.allCases.filter(\.usesFewCountForm) == [.ru],
               "Russian is the one language of the thirteen that asks for the middle form")

        expectEqual(ShelfTooltipSupport.text(forFileNamed: "risaPOGCHAMP.gif", resolvedKind: "GIF Image"),
                    "risaPOGCHAMP.gif\nGIF Image",
                    "file tooltip shows the name and the resolved kind on separate lines")
        expectEqual(ShelfTooltipSupport.text(forFileNamed: "mystery.xyz", resolvedKind: nil),
                    "mystery.xyz",
                    "file tooltip falls back to the name alone when the kind lookup failed")
        expectEqual(ShelfTooltipSupport.text(forFileNamed: "mystery.xyz", resolvedKind: ""),
                    "mystery.xyz",
                    "an empty resolved kind is treated the same as no kind at all")

        expectEqual(ShelfTooltipSupport.text(forText: "hello world"),
                    "hello world",
                    "text under the cap is shown unchanged")
        expectEqual(ShelfTooltipSupport.text(forText: "  padded on both sides  "),
                    "padded on both sides",
                    "text tooltip trims the surrounding whitespace the stored payload keeps verbatim")
        let longText = String(repeating: "a", count: 600)
        expectEqual(ShelfTooltipSupport.text(forText: longText),
                    String(repeating: "a", count: ShelfTooltipSupport.textCap) + "…",
                    "text over the cap is truncated to exactly the cap length with a trailing ellipsis")

        expectEqual(ShelfTooltipSupport.text(forLink: URL(string: "https://example.com/a/b?q=1")!),
                    "https://example.com/a/b?q=1",
                    "link tooltip shows the full URL, not just the host the tile's own title shows")

        let emptyBreakdown = ShelfTooltipSupport.breakdown(of: [])
        expect(emptyBreakdown.total == 0,
               "an empty leaf list breaks down to all zero counts")
        expectEqual(ShelfTooltipSupport.text(forPile: emptyBreakdown, strings: tooltipStrings),
                    "0 items",
                    "an empty pile's tooltip does not crash and carries no trailing colon with nothing after it")

        let oneOfEachBreakdown = ShelfTooltipSupport.breakdown(of: [.image, .file, .note, .link])
        expect(oneOfEachBreakdown.images == 1 && oneOfEachBreakdown.files == 1
                   && oneOfEachBreakdown.notes == 1 && oneOfEachBreakdown.links == 1
                   && oneOfEachBreakdown.total == 4,
               "one leaf of each kind counts one of each and totals four")
        expectEqual(ShelfTooltipSupport.text(forPile: oneOfEachBreakdown, strings: tooltipStrings),
                    "4 items: 1 image, 1 file, 1 note, 1 link",
                    "a pile with one of each kind lists all four in a fixed order, each in its singular form")

        let sameKindBreakdown = ShelfTooltipSupport.breakdown(of: [.image, .image, .image])
        expectEqual(ShelfTooltipSupport.text(forPile: sameKindBreakdown, strings: tooltipStrings),
                    "3 items: 3 images",
                    "a pile of only one kind omits the other three from the breakdown entirely")

        let singularPluralBoundary = ShelfTooltipSupport.breakdown(of: [.image, .file, .file, .file])
        expectEqual(ShelfTooltipSupport.text(forPile: singularPluralBoundary, strings: tooltipStrings),
                    "4 items: 1 image, 3 files",
                    "singular and plural forms are chosen per kind, not for the pile as a whole")
    }

    static func runPersistence(expect: (Bool, String) -> Void) {
        // Loading the saved shelf keeps "nothing saved", "decoded whole",
        // "decoded with entries dropped" and "will not decode" apart. Only a
        // store read whole may be saved over and swept behind.
        expect(ShelfPersistenceSupport.load(nil) == .items([]),
               "no saved shelf blob restores as an empty shelf")
        expect(ShelfPersistenceSupport.load(Data("[]".utf8)) == .items([]),
               "a saved empty shelf restores as an empty shelf")
        expect(ShelfPersistenceSupport.load(Data("not json".utf8)) == .unreadable,
               "an unreadable shelf blob is not an empty shelf")
        expect(ShelfPersistenceSupport.load(Data(#"{"items":[]}"#.utf8)) == .unreadable,
               "a shelf blob that is not a list is not an empty shelf")

        // One bad entry drops only itself: an unknown kind (written by a newer
        // build) and a missing optional field must not cost the whole shelf.
        // The list that comes back is `.partial`, never `.items`: the dropped
        // entry's payload file is still on disk and the blob still points at
        // it, so the caller must not save over the store or sweep behind it.
        let mixedShelfBlob = Data("""
        [{"id":"8B3E1C2A-0000-4000-8000-000000000001","kind":"text","title":"keep","text":"body"},
         {"id":"8B3E1C2A-0000-4000-8000-000000000002","kind":"telepathy","title":"unknown kind"},
         {"kind":"link","title":"no id","url":"https://example.com"}]
        """.utf8)
        var mixedShelfTitles: [String] = []
        if case let .partial(loaded) = ShelfPersistenceSupport.load(mixedShelfBlob) {
            mixedShelfTitles = loaded.map(\.title)
        }
        expect(mixedShelfTitles == ["keep", "no id"],
               "an entry with an unknown kind drops itself and the rest load as "
               + "partial, found \(mixedShelfTitles)")
        expect(ShelfPersistenceSupport.load(Data(#"[{"kind":"telepathy"}]"#.utf8)) == .unreadable,
               "a stored list where no entry survives is unreadable, not empty")

        let wholeShelfBlob = Data("""
        [{"id":"8B3E1C2A-0000-4000-8000-000000000007","kind":"text","title":"a","text":"a"},
         {"id":"8B3E1C2A-0000-4000-8000-000000000008","kind":"batch","title":"pile","children":[
           {"id":"8B3E1C2A-0000-4000-8000-000000000009","kind":"text","title":"b","text":"b"}]}]
        """.utf8)
        var wholeShelfTitles: [String] = []
        if case let .items(loaded) = ShelfPersistenceSupport.load(wholeShelfBlob) {
            wholeShelfTitles = loaded.map(\.title)
        }
        expect(wholeShelfTitles == ["a", "pile"],
               "a store every entry of which decodes loads whole, found \(wholeShelfTitles)")

        // A child that drops itself costs its payload file the same way a
        // top-level entry does, so the depth it sits at must not change the
        // answer: the batch survives with its readable children, and the load
        // is still partial.
        let batchShelfBlob = Data("""
        [{"id":"8B3E1C2A-0000-4000-8000-000000000003","kind":"batch","title":"pile","children":[
           {"id":"8B3E1C2A-0000-4000-8000-000000000004","kind":"text","title":"a","text":"a"},
           {"id":"8B3E1C2A-0000-4000-8000-000000000005","kind":"telepathy","title":"b"},
           {"id":"8B3E1C2A-0000-4000-8000-000000000006","kind":"text","title":"c","text":"c"}]}]
        """.utf8)
        var batchShelfChildTitles: [String] = []
        if case let .partial(loaded) = ShelfPersistenceSupport.load(batchShelfBlob) {
            batchShelfChildTitles = (loaded.first?.children ?? []).map(\.title)
        }
        expect(batchShelfChildTitles == ["a", "c"],
               "a bad child drops itself, its batch survives and the store loads as "
               + "partial, found \(batchShelfChildTitles)")

        // The sweep decision lives in ShelfService, which `--test` does not
        // compile, so it is pinned by shape: restore may reach the payload
        // sweep only past the guard that a store read whole has to pass. A
        // `.partial` store's dropped entries still own files in that
        // directory, and the blob it kept still points at them.
        let restoreItemsBody = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Shelf/ShelfService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "private func restoreItems()")
            .dropFirst().first?
            .components(separatedBy: "\n    private func ").first ?? ""
        let pastRestoreGuard = restoreItemsBody
            .components(separatedBy: "guard case .items = store else { return }")
        expect(pastRestoreGuard.count == 2
                && !pastRestoreGuard[0].contains("sweepOwnedFiles(")
                && pastRestoreGuard[1].contains("sweepOwnedFiles("),
               "restore sweeps the shelf's payload files only for a store it read whole")

        // Guards the class, not the one instance that emptied shelves: the
        // saved blob may only be read through `load`, which hands the caller a
        // `.unreadable` case it has to answer for. A bare array decode brings
        // back the all-or-nothing form, where any single bad entry restores an
        // empty shelf that is then written back over the real one.
        // The scan has to report how many files it read: an enumerator that
        // finds nothing (the tests run from somewhere other than the repo
        // root) leaves the list empty, and a rule checked against no files at
        // all passes while guarding nothing.
        var rawShelfStoreDecoders: [String] = []
        var scannedShelfStoreFiles = 0
        if let sources = FileManager.default.enumerator(atPath: "Sources") {
            for case let path as String in sources where path.hasSuffix(".swift") {
                let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
                scannedShelfStoreFiles += 1
                if text.contains("decode([ShelfPersistedItem]") {
                    rawShelfStoreDecoders.append((path as NSString).lastPathComponent)
                }
            }
        }
        expect(scannedShelfStoreFiles > 0 && rawShelfStoreDecoders.isEmpty,
               "the saved shelf is read only through ShelfPersistenceSupport.load, "
               + "found a bare decode in \(rawShelfStoreDecoders.sorted()) "
               + "across \(scannedShelfStoreFiles) scanned files")
    }
}
