// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Native gestures shared by pinned screenshot content and its window tests.
class ScreenshotPinGestureView: NSView {
    override func scrollWheel(with event: NSEvent) {
        guard let window, !window.ignoresMouseEvents, event.momentumPhase.isEmpty else { return }
        var delta = event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas, let native = event.cgEvent {
            delta = ScreenshotSupport.captureLoupeWheelDelta(
                scrollingDelta: delta,
                lineDelta: native.getIntegerValueField(.scrollWheelEventDeltaAxis1),
                fixedPointDelta: native.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        }
        guard delta.isFinite, delta != 0 else { return }
        let preciseDelta = min(24, max(-24, delta))
        if event.modifierFlags.contains(.option) {
            let change = event.hasPreciseScrollingDeltas ? preciseDelta * 0.005 : (delta > 0 ? 0.05 : -0.05)
            window.alphaValue = min(1, max(0.2, window.alphaValue + change))
            return
        }
        let factor = event.hasPreciseScrollingDeltas ? 1 + preciseDelta * 0.014 : (delta > 0 ? 1.03 : 1 / 1.03)
        zoom(by: factor, at: event.locationInWindow)
    }

    override func magnify(with event: NSEvent) {
        guard let window, !window.ignoresMouseEvents else { return }
        let amount = event.magnification
        guard amount.isFinite, amount != 0, amount > -1 else { return }
        zoom(by: 1 + amount, at: event.locationInWindow)
    }

    private func zoom(by factor: CGFloat, at point: CGPoint) {
        guard let window, factor.isFinite, factor > 0, factor != 1,
              point.x.isFinite, point.y.isFinite else { return }
        let frame = window.frame
        let anchor = window.convertPoint(toScreen: point)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? window.screen,
              frame.width > 0, frame.height > 0 else { return }
        let limits = screen.visibleFrame
        let aspect = window.contentAspectRatio
        guard aspect.width > 0, aspect.height > 0 else { return }
        // NSWindow rounds each new frame independently. Always derive the
        // height from the image ratio so small packets cannot accumulate skew.
        let imageHeight = frame.width * aspect.height / aspect.width
        let minimum = max(window.minSize.width / frame.width, window.minSize.height / imageHeight)
        let maximum = min(limits.width / frame.width, limits.height / imageHeight)
        guard maximum > 0 else { return }
        // A very elongated image may not fit both its minimum and the display;
        // keep it reachable on screen in that case.
        let scale = min(max(factor, minimum), maximum)
        // Floating-point multiplication can exceed the fitted edge by a tiny
        // fraction; AppKit rounds that out to an extra point off screen.
        let width = min(limits.width, frame.width * scale)
        let height = min(limits.height, imageHeight * scale)
        let next = CGRect(x: min(max(anchor.x - point.x * scale, limits.minX), limits.maxX - width),
                          y: min(max(anchor.y - point.y / frame.height * height, limits.minY), limits.maxY - height),
                          width: width, height: height)
        guard next != frame else { return }
        window.setFrame(next, display: true)
    }
}
