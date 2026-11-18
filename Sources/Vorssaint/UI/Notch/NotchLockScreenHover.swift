// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Where the pointer is over a view, top-left origin, or nil once it
/// leaves. The lock screen's panels are never key, so the tracking area is
/// active always; it takes no clicks itself.
struct NotchLockScreenHover: NSViewRepresentable {
    let onMove: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove
    }

    final class TrackingView: NSView {
        var onMove: ((CGPoint?) -> Void)?
        private var area: NSTrackingArea?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            self.area = area
        }

        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { onMove?(nil) }

        private func report(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            onMove?(bounds.contains(point) ? point : nil)
        }
    }
}
