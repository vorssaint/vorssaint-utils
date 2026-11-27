// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Lets the wheel scroll while text is being selected by dragging. AppKit's
/// selection loop asks the window only for mouse-up, drag and periodic events,
/// so a wheel turned mid-drag waited in the queue until the button came up.
/// A window hosting text routes those wheel events as they arrive; the loop's
/// next periodic event then extends the selection into the scrolled text.
enum DragSelectionWheel {
    /// The next event a drag-tracking loop asked for, after dispatching any
    /// wheel events that arrive first. Other requests pass through unchanged.
    static func nextEvent(matching mask: NSEvent.EventTypeMask, dequeue: Bool,
                          next: (NSEvent.EventTypeMask) -> NSEvent?,
                          scroll: (NSEvent) -> Void) -> NSEvent? {
        guard dequeue, mask.contains(.leftMouseDragged), !mask.contains(.scrollWheel) else { return next(mask) }
        while let event = next(mask.union(.scrollWheel)) {
            guard event.type == .scrollWheel else { return event }
            scroll(event)
        }
        return nil
    }
}
