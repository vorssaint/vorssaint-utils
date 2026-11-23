// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production drag completion runs with isolated windows and preferences.
enum ShelfDragCompletionContract {
    final class Window: NSWindow {
        var shown = true
        override var isVisible: Bool { shown }
    }
    static func window() -> Window {
        Window(contentRect: CGRect(x: 0, y: 0, width: 276, height: 188),
               styleMask: .borderless, backing: .buffered, defer: true)
    }
    static let standaloneWindow = window()
    typealias ShelfService = Service
    typealias ShelfTileView = Tile
    struct NSEvent {
        static var pressedMouseButtons = 1
        let locationInWindow = NSPoint(x: 10, y: 10)
        let clickCount = 1
        let modifierFlags: AppKit.NSEvent.ModifierFlags = []
    }
    enum QuickToolHUD {
        static func show(icon: String, message: String) {}
    }
    struct L10n {
        static let shared = L10n()
        var s: Self { self }
        let shelfFileMissing = "Missing"
    }

    /// Real view attachment and pasteboard items, without an interactive drag.
    class TileState: NSView {
        var item: Service.Item
        let isSelected: Bool
        let isExpanded: Bool
        let isPinned: Bool
        let iconView = NSImageView()
        var closeButton: NSButton!
        var pinBadge: NSImageView?
        var expandButton: NSButton?
        var mouseDownPoint: NSPoint = .zero
        var didDrag = false
        var draggedIDs: [UUID] = []
        var pendingDragEvent: NSEvent?
        var pendingDragID: UUID?
        var dragPreparation: DispatchWorkItem?
        var draggingItems: [NSDraggingItem] = []
        var replacementsAtStart = -1
        var sessionStarts = 0
        init(item: Service.Item, isSelected: Bool, isExpanded: Bool, isPinned: Bool) {
            self.item = item
            self.isSelected = isSelected
            self.isExpanded = isExpanded
            self.isPinned = isPinned
            super.init(frame: CGRect(origin: .zero, size: ShelfTilesView.tileSize))
            buildSubviews()
        }
        required init?(coder: NSCoder) { fatalError() }
        convenience init(item: Service.Item) {
            self.init(item: item, isSelected: false, isExpanded: false, isPinned: false)
            standaloneWindow.contentView = self
        }
        @objc func toggleBatchExpansion() { preconditionFailure() }
        @objc func removeSelf() { preconditionFailure() }
        func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: AnyObject) {
            sessionStarts += 1
            replacementsAtStart = Service.shared.replacements.count
            draggingItems = items
        }
    }

    static func dragItems(_ ids: [UUID]) -> [Service.Item] {
        ids.map { Service.Item(id: $0, payload: .text("note"), title: "note", icon: NSImage(), isImage: false) }
    }

    enum UserDefaults {
        static var standard = Store()
        struct Store {
            var closeAfterDrop = true
            var removeAfterDrop = true
            func bool(forKey key: String) -> Bool {
                key == DefaultsKey.shelfCloseAfterDrop ? closeAfterDrop
                    : key == DefaultsKey.shelfRemoveAfterDrop && removeAfterDrop
            }
        }
    }

    final class NotchService {
        static var shared = NotchService()
        var presentationWindow: Window? = window()
        var expanded = true
        var selected: NotchModule = .files
        var showingAppPanel = false
        var showingSections = false
        var pinned = false
        var heldDrag = false
        var closures = 0
        var dragMoves: [CGPoint] = []
        func fileDragChanged(_ active: Bool, internalDrag: Bool) { heldDrag = active && internalDrag }
        func shelfDragMoved(to point: CGPoint) { dragMoves.append(point) }
        func collapse() {
            precondition(!heldDrag, "release the drag before trying to collapse")
            closures += 1
            expanded = false
        }
    }

    static func reset() {
        UserDefaults.standard = UserDefaults.Store()
        NotchService.shared = NotchService()
        Service.shared = Service()
        NSEvent.pressedMouseButtons = 1
    }
}

