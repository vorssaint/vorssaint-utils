// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// AppKit owns tracking, keyboard input and accessibility; the cell only
/// draws the larger filled track used by the notch's level controls. The same
/// control carries the playback position, so every bar in the panel matches.
struct NotchLevelSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String
    var range: ClosedRange<Double> = 0...1
    var tint: Color = .white
    var valueLabel: String?
    var onEditingChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: proposal.height ?? 28)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        // The environment does cross into a representable, but an AppKit
        // control does nothing with it on its own. Handed the direction, the
        // cell mirrors its own tracking, so a click near an edge means what a
        // reader of the language expects; the fill below is drawn here and has
        // to be mirrored by hand.
        slider.userInterfaceLayoutDirection = context.environment.layoutDirection == .rightToLeft
            ? .rightToLeft : .leftToRight
        let cell = NotchLevelCell()
        cell.trackingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.trackingChanged(editing)
        }
        slider.cell = cell
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.altIncrementValue = 0.01
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        let wanted: NSUserInterfaceLayoutDirection =
            context.environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        if slider.userInterfaceLayoutDirection != wanted { slider.userInterfaceLayoutDirection = wanted }
        let lower = range.lowerBound
        let upper = max(lower, range.upperBound)
        if slider.minValue != lower { slider.minValue = lower }
        if slider.maxValue != upper { slider.maxValue = upper }
        (slider.cell as? NotchLevelCell)?.fill = NSColor(tint)
        let bounded = value.isFinite ? min(upper, max(lower, value)) : lower
        if slider.doubleValue != bounded { slider.doubleValue = bounded }
        slider.isEnabled = context.environment.isEnabled
        let span = upper - lower
        slider.setAccessibilityValueDescription(
            valueLabel ?? "\(Int((span > 0 ? (bounded - lower) / span * 100 : 0).rounded()))%")
        slider.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var parent: NotchLevelSlider
        private var editing = NotchSliderEditing()
        init(_ parent: NotchLevelSlider) { self.parent = parent }
        func trackingChanged(_ value: Bool) {
            editing.trackingChanged(value, onEditingChanged: parent.onEditingChanged)
        }
        @objc func changed(_ sender: NSSlider) {
            editing.valueChanged({ parent.value = sender.doubleValue }, onEditingChanged: parent.onEditingChanged)
        }
    }
}

private final class NotchLevelCell: NSSliderCell {
    var fill: NSColor = .white
    var trackingChanged: ((Bool) -> Void)?

    override func barRect(flipped: Bool) -> NSRect {
        let bounds = controlView?.bounds ?? .zero
        // Proportional so the same control reads as a chunky level bar and as
        // a slim playback position without a second cell.
        return bounds.insetBy(dx: 1, dy: max(1, bounds.height * 0.11))
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let started = super.startTracking(at: startPoint, in: controlView)
        if started { trackingChanged?(true) }
        return started
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint,
                               in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        trackingChanged?(false)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = barRect(flipped: flipped)
        guard track.width > 0, track.height > 0 else { return }
        let outline = NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.14).setFill()
        track.fill()
        let fraction = maxValue > minValue ? min(1, max(0, (doubleValue - minValue) / (maxValue - minValue))) : 0
        fill.withAlphaComponent(isEnabled ? 0.92 : 0.3).setFill()
        let mirrored = (controlView?.userInterfaceLayoutDirection ?? userInterfaceLayoutDirection) == .rightToLeft
        NotchLevelBar.fillRect(track: track, fraction: fraction, mirrored: mirrored).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawKnob(_ knobRect: NSRect) {}
}
