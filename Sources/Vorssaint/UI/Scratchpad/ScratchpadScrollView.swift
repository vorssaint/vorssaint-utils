// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Keep phased trackpad events in the scroll view. Responsive scrolling
/// can take over after the first event and deliver the rest privately.
final class ScratchpadScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    var onSwipe: ((ScratchpadDirection) -> Void)?
    private var swipe = ScratchpadSwipe()

    override func scrollWheel(with event: NSEvent) {
        if let direction = swipeDirection(for: event) { onSwipe?(direction) }
        super.scrollWheel(with: event)
    }

    private func swipeDirection(for event: NSEvent) -> ScratchpadDirection? {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let phase = event.phase
        if !phase.intersection([.ended, .cancelled]).isEmpty {
            return swipe.finish(cancelled: phase.contains(.cancelled) || !modifiers.isEmpty)
        }
        guard modifiers.isEmpty, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else {
            swipe = ScratchpadSwipe()
            return nil
        }
        if phase.contains(.began) { swipe.begin() }
        guard !phase.intersection([.began, .changed]).isEmpty else { return nil }

        // Follow finger movement with either system scroll-direction setting.
        let sign = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        swipe.move(x: sign * event.scrollingDeltaX, y: sign * event.scrollingDeltaY)
        return nil
    }
}