enum ShelfDragCompletionTests {
    private typealias Context = ShelfDragCompletionContract

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        for pinned in [false, true] {
            for close in [false, true] {
                for accepted in [false, true] {
                    for merged in [false, true] {
                        Context.reset()
                        let service = Context.Service()
                        let notch = Context.NotchService.shared
                        notch.pinned = pinned
                        service.isPinned = !pinned
                        Context.UserDefaults.standard.closeAfterDrop = close
                        let id = UUID()
                        service.beginInternalDrag(items: Context.dragItems([id]), from: notch.presentationWindow, containsPackageContent: false)
                        service.internalDragWasMerged = merged
                        suite.expect(notch.heldDrag, "a drag from the notch holds its working surface")
                        service.completeInternalDrag(dropAccepted: accepted)
                        let transferred = accepted && !merged
                        suite.expect(notch.closures == (transferred && close && !pinned ? 1 : 0),
                               "notch completion honors accepted drops, local merges, its pin and the close preference")
                        suite.expect(service.removed == (transferred ? [id] : []) && !notch.heldDrag
                               && service.internalDragWindow == nil && service.activeInternalDragIDs.isEmpty
                               && !service.internalDragHoldsPackageContent,
                               "completion preserves removal policy and always releases the drag's source")
                        suite.expect(service.floatingClosures == 0 && service.dockedClosures == 0,
                               "closing an embedded shelf leaves the separate presentations alone")
                    }
                }
            }
        }

        for docked in [false, true] {
            Context.reset()
            let service = Context.Service()
            let notch = Context.NotchService.shared
            let source = Context.window()
            if docked { service.dockedPanel = source } else { service.panel = source }
            service.isVisible = !docked
            service.dockedVisible = docked
            notch.pinned = true
            Context.UserDefaults.standard.removeAfterDrop = false
            service.beginInternalDrag(items: Context.dragItems([UUID()]), from: source, containsPackageContent: false)
            suite.expect(!notch.heldDrag, "a separate shelf cannot hold an unrelated notch open")
            service.completeInternalDrag(dropAccepted: true)
            suite.expect(service.floatingClosures == (docked ? 0 : 1) && service.dockedClosures == (docked ? 1 : 0)
                   && notch.closures == 0 && service.removed.isEmpty,
                   "separate shelf completion retains its own close, pin and removal behavior")
        }

        // Only a tile dragged from the island tells it where the drag is, and
        // only while the drag lasts.
        for fromNotch in [false, true] {
            Context.reset()
            let service = Context.Service()
            let notch = Context.NotchService.shared
            let source = fromNotch ? notch.presentationWindow! : Context.window()
            if !fromNotch { service.panel = source; service.isVisible = true }
            service.internalDragMoved(to: CGPoint(x: 1, y: 1))
            service.beginInternalDrag(items: Context.dragItems([UUID()]), from: source, containsPackageContent: false)
            service.internalDragMoved(to: CGPoint(x: 2, y: 2))
            service.completeInternalDrag(dropAccepted: false)
            service.internalDragMoved(to: CGPoint(x: 3, y: 3))
            suite.expect(notch.dragMoves == (fromNotch ? [CGPoint(x: 2, y: 2)] : []),
                   "only a drag from the island, while it lasts, can move the island aside")
        }

        Context.reset()
        let pinnedService = Context.Service()
        let pinnedID = UUID(), looseID = UUID()
        pinnedService.protectedIDs = [pinnedID]
        pinnedService.beginInternalDrag(items: Context.dragItems([pinnedID, looseID]), from: Context.window(), containsPackageContent: false)
        pinnedService.completeInternalDrag(dropAccepted: true)
        suite.expect(pinnedService.removed == [looseID],
               "a pinned shelf item survives a drag-out that removes the rest")

