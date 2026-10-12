// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import AppKit

/// A scoped local monitor reads two-finger scrolling without stealing clicks
/// from SwiftUI controls, dragging, or scrolling elsewhere on the panel.
struct PreviewSwipeReader: NSViewRepresentable {
    let enabled: Bool
    let orientation: DockPreviewOrientation
    let action: (WindowEnhancementAction) -> Void
    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) {
        if view.enabled != enabled || view.orientation != orientation { view.resetGesture() }
        view.enabled = enabled; view.orientation = orientation; view.action = action
    }
    static func dismantleNSView(_ view: Reader, coordinator: ()) { view.stop() }
    final class Reader: NSView {
        var enabled = false
        var orientation: DockPreviewOrientation = .bottom
        var action: ((WindowEnhancementAction) -> Void)?
        private var monitor: Any?
        private var gesture = PreviewSwipeGesture()
        func resetGesture() { gesture.reset() }
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.enabled, event.window === self.window, event.hasPreciseScrollingDeltas,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if event.phase == .began { self.gesture.reset() }
                if event.momentumPhase != [] { self.gesture.reset(); return event }
                let result = self.gesture.sample(x: event.scrollingDeltaX, y: event.scrollingDeltaY, orientation: self.orientation)
                let terminal = event.phase == .ended || event.phase == .cancelled
                if terminal { self.gesture.reset() }
                switch result {
                case .passThrough: return event
                case .consume: return nil
                case .maximize: if !terminal { self.action?(.maximize) }; return nil
                case .minimize: if !terminal { self.action?(.minimize) }; return nil
                }
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; gesture.reset() }
        deinit { stop() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
