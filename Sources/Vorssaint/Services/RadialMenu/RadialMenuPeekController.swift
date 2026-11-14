// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The panel a slice opens beside the wheel while the pointer rests on it.
/// It never takes the keyboard: the wheel keeps it, and the radial menu
/// service tells this panel which row the pointer or the arrows are on.
/// What it lists is read once on opening, so a copy arriving meanwhile never
/// moves the row under the pointer.
final class RadialMenuPeekController: ObservableObject {
    @Published private(set) var peek: RadialMenuPeek?
    @Published private(set) var entries: [ClipboardHistoryEntry] = []
    /// The folder list's place and picks, nil for any other peek.
    @Published private(set) var folder: RadialFolderBrowser?
    @Published private(set) var folderEntries: [RadialFolderEntry] = []
    /// The folder could not be listed, most often because macOS has not
    /// been allowed to let the app read it.
    @Published private(set) var folderUnreadable = false
    @Published private(set) var highlightedRow: Int?
    /// The entry at the top of the visible rows; the list scrolls by rows.
    @Published private(set) var firstVisibleRow = 0
    @Published private(set) var color = RadialMenuColor.accent
    /// The wheel slice the open peek belongs to.
    private(set) var sliceIndex: Int?
    private var panel: NSPanel?
    /// Scrolling not yet worth a whole row, in rows.
    private var scrollRemainder: CGFloat = 0
    /// Moves on with every opening, closing and folder change, so a folder
    /// read that finishes after the person moved on lands nowhere.
    private var generation = 0
    /// Folders are read off the main thread, one at a time: a dead network
    /// mount stalls only this lane, never the wheel.
    private static let folderQueue = DispatchQueue(label: "com.vorssaint.utils.radial-folder",
                                                   qos: .userInitiated)

    /// A press on the folder list that is not yet a click or a drag.
    private var press: (point: CGPoint, target: FolderTarget)?
    /// The file the last single click picked, so the second click of a
    /// double-click opens that file and never one a folder change put there.
    private var lastClickedURL: URL?
    private let dragSource = RadialFolderDragSource()
    private(set) var isDragging = false

    /// Set by the radial menu service, which owns the wheel's session.
    var onOpenFile: ((URL) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: ((_ dropped: Bool) -> Void)?

    enum FolderTarget: Equatable {
        case row(RadialFolderEntry), back, basket, clearBasket, none
    }

    var isOpen: Bool { peek != nil }
    var isFolder: Bool { folder != nil }
    var hasPendingPress: Bool { press != nil }

    private var rowCount: Int { isFolder ? folderEntries.count : entries.count }

    /// The open panel, which the wheel's click monitor must not read as an
    /// outside click.
    var window: NSWindow? { isOpen ? panel : nil }

    var highlightedEntry: ClipboardHistoryEntry? {
        guard !isFolder, let highlightedRow, entries.indices.contains(highlightedRow) else { return nil }
        return entries[highlightedRow]
    }

    var highlightedFolderEntry: RadialFolderEntry? {
        guard isFolder, let highlightedRow, folderEntries.indices.contains(highlightedRow) else { return nil }
        return folderEntries[highlightedRow]
    }

    func contains(_ point: CGPoint) -> Bool {
        guard isOpen, let panel else { return false }
        return panel.frame.contains(point)
    }

    /// Shows what the peek has, beside the wheel in the slice's direction.
    /// The clipboard is shown at once; a folder once it has been read.
    /// Nothing comes on screen when there is nothing to list.
    func open(_ peek: RadialMenuPeek, slice: Int, color: RadialMenuColor,
              wheelCenter: CGPoint, direction: (dx: CGFloat, dyUp: CGFloat)) {
        close()
        switch peek {
        case .clipboardHistory:
            let entries = Self.clipboardEntries()
            guard !entries.isEmpty else { return }
            self.entries = entries
            show(peek, slice: slice, color: color, wheelCenter: wheelCenter, direction: direction)
        case let .folder(path):
            let root = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            // Already resolved, and cached, for the slice's own label.
            let name = RadialMenuIconStore.fileName(for: path)
            let generation = self.generation
            Self.folderQueue.async {
                let result = RadialFolderListing.read(root, limit: RadialMenuPeekLayout.maxFolderEntries)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == generation, result != .notAFolder else { return }
                    self.folder = RadialFolderBrowser(root: root, name: name)
                    self.apply(result)
                    self.show(peek, slice: slice, color: color, wheelCenter: wheelCenter, direction: direction)
                }
            }
        }
    }

