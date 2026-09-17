// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production destination methods run against controlled delivery results.
/// Native transport and payload integrity have separate transfer tests.
enum ShelfDropRoutingContract {
    enum AppFeature {
        static var shelf = Feature()
        static var mediaTools = Feature()
        struct Feature { var isAvailable = true }
    }
    enum NotchSupport {
        static var enabled = true
        static var visibleModules: [NotchModule] = [.files]
        static func isEnabled() -> Bool { enabled }
        static func modules() -> [NotchModule] { visibleModules }
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
        var draggingLocation = CGPoint.zero
        var draggingSource: AnyObject?
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
        var choosingFileDropDestination = false
        var targetsMediaDrop = false
        var pinned = false
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32, cameraWidth: 180)
        var surfaceSize: CGSize { geometry.expandedSize(module: .files) }
        var opened: [NotchModule] = []
        func refreshPresentation() {}
        func open(_ module: NotchModule, pinned: Bool = false, takeFocus: Bool = true) {
            opened.append(module)
            if pinned { self.pinned = true }
        }
    }
    class FileToolsState {
        enum MediaState { case idle, running }
        final class Media { var state = MediaState.idle }
        let media = Media()
        var mediaSession: NotchMediaSession?
        var mediaContentHeight: CGFloat?
        var mediaPresented = false
        var isRunning = false
        var acceptsMedia = true
        var inputs: [URL] = []
        func openMedia(_ tool: MediaTool, inputs: [URL]) -> Bool {
            guard acceptsMedia else { return false }
            self.inputs = inputs
            mediaSession = NotchMediaSession(inputs: inputs, tool: tool)
            mediaPresented = true
            mediaContentHeight = nil
            return true
        }
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
                    canAccept: { _ in notch.canAcceptFileDrop }, enter: { _ in },
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
                canAccept: { _ in notch.canAcceptFileDrop }, enter: { _ in },
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
        mediaDrops(expect: expect)
    }

    private static func mediaDrops(expect: (Bool, String) -> Void) {
        let board = NSPasteboard.withUniqueName()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("notch-media-drop-\(UUID().uuidString)", isDirectory: true)
        func reset() {
            Context.AppFeature.shelf.isAvailable = true
            Context.AppFeature.mediaTools.isAvailable = true
            Context.UserDefaults.standard.enabled = true
            Context.NotchSupport.enabled = true
            Context.NotchSupport.visibleModules = [.files]
            Context.ShelfService.shared = Context.ShelfService()
            Context.NotchFileToolsService.shared = Context.NotchFileToolsService()
        }
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: folder)
            reset()
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = folder.appendingPathComponent("image.png")
            let secondImage = folder.appendingPathComponent("second.jpg")
            let video = folder.appendingPathComponent("video.mov")
            let note = folder.appendingPathComponent("note.txt")
            for url in [image, secondImage, video, note] { try Data([0]).write(to: url) }
            let inputs: [([URL], MediaTool?)] = [
                ([image], .imageCompressor), ([image, secondImage], .imageCompressor),
                ([video], .videoCompressor), ([video, image], nil), ([image, note], nil),
                ([video, video], nil), ([note], nil), ([folder], nil),
                ([folder.appendingPathComponent("missing.png")], nil),
                ([URL(string: "https://example.com/image.png")!], nil), ([], nil),
            ]
            for (urls, tool) in inputs {
                for optimize in [false, true] {
                    reset()
                    board.clearContents()
                    board.writeObjects(urls as [NSURL])
                    let notch = Context.Notch()
                    notch.beginFileDrop(board)
                    expect(notch.choosingFileDropDestination == (tool != nil),
                           "only complete compatible file batches offer optimization: \(urls.map(\.lastPathComponent))")
                    let area = NotchFileToolsSupport.mediaDropArea(in: notch.geometry, size: notch.surfaceSize)
                    _ = notch.updateFileDrop(at: optimize ? CGPoint(x: area.midX, y: area.midY) : CGPoint(x: 40, y: area.midY))
                    let accepted = notch.accept(board)
                    let files = Context.NotchFileToolsService.shared
                    expect(accepted && files.mediaSession?.tool == (optimize ? tool : nil),
                           "dropping in each destination opens exactly its selected tool or the shelf")
                    if optimize, tool != nil {
                        expect(files.inputs == urls && !notch.pinned && Context.ShelfService.shared.ordinaryAccepts == 0,
                               "optimization receives the full input batch without pinning the island or shelving source files")
                    } else {
                        expect(Context.ShelfService.shared.ordinaryAccepts == 1 && !notch.pinned,
                               "ordinary drops keep the original shelf delivery path")
                    }
                    expect(!notch.choosingFileDropDestination && !notch.targetsMediaDrop,
                           "a finished drop removes its transient destinations")
                }
            }
            reset()
            board.clearContents()
            let text = NSPasteboardItem()
            text.setString("companion", forType: .string)
            board.writeObjects([image as NSURL, text])
            expect(Context.NotchFileToolsService.shared.mediaDropContent(for: board) == nil,
                   "a text companion prevents partial optimization of a mixed drag")

            for revoked in 0..<9 {
                reset()
                board.clearContents()
                board.writeObjects([image as NSURL])
                let notch = Context.Notch()
                notch.beginFileDrop(board)
                let area = NotchFileToolsSupport.mediaDropArea(in: notch.geometry, size: notch.surfaceSize)
                _ = notch.updateFileDrop(at: CGPoint(x: area.midX, y: area.midY))
                let files = Context.NotchFileToolsService.shared
                switch revoked {
                case 0: Context.AppFeature.mediaTools.isAvailable = false
                case 1: Context.AppFeature.shelf.isAvailable = false
                case 2: Context.UserDefaults.standard.enabled = false
                case 3: Context.NotchSupport.enabled = false
                case 4: Context.NotchSupport.visibleModules = []
                case 5: files.media.state = .running
                case 6: files.isRunning = true
                case 7: notch.acceptsSystemFeedback = false
                default: notch.captureControls = 1
                }
                expect(!notch.accept(board) && files.inputs.isEmpty && Context.ShelfService.shared.ordinaryAccepts == 0,
                       "revoked access or running work rejects optimization without rerouting or replacing work")
                expect(!notch.choosingFileDropDestination && !notch.targetsMediaDrop,
                       "a refused drop clears its transient presentation")
            }
            reset()
            let notch = Context.Notch()
            notch.beginFileDrop(board)
            notch.endFileDrop()
            expect(!notch.choosingFileDropDestination && Context.NotchFileToolsService.shared.mediaSession == nil,
                   "leaving a drag never creates a media workspace")

            for initiallyPinned in [false, true] {
                reset()
                let repeatDrop = Context.Notch()
                repeatDrop.pinned = initiallyPinned
                let files = Context.NotchFileToolsService.shared
                for (input, optimize) in [(image, true), (secondImage, false), (secondImage, true), (video, true)] {
                    board.clearContents()
                    board.writeObjects([input as NSURL])
                    repeatDrop.beginFileDrop(board)
                    expect(repeatDrop.choosingFileDropDestination,
                           "every new compatible drag offers both destinations even with an existing media workspace")
                    let area = NotchFileToolsSupport.mediaDropArea(in: repeatDrop.geometry, size: repeatDrop.surfaceSize)
                    _ = repeatDrop.updateFileDrop(at: CGPoint(x: optimize ? area.midX : 40, y: area.midY))
                    expect(repeatDrop.accept(board) && files.mediaPresented == optimize && repeatDrop.pinned == initiallyPinned,
                           "each drop follows its new destination and leaves the user's pin choice untouched")
                    if optimize { expect(files.inputs == [input], "a new optimization replaces only the deliberately selected input") }
                    else { expect(files.inputs == [image], "choosing the shelf hides media without discarding its previous work") }
                }
                let id = files.mediaSession!.id
                files.updateMediaHeight(id: id, height: 321.3)
                expect(files.mediaContentHeight == 322, "media records its actual content height at a stable whole-point boundary")
                for rejected in [CGFloat.nan, .infinity, 0, -1] { files.updateMediaHeight(id: id, height: rejected) }
                files.updateMediaHeight(id: UUID(), height: 900)
                expect(files.mediaContentHeight == 322, "invalid sizes and callbacks from a replaced workspace cannot stretch the island")
                files.updateMediaHeight(id: id, height: 240)
                expect(files.mediaContentHeight == 240, "hiding extra media controls shrinks the recorded content height")
                files.media.state = .running
                repeatDrop.beginFileDrop(board)
                let area = NotchFileToolsSupport.mediaDropArea(in: repeatDrop.geometry, size: repeatDrop.surfaceSize)
                expect(repeatDrop.choosingFileDropDestination
                       && !repeatDrop.updateFileDrop(at: CGPoint(x: area.midX, y: area.midY)),
                       "running media keeps the chooser available but cannot be overwritten by another drop")
                expect(repeatDrop.updateFileDrop(at: CGPoint(x: 40, y: area.midY)) && repeatDrop.accept(board)
                       && !files.mediaPresented && files.media.state == .running,
                       "the shelf remains usable while an optimization continues without interruption")
                files.showMedia()
                expect(files.mediaPresented && files.mediaSession?.id == id,
                       "returning to media resumes the same work and results")
                files.media.state = .idle
                files.acceptsMedia = false
                expect(!files.openMediaDrop(board) && files.mediaSession?.id == id,
                       "a late input validation failure cannot claim success using a previous media session")
            }

            for finishOutside in [false, true] {
                reset()
                board.clearContents()
                board.writeObjects([image as NSURL])
                let destination = Context.Notch()
                let canvas = Context.Canvas()
                canvas.visibleRect = CGRect(origin: .zero, size: destination.surfaceSize)
                canvas.dropActions = Context.NotchFileDropActions(
                    canAccept: { _ in destination.canAcceptFileDrop },
                    enter: { destination.beginFileDrop($0) },
                    accept: { destination.accept($0) },
                    exit: { destination.endFileDrop() },
                    update: { destination.updateFileDrop(at: $0) })
                let area = NotchFileToolsSupport.mediaDropArea(in: destination.geometry, size: destination.surfaceSize)
                var drag = Context.NSDraggingInfo(draggingPasteboard: board, draggingDestinationWindow: nil,
                                                  draggingLocation: CGPoint(x: 40, y: area.midY))
                expect(canvas.draggingUpdated(drag) == .copy && !destination.targetsMediaDrop,
                       "native dragging starts on the shelf side")
                drag.draggingLocation = CGPoint(x: area.midX, y: area.midY)
                expect(canvas.draggingUpdated(drag) == .copy && destination.targetsMediaDrop,
                       "moving across the island highlights the media destination")
                drag.draggingLocation = finishOutside ? CGPoint(x: -1, y: -1) : CGPoint(x: 40, y: area.midY)
                expect(canvas.performDragOperation(drag) == !finishOutside
                       && Context.NotchFileToolsService.shared.mediaSession == nil,
                       "the release point is rechecked even when the last drag update targeted media")
                expect(Context.ShelfService.shared.ordinaryAccepts == (finishOutside ? 0 : 1)
                       && !destination.choosingFileDropDestination,
                       "releasing outside cancels cleanly and releasing over the shelf preserves its route")
            }
        } catch { expect(false, "media drop fixtures failed: \(error)") }
    }
}
