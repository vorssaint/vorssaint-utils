// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A native source keeps all of an entry's pasteboard representations together,
/// including one dragging item per file. Its click waits for mouse-up so a drag
/// never also copies or pastes the entry.
private struct ClipboardHistoryDragSource: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let entry: ClipboardHistoryEntry
    let activate: () -> Void
    let draggingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.source = self
    }

    static func dismantleNSView(_ view: DragView, coordinator: ()) {
        view.source = nil
        view.pressedSource = nil
    }

    final class DragView: NSView, NSDraggingSource {
        var source: ClipboardHistoryDragSource?
        var pressedSource: ClipboardHistoryDragSource?
        private var start: NSPoint?
        private var activeChanged: ((Bool) -> Void)?
        // AppKit does not keep the source view alive when its SwiftUI row goes
        // away. Keep it and the original completion until the session ends.
        private var activeSource: DragView?

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard source?.isEnabled == true, let event = NSApp.currentEvent,
                  [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type),
                  !event.modifierFlags.contains(.control) else { return nil }
            // Right-clicks and hover remain with the SwiftUI content underneath.
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            start = event.locationInWindow
            pressedSource = source
        }

        override func mouseUp(with event: NSEvent) {
            let pressedSource = pressedSource
            let wasPressed = start != nil
            self.pressedSource = nil
            start = nil
            guard source?.isEnabled == true, wasPressed,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
            pressedSource?.activate()
        }

        override func mouseDragged(with event: NSEvent) {
            guard source?.isEnabled == true, let start, let pressedSource,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
            self.start = nil
            self.pressedSource = nil
            let writers = ClipboardHistoryDrag.writers(for: pressedSource.entry,
                                                       imageDirectory: ClipboardImageStore.directory)
            guard !writers.isEmpty else { return }

            let point = convert(start, from: nil)
            let items = writers.enumerated().map { index, writer in
                let item = NSDraggingItem(pasteboardWriter: writer)
                let image = Self.dragImage(for: pressedSource.entry, writer: writer)
                let offset = CGFloat(min(index, 5)) * 5
                item.setDraggingFrame(NSRect(x: point.x - 20 + offset,
                                             y: point.y - 20 + offset,
                                             width: image.size.width,
                                             height: image.size.height),
                                      contents: image)
                return item
            }
            activeChanged = pressedSource.draggingChanged
            activeSource = self
            activeChanged?(true)
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .stack
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            let changed = activeChanged
            activeChanged = nil
            changed?(false)
            activeSource = nil
        }

        private static func dragImage(for entry: ClipboardHistoryEntry, writer: NSPasteboardWriting) -> NSImage {
            if entry.kind == .image, let name = entry.imageFile,
               let thumbnail = ClipboardImageStore.thumbnail(named: name),
               thumbnail.size.width > 0, thumbnail.size.height > 0 {
                let scale = min(1, 220 / thumbnail.size.width, 160 / thumbnail.size.height)
                let size = NSSize(width: thumbnail.size.width * scale,
                                  height: thumbnail.size.height * scale)
                return NSImage(size: size, flipped: false) { rect in
                    thumbnail.draw(in: rect)
                    return true
                }
            }

            let filePath = entry.kind == .files ? (writer as? NSURL)?.path : nil
            let label = filePath.map { ($0 as NSString).lastPathComponent } ?? entry.preview
            let icon = filePath.map { NSWorkspace.shared.icon(forFile: $0) }
                ?? NSImage(systemSymbolName: entry.kind == .image ? "photo" : "doc.text", accessibilityDescription: nil)
            return NSImage(size: NSSize(width: 240, height: 56), flipped: false) { rect in
                NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
                NSColor.separatorColor.setStroke()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9).stroke()
                icon?.draw(in: NSRect(x: 12, y: 16, width: 24, height: 24))
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                (label as NSString).draw(in: NSRect(x: 46, y: 11, width: 182, height: 34),
                                        withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                                                         .foregroundColor: NSColor.labelColor,
                                                         .paragraphStyle: paragraph])
                return true
            }
        }
    }
}

extension View {
    func clipboardHistoryDragSource(_ entry: ClipboardHistoryEntry,
                                    activate: @escaping () -> Void,
                                    draggingChanged: @escaping (Bool) -> Void = { _ in }) -> some View {
        overlay {
            ClipboardHistoryDragSource(entry: entry, activate: activate, draggingChanged: draggingChanged)
        }
    }
}
