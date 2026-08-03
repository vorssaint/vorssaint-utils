// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A transparent strip that moves the whole panel when dragged. Used over the
/// header and empty shelf space; tiles stay free to start item drags.
struct WindowMoveHandle: NSViewRepresentable {
    var acceptsDrops = false

    func makeNSView(context: Context) -> ShelfPanelMoveView {
        let view = ShelfPanelMoveView()
        view.acceptsDrops = acceptsDrops
        return view
    }

    func updateNSView(_ nsView: ShelfPanelMoveView, context: Context) {
        nsView.acceptsDrops = acceptsDrops
    }
}

class ShelfPanelMoveView: NSView {
    var acceptsDrops = false {
        didSet { syncDraggedTypes() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        syncDraggedTypes()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        ShelfService.shared.beginInteraction()
        defer { ShelfService.shared.endInteraction() }
        window?.performDrag(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender)
        ShelfService.shared.setDropTargeted(operation != [])
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = dropOperation(for: sender)
        ShelfService.shared.setDropTargeted(operation != [])
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        ShelfService.shared.setDropTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = acceptsDrops && ShelfService.shared.accept(pasteboard: sender.draggingPasteboard)
        ShelfService.shared.setDropTargeted(false)
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        ShelfService.shared.setDropTargeted(false)
    }

    private func syncDraggedTypes() {
        unregisterDraggedTypes()
        if acceptsDrops {
            registerForDraggedTypes(ShelfService.tileDropTypes)
        }
    }

    private func dropOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsDrops,
              !ShelfService.shared.isInternalDragActive,
              ShelfService.shared.canAcceptPasteboard(sender.draggingPasteboard) else {
            return []
        }
        return .copy
    }
}

/// The shelf's item tiles, in AppKit so they can do what SwiftUI's `.onDrag`
/// can't: drag several selected items out at once, and remove them from the
/// shelf once the drop is accepted somewhere.
struct ShelfTilesView: NSViewRepresentable {
    var items: [ShelfService.Item]
    var selection: Set<UUID>
    var expandedBatches: Set<UUID>

    static let tileSize = NSSize(width: 78, height: 88)
    static let spacing: CGFloat = 10
    static let inset: CGFloat = 4

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .allowed
        scroll.contentView.drawsBackground = false
        let document = FlippedView()
        document.acceptsDrops = true
        scroll.documentView = document
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let document = scroll.documentView else { return }
        document.subviews.forEach { $0.removeFromSuperview() }

        let tile = Self.tileSize
        let inset = Self.inset
        let contentWidth = max(scroll.contentSize.width, 276)
        let columnStride = tile.width + Self.spacing
        let rowStride = tile.height + Self.spacing
        let columns = max(1, Int((contentWidth - inset * 2 + Self.spacing) / columnStride))
        let rows = max(1, Int(ceil(Double(items.count) / Double(columns))))

        for (index, item) in items.enumerated() {
            let column = index % columns
            let row = index / columns
            let view = ShelfTileView(item: item,
                                     isSelected: selection.contains(item.id),
                                     isExpanded: expandedBatches.contains(item.id))
            view.frame = NSRect(x: inset + CGFloat(column) * columnStride,
                                y: inset + CGFloat(row) * rowStride,
                                width: tile.width,
                                height: tile.height)
            document.addSubview(view)
        }
        let contentHeight = inset * 2 + CGFloat(rows) * tile.height + CGFloat(max(0, rows - 1)) * Self.spacing
        scroll.hasVerticalScroller = contentHeight > scroll.contentSize.height + 1
        document.frame = NSRect(x: 0,
                                y: 0,
                                width: contentWidth,
                                height: max(contentHeight, scroll.contentSize.height))
    }

    private final class FlippedView: ShelfPanelMoveView {
        override var isFlipped: Bool { true }
    }
}

/// One tile. Click toggles selection; dragging starts a drag of the whole
/// selection (or just this tile if it isn't selected); a successful drop
/// removes the dragged tiles from the shelf.
final class ShelfTileView: NSView, NSDraggingSource {
    private let item: ShelfService.Item
    private let isSelected: Bool
    private let isExpanded: Bool
    private var mouseDownPoint: NSPoint = .zero
    private var didDrag = false
    private var draggedIDs: [UUID] = []
    private var isDropTargeted = false
    private var closeButton: NSButton!
    private var expandButton: NSButton?

