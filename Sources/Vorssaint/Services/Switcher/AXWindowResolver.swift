// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics

/// Resolves an Accessibility window element to its WindowServer id. Exported by
/// ApplicationServices and used by macOS window switchers; there is no public
/// alternative for this mapping.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXWindowResolver {
    static func windowID(for element: AXUIElement) -> CGWindowID? {
        readWindowID(for: element).id
    }

    /// Same lookup as `windowID(for:)`, but reports whether the read hit its
    /// messaging timeout instead of collapsing that into the same `nil` as
    /// "this element genuinely has no window id" — a caller deciding whether
    /// a missing id proves a window does not exist needs to tell those two
    /// apart.
    static func readWindowID(for element: AXUIElement) -> (id: CGWindowID?, timedOut: Bool) {
        var id: CGWindowID = 0
        let error = _AXUIElementGetWindow(element, &id)
        guard error == .success, id != 0 else { return (nil, error == .cannotComplete) }
        return (id, false)
    }
}