        for changedSurface in 0..<5 {
            Context.reset()
            let service = Context.Service()
            let notch = Context.NotchService.shared
            let source = notch.presentationWindow!
            service.panel = Context.window()
            service.isVisible = true
            service.beginInternalDrag(items: Context.dragItems([UUID()]), from: source, containsPackageContent: false)
            switch changedSurface {
            case 0: notch.selected = .music
            case 1: notch.showingSections = true
            case 2: notch.showingAppPanel = true
            case 3: notch.expanded = false
            default: notch.presentationWindow = Context.window(); notch.heldDrag = false
            }
            service.completeInternalDrag(dropAccepted: true)
            suite.expect(notch.closures == 0 && service.floatingClosures == 0,
                   "an old drag cannot close a different destination or a replacement notch window")
        }
        fileDragProtection(suite)
    }

    private static func drain(until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !done() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    }

    private static func beginAndWait(_ tile: Context.Tile) {
        tile.beginItemDrag(with: Context.NSEvent())
        drain { tile.pendingDragID == nil }
    }

    private enum PendingGesture: CaseIterable {
        case held, heldBatch, mouseUp, newSelection, restoredSelection, changedFile, renamedFile, changedChild
        case removed, detached
        case hiddenWindow, hiddenAncestor
    }

    private static func rebuildDuringDrag(_ suite: TestSuite, source: Context.Service.Item,
                                          sibling: Context.Service.Item) {
        let thumbnail = Context.Service.Item(id: sibling.id, payload: sibling.payload, title: sibling.title,
                                             icon: NSImage(size: NSSize(width: 21, height: 17)),
                                             isImage: sibling.isImage, hasContentThumbnail: true)
        let batchID = UUID()
        func batch(_ first: Context.Service.Item) -> Context.Service.Item {
            Context.Service.Item(id: batchID, payload: .batch([first, source]), title: "Files",
                                 icon: first.icon, isImage: false, hasContentThumbnail: first.hasContentThumbnail)
        }
        for gesture in PendingGesture.allCases {
            Context.reset()
            let service = Context.Service.shared
            let draggingBatch = gesture == .heldBatch || gesture == .changedChild
            service.items = draggingBatch ? [batch(sibling)] : [source, sibling]
            if gesture == .held { service.selection = [source.id] }
            let window = Context.window()
            let scroll = NSScrollView(frame: window.frame)
            let document = NSView()
            window.contentView = scroll
            scroll.documentView = document
            defer { window.contentView = nil }
            let coordinator = Context.ShelfTilesView.Coordinator()
            func rebuild() {
                Context.ShelfTilesView.rebuildTiles(scroll: scroll, items: service.items, selection: service.selection,
                                                    expandedBatches: [], pinnedIDs: [], coordinator: coordinator)
            }
            rebuild()
            guard let tile = document.subviews.first as? Context.Tile, tile.item.id == service.items[0].id else {
                suite.expect(false, "the Shelf rebuild mounts the source file tile")
                return
            }
            let held = DispatchSemaphore(value: 0)
            Context.Service.dragFileQueue.async { _ = held.wait(timeout: .now() + 3) }
            tile.mouseDragged(with: Context.NSEvent())
            suite.expect(tile.pendingDragID != nil && tile.sessionStarts == 0,
                         "the file gesture is pending when the sibling thumbnail arrives")
            // A completed thumbnail replaces the file and becomes its pile's face if it is first.
            let replacement = draggingBatch ? batch(thumbnail) : thumbnail
            service.items[draggingBatch ? 0 : 1] = replacement
            rebuild()
            let updated = document.subviews.compactMap { $0 as? Context.Tile }.first { $0.item.id == replacement.id }
            let showsThumbnail = updated?.subviews.flatMap(\.subviews).contains {
                ($0 as? NSImageView)?.image?.size == thumbnail.icon.size
            } ?? false
            suite.expect(showsThumbnail && updated?.item.hasContentThumbnail == true,
                         "the Shelf refreshes the thumbnail during file preparation for \(gesture)")
            switch gesture {
            case .held, .heldBatch: break
            case .mouseUp:
                tile.mouseUp(with: Context.NSEvent())
            case .newSelection:
                // SwiftUI has not redrawn yet, and the unselected source still resolves to the same drag leaves.
                service.selection = [sibling.id]
            case .restoredSelection:
                service.selection = [sibling.id]
                rebuild()
                service.selection = []
                rebuild()
            case .changedFile:
                service.items[0] = Context.Service.Item(id: source.id, payload: sibling.payload, title: sibling.title,
                                                        icon: source.icon, isImage: source.isImage)
                rebuild()
            case .renamedFile:
                let title = "Renamed file"
                service.items[0] = Context.Service.Item(id: source.id, payload: source.payload, title: title,
                                                        icon: source.icon, isImage: source.isImage)
                rebuild()
                let current = document.subviews.first as? Context.Tile
                let showsTitle = current?.subviews.contains { ($0 as? NSTextField)?.stringValue == title } ?? false
                suite.expect(tile.window == nil && current?.window === window && showsTitle,
                             "renaming a file detaches its old tooltip owner and mounts the new title")
            case .changedChild:
                // Stacking a note onto the first child preserves both its ID and the parent pile's face.
                let note = Context.dragItems([UUID()])[0]
                let nested = Context.Service.Item(id: thumbnail.id, payload: .batch([thumbnail, note]),
                                                  title: "2 items", icon: thumbnail.icon, isImage: false,
                                                  hasContentThumbnail: thumbnail.hasContentThumbnail)
                service.items[0] = batch(nested)
                rebuild()
                let current = document.subviews.first as? Context.Tile
                let child = current?.item.batchItems.first
                suite.expect(tile.window == nil && current?.window === window
                             && child?.id == nested.id && child?.batchItems.map(\.id) == [thumbnail.id, note.id],
                             "a changed child with the same ID detaches the pile's old tooltip owner")
            case .removed:
                service.items.removeFirst()
                rebuild()
            case .detached:
                window.contentView = nil
            case .hiddenWindow:
                window.shown = false // orderOut keeps the content attached to its window.
            case .hiddenAncestor:
                document.isHidden = true
            }
            held.signal()
            // A cancelled work item can skip its completion. Wait for every
            // earlier worker and its main-queue callback before testing either outcome.
            Context.Service.dragFileQueue.sync {}
            var delivered = false
            DispatchQueue.main.async { delivered = true }
            drain { delivered }
            suite.expect(delivered, "the pending file gesture finishes for \(gesture)")
            if gesture == .held || gesture == .heldBatch {
                let expected = gesture == .heldBatch ? [sibling, source] : [source]
                let urls = tile.draggingItems.compactMap { $0.item as? NSURL }.map { $0 as URL }
                suite.expect(tile.sessionStarts == 1 && service.activeInternalDragIDs == expected.map(\.id)
                             && urls.map(Context.Service.Item.Payload.file) == expected.map(\.payload),
                             "the held gesture starts once with its original files after the thumbnail rebuild")
                service.completeInternalDrag(dropAccepted: false)
            } else {
                suite.expect(tile.sessionStarts == 0 && service.activeInternalDragIDs.isEmpty,
                             "the pending gesture cannot start after \(gesture)")
            }
        }
    }

    private static func fileDragProtection(_ suite: TestSuite) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("vorss-shelf-drag-tests-\(UUID())")
        defer { try? fm.removeItem(at: root) }
        do {
            let package = root.appendingPathComponent("Library.app", isDirectory: true)
            let resources = package.appendingPathComponent("Contents/Resources", isDirectory: true)
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            let inside = resources.appendingPathComponent("photo.jpeg")
            let plain = root.appendingPathComponent("plain.jpeg")
            try Data("package content".utf8).write(to: inside)
            try Data("ordinary file".utf8).write(to: plain)
            let directoryLink = root.appendingPathComponent("exports", isDirectory: true)
            let fileLink = root.appendingPathComponent("photo-link")
            let packageLink = root.appendingPathComponent("package-link")
            try fm.createSymbolicLink(at: directoryLink, withDestinationURL: resources)
            try fm.createSymbolicLink(at: fileLink, withDestinationURL: inside)
            try fm.createSymbolicLink(at: packageLink, withDestinationURL: package)

            func item(_ url: URL, bookmark: Data? = nil) -> Context.Service.Item {
                Context.Service.Item(payload: .file(url), title: url.lastPathComponent,
                                     icon: NSImage(), isImage: false, bookmark: bookmark)
            }
            rebuildDuringDrag(suite, source: item(plain), sibling: item(inside))
            // Hold the real preparation queue before the tile handles its event.
            // Main must be able to process cancellation before the I/O can start.
            Context.reset()
            let early = item(plain)
            let slowService = Context.Service.shared
            slowService.items = [early]
            let slowTile = Context.Tile(item: early)
            let releaseIO = DispatchSemaphore(value: 0)
            Context.Service.dragFileQueue.async { _ = releaseIO.wait(timeout: .now() + 3) }
            slowTile.beginItemDrag(with: Context.NSEvent())
            suite.expect(slowTile.pendingDragID != nil && slowTile.draggingItems.isEmpty
                         && slowService.activeInternalDragIDs.isEmpty,
                         "a delayed disk returns the mouse callback without taking the drag session")
            slowTile.cancelDragPreparation()
            releaseIO.signal()
            beginAndWait(slowTile)
            suite.expect(slowTile.draggedIDs == [early.id], "the next gesture can drag normally after cancellation")
            slowService.completeInternalDrag(dropAccepted: false)

            let held = DispatchSemaphore(value: 0)
            Context.Service.dragFileQueue.async { _ = held.wait(timeout: .now() + 3) }
            let released = Context.Tile(item: early)
            released.beginItemDrag(with: Context.NSEvent())
            Context.NSEvent.pressedMouseButtons = 0
            held.signal()
            drain { released.pendingDragID == nil }
            suite.expect(released.draggingItems.isEmpty && slowService.activeInternalDragIDs.isEmpty,
                         "a worker finishing after mouse-up cannot start a stale session")
            Context.reset()

            let cases: [(URL, Bool, String)] = [
                (inside, true, "package content"),
                (resources, true, "a directory inside a package"),
                (directoryLink.appendingPathComponent("photo.jpeg"), true, "content through a directory symlink"),
                (plain, false, "an ordinary file"),
                (package, false, "a whole package"),
                (fileLink, false, "a symlink to a package file"),
                (packageLink, false, "a symlink to a whole package"),
            ]
            for (url, protected, label) in cases {
                Context.reset()
                let service = Context.Service.shared
                let entry = item(url)
                service.items = [entry]
                let tile = Context.Tile(item: entry)
                beginAndWait(tile)
                let writer = tile.draggingItems.first?.item as? NSURL
                suite.expect(writer?.path == url.path && service.activeInternalDragIDs == [entry.id],
                       "the production tile keeps the selected payload and identity for \(label)")
                let operations = service.sourceOperationMask(for: .outsideApplication)
                suite.expect(operations == (protected ? .copy : [.copy, .move]),
                       "the production drag only protects package contents for \(label)")
                // Exercise a same-volume destination using only the offered
                // operation. Everything here belongs to this temporary fixture.
                let destination = root.appendingPathComponent("drop-\(UUID())")
                if operations.contains(.move) {
                    try fm.moveItem(at: url, to: destination)
                } else {
                    try fm.copyItem(at: url, to: destination)
                }
                suite.expect(fm.fileExists(atPath: destination.path)
                        && fm.fileExists(atPath: url.path) == protected,
                       "the offered transfer leaves package contents in place and permits legitimate moves for \(label)")
                if url == fileLink || url == packageLink {
                    suite.expect(fm.fileExists(atPath: inside.path),
                           "moving the symlink itself leaves its package target untouched")
                }
                if operations.contains(.move) {
                    try fm.moveItem(at: destination, to: url)
                } else {
                    try fm.removeItem(at: destination)
                }
                suite.expect(service.sourceOperationMask(for: .withinApplication) == .move,
                       "internal Shelf stacking remains a move for \(label)")
                service.completeInternalDrag(dropAccepted: false)
                suite.expect(!service.internalDragHoldsPackageContent && service.removed.isEmpty,
                       "cancelling \(label) clears the protection without removing its tile")
            }

            // The bookmark follows the inode into a package, but the stored
            // tile still has its old URL during the production drag callback.
            Context.reset()
            let recovered = resources.appendingPathComponent("recovered.jpeg")
            let saved = item(plain, bookmark: try plain.bookmarkData())
            try fm.moveItem(at: plain, to: recovered)
            let service = Context.Service.shared
            service.items = [saved]
            let healedTile = Context.Tile(item: saved)
            beginAndWait(healedTile)
            let writer = healedTile.draggingItems.first?.item as? NSURL
            suite.expect(writer.map { ($0 as URL).standardizedFileURL.path } == recovered.standardizedFileURL.path
                    && service.items.first?.payload == .file(plain)
                    && healedTile.replacementsAtStart == 0,
                   "the bookmark reaches the actual drag before the deferred saved-item replacement")
            suite.expect(service.sourceOperationMask(for: .outsideApplication) == .copy,
                   "a healed bookmark moved into a package cannot offer Finder a move")
            service.completeInternalDrag(dropAccepted: true)
            suite.expect(service.removed == [saved.id] && !service.internalDragHoldsPackageContent
                    && fm.fileExists(atPath: recovered.path),
                   "an accepted protected drag retires its tile and resets the drag state")

            Context.reset()
            let exported = root.appendingPathComponent("exported.jpeg")
            let savedInside = item(recovered, bookmark: try recovered.bookmarkData())
            try fm.moveItem(at: recovered, to: exported)
            let exportedService = Context.Service.shared
            exportedService.items = [savedInside]
            let exportedTile = Context.Tile(item: savedInside)
            beginAndWait(exportedTile)
            let exportedWriter = exportedTile.draggingItems.first?.item as? NSURL
            suite.expect(exportedWriter.map { ($0 as URL).standardizedFileURL.path } == exported.standardizedFileURL.path,
                   "a bookmark heals into the drag even outside its package")
            suite.expect(exportedService.sourceOperationMask(for: .outsideApplication) == [.copy, .move],
                   "a bookmark moved out of a package is checked at its new location and can move")
            exportedService.completeInternalDrag(dropAccepted: false)

            // Batch flattening and mixed selections use the same copy-only
            // decision, while pinned and retained files remain copy-only too.
            Context.reset()
            let note = Context.dragItems([UUID()])[0]
            let entry = item(inside)
            let batch = Context.Service.Item(payload: .batch([note, entry]), title: "batch",
                                            icon: NSImage(), isImage: false)
            let batchService = Context.Service.shared
            batchService.items = [batch]
            batchService.selection = [batch.id]
            let batchTile = Context.Tile(item: batch)
            beginAndWait(batchTile)
            suite.expect(batchTile.draggedIDs == [note.id, entry.id]
                    && batchService.sourceOperationMask(for: .outsideApplication) == .copy,
                   "a mixed batch protects its package content while retaining every leaf")
            batchService.completeInternalDrag(dropAccepted: false)
            // The earlier bookmark scenarios moved plain into and then out of
            // the package. Its current, ordinary path is exported.
            let ordinary = item(exported)
            let web = Context.Service.Item(payload: .link(URL(string: "https://example.com")!),
                                           title: "link", icon: NSImage(), isImage: false)
            batchService.items = [ordinary, note, web]
            batchService.selection = [ordinary.id, note.id, web.id]
            let ordinaryTile = Context.Tile(item: ordinary)
            beginAndWait(ordinaryTile)
            suite.expect(ordinaryTile.draggedIDs == [ordinary.id, note.id, web.id],
                         "a mixed drag preserves all three live items and their order")
            suite.expect(batchService.sourceOperationMask(for: .outsideApplication) == [.copy, .move],
                         "a text or link next to an ordinary file does not remove its move operation")
            batchService.completeInternalDrag(dropAccepted: false)

            let missing = item(root.appendingPathComponent("missing"))
            let offline = item(URL(fileURLWithPath: "/Volumes/VorssaintOffline-\(UUID())/offline"))
            batchService.items = [missing, offline]
            batchService.selection = [missing.id, offline.id]
            let missingTile = Context.Tile(item: missing)
            beginAndWait(missingTile)
            suite.expect(missingTile.draggingItems.isEmpty && batchService.removed.contains(missing.id)
                         && !batchService.removed.contains(offline.id),
                         "an all-missing grab retires only confirmed missing files on mounted volumes")
            let link = item(fileLink)
            batchService.beginInternalDrag(items: [link], from: Context.window(), containsPackageContent: false)
            suite.expect(batchService.sourceOperationMask(for: .outsideApplication) == [.copy, .move],
                   "a subsequent ordinary drag does not retain the previous package protection")
            batchService.protectedIDs = [link.id]
            suite.expect(batchService.sourceOperationMask(for: .outsideApplication) == .copy,
                   "a pinned item remains copy-only")
            batchService.protectedIDs = []
            Context.UserDefaults.standard.removeAfterDrop = false
            suite.expect(batchService.sourceOperationMask(for: .outsideApplication) == .copy,
                   "turning off removal keeps ordinary payloads copy-only")
            batchService.completeInternalDrag(dropAccepted: true)
        } catch {
            suite.expect(false, "shelf drag protection fixture failed: \(error)")
        }
    }
}