    init(item: ShelfService.Item, isSelected: Bool, isExpanded: Bool) {
        self.item = item
        self.isSelected = isSelected
        self.isExpanded = isExpanded
        super.init(frame: NSRect(origin: .zero, size: ShelfTilesView.tileSize))
        wantsLayer = true
        layer?.cornerRadius = 10
        syncChrome()
        registerForDraggedTypes(ShelfService.tileDropTypes)
        buildSubviews()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func syncChrome() {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
            : nil
        if isSelected || isDropTargeted {
            layer?.borderWidth = 2
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else {
            layer?.borderWidth = 0
            layer?.borderColor = nil
        }
    }

    private func setDropTargeted(_ targeted: Bool) {
        guard isDropTargeted != targeted else { return }
        isDropTargeted = targeted
        syncChrome()
    }

    private func buildSubviews() {
        if item.isBatch { addStackBackplates() }

        let iconWell = NSView(frame: NSRect(x: 7, y: 6, width: 64, height: 50))
        iconWell.wantsLayer = true
        iconWell.layer?.cornerRadius = 8
        iconWell.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        addSubview(iconWell)

        let imageView = NSImageView(frame: iconWell.bounds.insetBy(dx: item.isImage ? 4 : 13,
                                                                   dy: item.isImage ? 4 : 8))
        imageView.image = item.icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        iconWell.addSubview(imageView)

        if item.isBatch {
            let badge = NSTextField(labelWithString: "\(item.leafCount)")
            badge.frame = NSRect(x: 50, y: 39, width: 22, height: 15)
            badge.font = .systemFont(ofSize: 9, weight: .bold)
            badge.alignment = .center
            badge.textColor = .white
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 7.5
            badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            addSubview(badge)

            let expand = NSButton(frame: NSRect(x: 4, y: 4, width: 17, height: 17))
            expand.image = NSImage(systemSymbolName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill",
                                   accessibilityDescription: nil)
            expand.isBordered = false
            expand.bezelStyle = .regularSquare
            expand.imagePosition = .imageOnly
            expand.contentTintColor = .secondaryLabelColor
            expand.target = self
            expand.action = #selector(toggleBatchExpansion)
            expandButton = expand
            addSubview(expand)
        }

        let label = NSTextField(labelWithString: item.title)
        label.frame = NSRect(x: 3, y: 59, width: 72, height: 24)
        label.font = .systemFont(ofSize: 10)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.textColor = .secondaryLabelColor
        addSubview(label)

        if isSelected {
            let badgeY: CGFloat = item.isBatch ? 22 : 4
            let badge = NSImageView(frame: NSRect(x: 4, y: badgeY, width: 16, height: 16))
            badge.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            badge.contentTintColor = .controlAccentColor
            addSubview(badge)
        }

        closeButton = NSButton(frame: NSRect(x: 58, y: 4, width: 17, height: 17))
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(removeSelf)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    private func addStackBackplates() {
        for (index, offset) in [2, 1].enumerated() {
            let view = NSView(frame: NSRect(x: 7 + CGFloat(offset) * 3,
                                           y: 6 + CGFloat(offset) * 3,
                                           width: 64,
                                           height: 50))
            view.wantsLayer = true
            view.layer?.cornerRadius = 8
            view.layer?.backgroundColor = NSColor.white.withAlphaComponent(index == 0 ? 0.035 : 0.055).cgColor
            view.layer?.borderWidth = 1
            view.layer?.borderColor = NSColor.white.withAlphaComponent(0.05).cgColor
            addSubview(view)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        ShelfService.shared.noteInteraction()
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        guard !urls.isEmpty else { return nil }

        let strings = L10n.shared.s
        let menu = NSMenu()
        let open = NSMenuItem(title: strings.shelfActionOpen,
                              action: #selector(openFiles),
                              keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let openWith = NSMenuItem(title: strings.shelfActionOpenWith,
                                  action: nil,
                                  keyEquivalent: "")
        let applications = commonApplications(for: urls)
        if applications.isEmpty {
            openWith.isEnabled = false
        } else {
            let submenu = NSMenu(title: strings.shelfActionOpenWith)
            for applicationURL in applications.prefix(40) {
                let entry = NSMenuItem(title: FileManager.default.displayName(atPath: applicationURL.path),
                                       action: #selector(openFilesWithApplication(_:)),
                                       keyEquivalent: "")
                entry.target = self
                entry.representedObject = applicationURL
                let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
                submenu.addItem(entry)
            }
            openWith.submenu = submenu
        }
        menu.addItem(openWith)

        let airDrop = NSMenuItem(title: strings.shelfActionAirDrop,
                                 action: #selector(shareWithAirDrop),
                                 keyEquivalent: "")
        airDrop.target = self
        airDrop.isEnabled = NSSharingService(named: .sendViaAirDrop) != nil
        menu.addItem(airDrop)
        menu.addItem(.separator())

        let reveal = NSMenuItem(title: strings.cleanerRevealInFinder,
                                action: #selector(revealFiles),
                                keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        ShelfService.shared.noteInteraction()
        mouseDownPoint = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        let point = event.locationInWindow
        if hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 4 {
            didDrag = true
            beginItemDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        if item.isBatch, event.clickCount >= 2 {
            ShelfService.shared.toggleBatchExpansion(item.id)
        } else {
            ShelfService.shared.toggleSelection(item.id)
        }
    }

    @objc private func removeSelf() {
        ShelfService.shared.removeItem(item.id)
    }

    @objc private func toggleBatchExpansion() {
        ShelfService.shared.toggleBatchExpansion(item.id)
    }

    @objc private func openFiles() {
        for url in ShelfService.shared.fileURLsForActions(startingAt: item) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openFilesWithApplication(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL else { return }
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        guard !urls.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls,
                                withApplicationAt: applicationURL,
                                configuration: configuration)
    }

    @objc private func shareWithAirDrop() {
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else { return }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    @objc private func revealFiles() {
        let urls = ShelfService.shared.fileURLsForActions(startingAt: item)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func commonApplications(for urls: [URL]) -> [URL] {
        guard let first = urls.first else { return [] }
        var common = Set(NSWorkspace.shared.urlsForApplications(toOpen: first))
        for url in urls.dropFirst() {
            common.formIntersection(NSWorkspace.shared.urlsForApplications(toOpen: url))
        }
        return common.filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted {
                FileManager.default.displayName(atPath: $0.path)
                    .localizedCaseInsensitiveCompare(
                        FileManager.default.displayName(atPath: $1.path)) == .orderedAscending
            }
    }

    private func beginItemDrag(with event: NSEvent) {
        let shelf = ShelfService.shared
        let candidates = shelf.selection.contains(item.id) ? shelf.selectedItems() : [item]
        let dragged = shelf.dragItems(for: candidates)
        guard !dragged.isEmpty else { return }
        // A payload whose file vanished since it was shelved can never be
        // dropped: every destination refuses the dead URL and the whole
        // drag reads as broken. Only living payloads join the session; an
        // all-dead grab explains itself instead of offering a ghost drag.
        let living = shelf.livingDragItems(in: dragged)
        guard !living.isEmpty else {
            shelf.handleDeadDrag(dragged)
            return
        }
        draggedIDs = living.map(\.id)

        let draggingItems: [NSDraggingItem] = living.map { entry in
            let draggingItem = NSDraggingItem(pasteboardWriter: shelf.pasteboardWriter(for: entry))
            // Overlapping frames make AppKit stack them with a count badge.
            draggingItem.setDraggingFrame(bounds, contents: entry.icon)
            return draggingItem
        }
        shelf.beginInternalDrag(ids: draggedIDs)
        shelf.beginInteraction()
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        ShelfService.shared.sourceOperationMask(for: context)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // A non-empty operation means the drop was accepted somewhere — pull the
        // dragged tiles out of the shelf. A cancelled drag leaves them.
        DispatchQueue.main.async {
            ShelfService.shared.completeInternalDrag(dropAccepted: operation != [])
        }
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = mergeOperation(for: sender)
        setDropTargeted(operation != [])
        if operation != [] { ShelfService.shared.noteInteraction() }
        return operation
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let operation = mergeOperation(for: sender)
        setDropTargeted(operation != [])
        return operation
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        ShelfService.shared.canMergePasteboard(sender.draggingPasteboard, into: item.id)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let merged = ShelfService.shared.mergePasteboard(sender.draggingPasteboard, into: item.id)
        setDropTargeted(false)
        return merged
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setDropTargeted(false)
    }

    private func mergeOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        guard ShelfService.shared.canMergePasteboard(sender.draggingPasteboard, into: item.id) else {
            return []
        }
        return ShelfService.shared.isInternalDragActive ? .move : .copy
    }
}