    private func show(_ peek: RadialMenuPeek, slice: Int, color: RadialMenuColor,
                      wheelCenter: CGPoint, direction: (dx: CGFloat, dyUp: CGFloat)) {
        self.peek = peek
        self.color = color
        sliceIndex = slice
        highlightedRow = nil
        firstVisibleRow = 0
        scrollRemainder = 0

        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(wheelCenter) })?.visibleFrame
            ?? NSScreen.pointerVisibleFrame
        let frame = isFolder
            ? RadialMenuPeekLayout.frame(wheelCenter: wheelCenter, direction: direction,
                                         rowCount: RadialMenuPeekLayout.visibleRows, basket: true,
                                         visibleFrame: visibleFrame)
            : RadialMenuPeekLayout.frame(wheelCenter: wheelCenter, direction: direction,
                                         rowCount: entries.count, visibleFrame: visibleFrame)
        let panel = ensurePanel()
        panel.setFrame(frame, display: false)
        // The panel last drew the list it was closed with, emptied. Drawn
        // now, before it is ordered in, it never shows a frame of that.
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animates ? 0 : 1
        panel.orderFrontRegardless()
        if animates {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        generation &+= 1
        press = nil
        lastClickedURL = nil
        guard isOpen else { return }
        panel?.orderOut(nil)
        peek = nil
        entries = []
        folder = nil
        folderEntries = []
        folderUnreadable = false
        highlightedRow = nil
        firstVisibleRow = 0
        sliceIndex = nil
    }

    /// Closes and frees the panel, for when the radial menu is switched off.
    func releasePanel() {
        close()
        panel = nil
    }

    /// The pointer picks the row under it; anywhere else it picks none, so
    /// a release on the way out of the panel never pastes.
    func trackPointer(_ point: CGPoint) {
        guard isOpen, let panel else { return }
        let row = RadialMenuPeekLayout.row(at: point, in: panel.frame, rowCount: rowCount,
                                           firstVisibleRow: firstVisibleRow)
        if row != highlightedRow { highlightedRow = row }
    }

    func moveHighlight(by delta: Int) {
        guard isOpen else { return }
        highlightedRow = RadialMenuPeekLayout.movedRow(highlightedRow, by: delta, rowCount: rowCount)
        reveal(highlightedRow)
    }

    /// Picks an entry by its number in the list. False when there is none.
    func highlight(row: Int) -> Bool {
        guard isOpen, (0..<rowCount).contains(row) else { return false }
        highlightedRow = row
        reveal(row)
        return true
    }

    /// A trackpad scrolls by points and a mouse wheel by lines; either one
    /// moves the list by whole rows, and the row now under the pointer is
    /// the one it picks.
    func scroll(deltaY: CGFloat, precise: Bool, pointer: CGPoint) {
        guard isOpen, rowCount > RadialMenuPeekLayout.visibleRows else { return }
        scrollRemainder += precise ? deltaY / RadialMenuPeekLayout.rowHeight : deltaY
        let rows = Int(scrollRemainder)
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows)
        // A positive delta brings earlier entries down into view.
        let first = RadialMenuPeekLayout.scrolledFirstRow(firstVisibleRow, by: -rows, rowCount: rowCount)
        if first == firstVisibleRow {
            // Held at an end, the leftover would delay the first row back.
            scrollRemainder = 0
            return
        }
        firstVisibleRow = first
        trackPointer(pointer)
    }

    private func reveal(_ row: Int?) {
        guard let row else { return }
        let first = RadialMenuPeekLayout.firstRow(revealing: row, from: firstVisibleRow, rowCount: rowCount)
        if first != firstVisibleRow { firstVisibleRow = first }
    }

    /// The clipboard is listed only while its history is on: a history the
    /// user switched off is not shown, even though its file still exists.
    private static func clipboardEntries() -> [ClipboardHistoryEntry] {
        guard AppFeature.clipboardHistory.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled) else { return [] }
        return Array(ClipboardHistoryService.shared.entries.prefix(RadialMenuPeekLayout.maxEntries))
    }

    // MARK: - Folder list

    /// Goes into a folder in the list. The rows change once it has been read,
    /// and a folder that cannot be read says so instead of listing nothing.
    func enter(_ entry: RadialFolderEntry) {
        guard entry.isFolder, var target = folder else { return }
        target.enter(entry)
        load(target.trail)
    }

    /// Up one folder. False at the folder on the wheel, which has no parent
    /// in this list.
    @discardableResult
    func goUp() -> Bool {
        guard var target = folder, target.canGoUp else { return false }
        target.goUp()
        load(target.trail)
        return true
    }

    /// Only the place travels with the read: picks made while it runs are
    /// kept, whatever folder they were made in.
    private func load(_ trail: [RadialFolderBrowser.Step]) {
        guard let root = folder?.root else { return }
        generation &+= 1
        let generation = self.generation
        let url = (trail.last ?? root).url
        lastClickedURL = nil
        Self.folderQueue.async {
            let result = RadialFolderListing.read(url, limit: RadialMenuPeekLayout.maxFolderEntries)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.isFolder else { return }
                self.folder?.trail = trail
                self.apply(result)
                self.highlightedRow = nil
                self.firstVisibleRow = 0
                self.scrollRemainder = 0
                self.trackPointer(NSEvent.mouseLocation)
            }
        }
    }

    private func apply(_ result: RadialFolderListing.Result) {
        if case let .entries(list) = result {
            folderEntries = list
            folderUnreadable = false
        } else {
            // A folder that vanished since it was listed reads like one
            // that may not be read: there is nothing to show from it.
            folderEntries = []
            folderUnreadable = true
        }
    }

    /// Return, → or a digit on a row: a folder is gone into, a file opened.
    func activateHighlighted() -> Bool {
        guard let entry = highlightedFolderEntry else { return false }
        if entry.isFolder {
            enter(entry)
        } else {
            onOpenFile?(entry.url)
        }
        return true
    }

    /// → goes into the highlighted folder; on a file it does nothing here.
    func enterHighlightedFolder() -> Bool {
        guard let entry = highlightedFolderEntry, entry.isFolder else { return false }
        enter(entry)
        return true
    }

    /// Space picks or unpicks the highlighted file.
    func togglePickHighlighted() -> Bool {
        guard let entry = highlightedFolderEntry, !entry.isFolder else { return false }
        folder?.toggle(entry.url)
        return true
    }

    /// ⌘C: the picked files, or the highlighted row when none is picked, go
    /// on the clipboard as files, ready to paste into Finder, Mail or a chat.
    /// Written on the shared pasteboard lane like every other write.
    func copyFiles() -> Bool {
        guard let folder else { return false }
        let urls = folder.copied(highlighted: highlightedFolderEntry?.url)
        guard !urls.isEmpty else { return false }
        GeneralPasteboardAccess.shared.async {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        }
        return true
    }

    func folderTarget(at point: CGPoint) -> FolderTarget {
        guard isFolder, let panel, let folder else { return .none }
        let frame = panel.frame
        if folder.canGoUp, RadialMenuPeekLayout.backButtonFrame(in: frame).contains(point) { return .back }
        if !folder.basket.isEmpty, RadialMenuPeekLayout.clearButtonFrame(in: frame).contains(point) {
            return .clearBasket
        }
        if RadialMenuPeekLayout.basketFrame(in: frame).contains(point) { return .basket }
        if let row = RadialMenuPeekLayout.row(at: point, in: frame, rowCount: folderEntries.count,
                                              firstVisibleRow: firstVisibleRow) {
            return .row(folderEntries[row])
        }
        return .none
    }

    /// Nothing happens on the way down: whether this is a click or a drag is
    /// only known once the pointer moves or the button comes back up.
    func folderMouseDown(at point: CGPoint) {
        guard !isDragging else { return }
        press = (point, folderTarget(at: point))
    }

    /// True once the press has become a drag, which this event starts.
    func folderMouseDragged(_ event: NSEvent, at point: CGPoint) -> Bool {
        guard let press, !isDragging else { return isDragging }
        guard hypot(point.x - press.point.x, point.y - press.point.y) > RadialMenuPeekLayout.dragThreshold else {
            return false
        }
        self.press = nil
        let urls: [URL]
        switch press.target {
        case let .row(entry): urls = folder?.dragged(grabbing: entry.url) ?? []
        case .basket: urls = folder?.basket ?? []
        case .back, .clearBasket, .none: urls = []
        }
        return beginDrag(urls, event: event)
    }

    /// A click is a press released where it began. A file is picked or
    /// unpicked, a double-click opens it, and a folder is gone into.
    func folderMouseUp(_ event: NSEvent, at point: CGPoint) {
        guard let press else { return }
        self.press = nil
        guard folderTarget(at: point) == press.target else { return }
        switch press.target {
        case .back:
            goUp()
        case .clearBasket:
            folder?.clearBasket()
        case let .row(entry) where entry.isFolder:
            // A double-click on a folder must not land its second click on
            // whatever row the new folder puts under the pointer.
            lastClickedURL = entry.url
            enter(entry)
        case let .row(entry):
            if event.clickCount >= 2 {
                guard lastClickedURL == entry.url else { return }
                // The first click of the pair picked it; opening leaves the
                // basket as it was before the double-click.
                folder?.toggle(entry.url)
                lastClickedURL = nil
                onOpenFile?(entry.url)
            } else {
                folder?.toggle(entry.url)
                lastClickedURL = entry.url
            }
        case .basket, .none:
            break
        }
    }

    /// Hands the files to macOS, which draws the drag and delivers them where
    /// they are dropped. Only a copy is ever offered, so dropping into Finder
    /// can never move the original away, and the Trash refuses it.
    private func beginDrag(_ urls: [URL], event: NSEvent) -> Bool {
        guard !urls.isEmpty, let view = panel?.contentView else { return false }
        let location = view.convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32)
        let items = urls.map { url -> NSDraggingItem in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            // Overlapping frames make AppKit stack them with a count badge.
            item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        isDragging = true
        dragSource.ended = { [weak self] dropped in
            guard let self else { return }
            self.isDragging = false
            self.onDragEnded?(dropped)
        }
        onDragStarted?()
        view.beginDraggingSession(with: items, event: event, source: dragSource)
        return true
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        panel.title = "Vorssaint"
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingController(rootView: RadialMenuPeekView(controller: self))
        // The frame comes from the shared layout, which the view draws to;
        // the host must not resize the panel to its own idea of the content.
        host.sizingOptions = []
        panel.contentViewController = host
        self.panel = panel
        return panel
    }
}

/// The folder list's side of a drag. It offers a copy and nothing else.
private final class RadialFolderDragSource: NSObject, NSDraggingSource {
    var ended: ((Bool) -> Void)?

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        let dropped = operation != []
        DispatchQueue.main.async { [weak self] in self?.ended?(dropped) }
    }
}
