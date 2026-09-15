// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production destination methods run against controlled delivery results.
/// Native transport and payload integrity have separate transfer tests.
enum ShelfDropRoutingContract {
    enum AppFeature {
        static var shelf = Feature()
        struct Feature { var isAvailable = true }
    }
    enum UserDefaults {
        static var standard = Store()
        struct Store {
            var enabled = true
            func bool(forKey key: String) -> Bool { enabled }
        }
    }
    final class Window {}
    struct NSDraggingInfo {
        let draggingPasteboard: NSPasteboard
        let draggingDestinationWindow: Window?
    }
    class ShelfState {
        var dockedPanel = Window()
        var dockCompletions = 0
        var promises: [Int] = []
        var ordinaryItems: [String] = []
        var accepts = true
        var ordinaryAccepts = 0
        var promisedAccepts = 0
        var deliveredItems: [String] = []
        func filePromiseReceivers(from board: NSPasteboard) -> [Int] { promises }
        func nonPromisedItems(from board: NSPasteboard) -> [String] { ordinaryItems }
        func accept(pasteboard: NSPasteboard) -> Bool { ordinaryAccepts += 1; return accepts }
        func beginPromisedFileReceive(_ receivers: [Int], additions: [String], mergeInto target: UUID?) -> Bool {
            promisedAccepts += 1
            deliveredItems = additions
            return accepts
        }
        func dockDidAccept() { dockCompletions += 1 }
    }
    class NotchState {
        var acceptsSystemFeedback = true
        var captureControls: Int?
        var modules: [NotchModule] = [.files]
        var heldDrag = true
        var dragPlaceholder = true
        var opened: [NotchModule] = []
        func open(_ module: NotchModule) { opened.append(module) }
    }
}

enum ShelfDropRoutingTests {
    private typealias Context = ShelfDropRoutingContract

    static func run(expect: (Bool, String) -> Void) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        for promised in [false, true] {
            for accepted in [false, true] {
                Context.AppFeature.shelf.isAvailable = true
                Context.UserDefaults.standard.enabled = true
                Context.ShelfService.shared = Context.ShelfService()
                let shelf = Context.ShelfService.shared
                shelf.promises = promised ? [1, 2] : []
                shelf.ordinaryItems = ["file", "note"]
                shelf.accepts = accepted
                let notch = Context.Notch()
                let canvas = Context.Canvas()
                canvas.dropActions = Context.NotchFileDropActions(
                    canAccept: { _ in notch.canAcceptFileDrop }, enter: {},
                    accept: { notch.accept($0) }, exit: {})
                expect(canvas.beginDrop(board, localSource: true) == [],
                       "the island leaves internal tile drags to their merge destinations")
                expect(!canvas.finishDrop(board) && shelf.promisedAccepts + shelf.ordinaryAccepts == 0,
                       "an unaccepted gesture never reaches file delivery")
                expect(canvas.beginDrop(board, localSource: false) == .copy,
                       "an external drag remains accepted by the stable island destination")
                expect(canvas.finishDrop(board) == accepted,
                       "the island reports the actual shelf admission result")
                expect(shelf.promisedAccepts == (promised ? 1 : 0)
                       && shelf.ordinaryAccepts == (promised ? 0 : 1),
                       "promised attachments reach native delivery instead of their fallback text")
                expect(!promised || shelf.deliveredItems == ["file", "note"],
                       "ordinary file and note companions remain attached to a promised delivery")
                expect(notch.opened == (accepted ? [.files] : [])
                       && notch.heldDrag == !accepted && notch.dragPlaceholder == !accepted,
                       "only accepted deliveries open files and release the island placeholder")
                expect(!canvas.finishDrop(board), "one gesture cannot deliver twice")

                let dockDrop = Context.NSDraggingInfo(draggingPasteboard: board,
                                                     draggingDestinationWindow: shelf.dockedPanel)
                expect(shelf.accept(draggingInfo: dockDrop) == accepted
                       && shelf.dockCompletions == (accepted ? 1 : 0),
                       "the separate dock keeps its completion behavior through the shared receiver")
            }
        }
        for revoked in 0..<5 {
            Context.AppFeature.shelf.isAvailable = true
            Context.UserDefaults.standard.enabled = true
            Context.ShelfService.shared = Context.ShelfService()
            let shelf = Context.ShelfService.shared
            shelf.promises = [1]
            let notch = Context.Notch()
            let canvas = Context.Canvas()
            canvas.dropActions = Context.NotchFileDropActions(
                canAccept: { _ in notch.canAcceptFileDrop }, enter: {},
                accept: { notch.accept($0) }, exit: {})
            _ = canvas.beginDrop(board, localSource: false)
            switch revoked {
            case 0: Context.AppFeature.shelf.isAvailable = false
            case 1: Context.UserDefaults.standard.enabled = false
            case 2: notch.modules = []
            case 3: notch.acceptsSystemFeedback = false
            default: notch.captureControls = 1
            }
            expect(!canvas.finishDrop(board) && shelf.promisedAccepts == 0 && notch.opened.isEmpty,
                   "a destination disabled after hover cannot start an attachment delivery")
        }
        Context.AppFeature.shelf.isAvailable = true
        Context.UserDefaults.standard.enabled = true
    }
}
