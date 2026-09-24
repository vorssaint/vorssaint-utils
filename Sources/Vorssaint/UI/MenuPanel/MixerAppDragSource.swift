// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Only Command-clicks belong to this overlay. All ordinary input passes to
/// the existing sliders, fields and menus underneath it.
struct MixerAppDragSource: NSViewRepresentable {
    static let pasteboardType = NSPasteboard.PasteboardType("com.vorssaint.mixer-app")
    let id: String?
    let icon: NSImage
    let onBegin: (String) -> Void
    let onEnd: () -> Void
    let canMove: (String, String) -> Bool
    let onTarget: (MixerAppDropTarget?) -> Void
    let move: (String, String, Bool) -> Void
    /// Columns running sideways read the insertion side from the pointer's x.
    var sideways = false

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.source = self
    }

    final class DragView: NSView, NSDraggingSource {
        var source: MixerAppDragSource?
        private var start: NSPoint?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            registerForDraggedTypes([MixerAppDragSource.pasteboardType])
        }

        required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard source?.id != nil, NSEvent.modifierFlags.contains(.command) else { return nil }
            return super.hitTest(point)
        }

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { start = event.locationInWindow }
        override func mouseUp(with event: NSEvent) { start = nil }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let source, let id = source.id,
                  hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
            self.start = nil
            let item = NSPasteboardItem()
            item.setString(id, forType: MixerAppDragSource.pasteboardType)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            let point = convert(start, from: nil)
            draggingItem.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32), contents: source.icon)
            source.onBegin(id)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        // The native overlay receiving the mouse must also receive the drop.
        // A SwiftUI drop target underneath it never gets the destination callbacks.
        private func destination(_ sender: NSDraggingInfo) -> (sourceID: String, target: MixerAppDropTarget)? {
            guard let source, let targetID = source.id,
                  let origin = sender.draggingSource as? DragView,
                  let sourceID = origin.source?.id, sourceID != targetID,
                  sender.draggingSourceOperationMask.contains(.move),
                  sender.draggingPasteboard.string(forType: MixerAppDragSource.pasteboardType) == sourceID,
                  source.canMove(sourceID, targetID) else { return nil }
            let point = convert(sender.draggingLocation, from: nil)
            guard bounds.contains(point) else { return nil }
            let after = source.sideways ? point.x > bounds.midX : point.y > bounds.midY
            return (sourceID, MixerAppDropTarget(id: targetID, after: after))
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let destination = destination(sender)
            source?.onTarget(destination?.target)
            return destination == nil ? [] : .move
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            if let event = NSApp.currentEvent { autoscroll(with: event) }
            return draggingEntered(sender)
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { source?.onTarget(nil) }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            destination(sender) != nil
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let destination = destination(sender) else { return false }
            source?.move(destination.sourceID, destination.target.id, destination.target.after)
            source?.onTarget(nil)
            return true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? .move : []
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            source?.onEnd()
        }
    }
}

struct MixerAppDropTarget: Equatable {
    let id: String
    let after: Bool
}

struct MixerAppReorderModifier: ViewModifier {
    let id: String?
    let icon: NSImage
    @Binding var draggingID: String?
    @Binding var target: MixerAppDropTarget?
    let dragChanged: (Bool) -> Void
    let canMove: (String, String) -> Bool
    let move: (String, String, Bool) -> Void
    var sideways = false

    private var markerEdge: Alignment {
        sideways ? (target?.after == true ? .trailing : .leading) : (target?.after == true ? .bottom : .top)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                MixerAppDragSource(id: id, icon: icon,
                                   onBegin: { draggingID = $0; dragChanged(true) },
                                   onEnd: { draggingID = nil; target = nil; dragChanged(false) },
                                   canMove: canMove,
                                   onTarget: { next in
                                       if next != nil || target?.id == id { target = next }
                                   },
                                   move: move,
                                   sideways: sideways)
            }
            .overlay(alignment: markerEdge) {
                if target?.id == id, draggingID != nil {
                    Capsule().fill(Color.accentColor)
                        .frame(width: sideways ? 2 : nil, height: sideways ? nil : 2)
                        .allowsHitTesting(false)
                }
            }
            .opacity(draggingID == id && draggingID != nil ? 0.45 : 1)
    }
}
