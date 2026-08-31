// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Lets a clipboard row be dragged out as real files. In AppKit because
/// SwiftUI's `.onDrag` hands over one item provider and never says where the
/// pointer is, and both matter here: a copy of several files drags as several
/// files, and the Shelf's shake-to-open needs the pointer's path, which the
/// Shelf's global monitor never sees for a drag that starts in this app.
///
/// A press that never turns into a drag is handed back as a click, so the row
/// under it keeps its paste-on-click; a right click is passed up untouched so
/// the row's context menu still opens.
struct ClipboardFileDragSource: NSViewRepresentable {
    let items: [ClipboardHistoryService.DragItem]
    let onClick: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> ClipboardFileDragView {
        let view = ClipboardFileDragView()
        view.items = items
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: ClipboardFileDragView, context: Context) {
        view.items = items
        view.onClick = onClick
    }
}

final class ClipboardFileDragView: NSView, NSDraggingSource {
    var items: [ClipboardHistoryService.DragItem] = []
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    private var pressLocation: NSPoint?
    private static let dragThreshold: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressLocation, !items.isEmpty else { return }
        let location = event.locationInWindow
        guard hypot(location.x - pressLocation.x, location.y - pressLocation.y) > Self.dragThreshold
        else { return }
        self.pressLocation = nil
        beginDraggingSession(with: draggingItems(around: convert(location, from: nil)),
                             event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard pressLocation != nil else { return }
        pressLocation = nil
        onClick?(event.modifierFlags.intersection([.command, .shift, .option, .control]))
    }

    override func rightMouseDown(with event: NSEvent) {
        nextResponder?.rightMouseDown(with: event)
    }

    /// Finder-style: each file drags under its own icon, fanned so a copy of
    /// many files reads as many files from the first moment. Centred on the
    /// pointer, not the row, or the icon slides in from wherever the row's
    /// middle happens to be.
    private func draggingItems(around point: NSPoint) -> [NSDraggingItem] {
        let iconSize = NSSize(width: 48, height: 48)
        return items.enumerated().map { index, entry in
            let item = NSDraggingItem(pasteboardWriter: entry.writer)
            let icon = entry.icon.copy() as? NSImage ?? entry.icon
            icon.size = iconSize
            let offset = CGFloat(min(index, 3)) * 6
            item.setDraggingFrame(NSRect(x: point.x - iconSize.width / 2 + offset,
                                         y: point.y - iconSize.height / 2 - offset,
                                         width: iconSize.width,
                                         height: iconSize.height),
                                  contents: icon)
            return item
        }
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        ShelfService.shared.noteInternalContentDrag(at: ProcessInfo.processInfo.systemUptime)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        ShelfService.shared.endInternalContentDrag()
    }
}
