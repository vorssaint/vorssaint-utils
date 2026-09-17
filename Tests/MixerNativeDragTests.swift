// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Calls the actual native destination callbacks using a private pasteboard.
/// No mouse events, application windows or real user preferences are involved.
enum MixerNativeDragTests {
    static func run(_ suite: TestSuite) {
        let origin = MixerAppDragSource.DragView(frame: NSRect(x: 0, y: 0, width: 300, height: 48))
        let destination = MixerAppDragSource.DragView(frame: origin.frame)
        let ids = ["app.a", "app.b", "app.c"]
        var arrangement = MixerAppArrangement()
        var marker: MixerAppDropTarget?
        var available = true
        let icon = NSImage(size: NSSize(width: 32, height: 32))
        origin.source = MixerAppDragSource(id: "app.a", icon: icon, onBegin: { _ in }, onEnd: {},
                                          canMove: { _, _ in true }, onTarget: { _ in }, move: { _, _, _ in })
        destination.source = MixerAppDragSource(id: "app.c", icon: icon, onBegin: { _ in }, onEnd: {},
                                               canMove: { _, _ in available }, onTarget: { marker = $0 },
                                               move: { source, target, after in
            arrangement.move(source, to: target, after: after,
                             visibleIDs: arrangement.ordered(ids, identity: { $0 }))
        })
        let info = DragInfo(origin: origin)
        defer { info.draggingPasteboard.releaseGlobally() }
        info.draggingPasteboard.setString("app.a", forType: MixerAppDragSource.pasteboardType)
        info.draggingLocation = destination.convert(NSPoint(x: 20, y: 40), to: nil)
        suite.expect(destination.registeredDraggedTypes.contains(MixerAppDragSource.pasteboardType),
                     "the native mouse receiver is also registered to receive mixer drops")
        suite.expect(destination.draggingEntered(info) == .move && marker == MixerAppDropTarget(id: "app.c", after: true),
                     "entering the lower half of a row accepts the native drag and marks insertion below")
        suite.expect(arrangement.order.isEmpty, "hovering a destination does not persist an unfinished drag")
        suite.expect(destination.prepareForDragOperation(info) && destination.performDragOperation(info),
                     "native prepare and drop callbacks accept the app")
        suite.expect(arrangement.ordered(ids, identity: { $0 }) == ["app.b", "app.c", "app.a"] && marker == nil,
                     "dropping through the real native view changes the saved order and clears the marker")
        info.draggingLocation = destination.convert(NSPoint(x: 20, y: 5), to: nil)
        suite.expect(destination.draggingEntered(info) == .move && marker?.after == false,
                     "the top half of the native row offers insertion above")
        let beforeCancel = arrangement
        destination.draggingExited(info)
        suite.expect(marker == nil && arrangement == beforeCancel, "leaving without a drop cancels the preview without saving")
        available = false
        suite.expect(!destination.prepareForDragOperation(info) && !destination.performDragOperation(info)
                     && arrangement == beforeCancel, "a disappearing or disallowed target cannot reorder apps")
        available = true
        info.draggingSource = nil
        suite.expect(destination.draggingEntered(info).isEmpty && !destination.performDragOperation(info),
                     "an external drag cannot impersonate a mixer app")
        info.draggingSource = origin
        info.draggingPasteboard.setString("app.other", forType: MixerAppDragSource.pasteboardType)
        suite.expect(!destination.performDragOperation(info), "the payload must match the actual native source")
    }

    private final class DragInfo: NSObject, NSDraggingInfo {
        var draggingDestinationWindow: NSWindow? { nil }
        var draggingSourceOperationMask: NSDragOperation { .move }
        var draggingLocation = NSPoint.zero
        var draggedImageLocation: NSPoint { .zero }
        var draggedImage: NSImage? { nil }
        let draggingPasteboard = NSPasteboard.withUniqueName()
        var draggingSource: Any?
        var draggingSequenceNumber: Int { 1 }
        var draggingFormation: NSDraggingFormation = .none
        var animatesToDestination = false
        var numberOfValidItemsForDrop = 1
        var springLoadingHighlight: NSSpringLoadingHighlight { .none }
        func resetSpringLoading() {}

        init(origin: Any) { draggingSource = origin }
        func slideDraggedImage(to screenPoint: NSPoint) {}
        override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
        func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions,
                                    for view: NSView?, classes classArray: [AnyClass],
                                    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                    using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    }
}
