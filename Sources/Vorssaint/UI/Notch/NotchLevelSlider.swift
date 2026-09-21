// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// AppKit owns tracking, keyboard input and accessibility; the cell only
/// draws the larger filled track used by the notch's level controls. The same
/// control carries the playback position, so every bar in the panel matches.
/// A vertical one is a fader filling from the bottom; the orientation is set
/// outright because AppKit fixes it from the frame it first sees, which under
/// SwiftUI is empty.
struct NotchLevelSlider: NSViewRepresentable {
    @Binding var value: Double
    let label: String
    var range: ClosedRange<Double> = 0...1
    var tint: Color = .white
    var vertical = false
    /// A slimmer drawing can retain the native control's full hit area.
    var trackThickness: CGFloat?
    /// A value worth a tick on the track, such as unity on a fader that boosts.
    var marker: Double?
    var valueLabel: String?
    var onEditingChanged: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        vertical ? CGSize(width: proposal.width ?? 28, height: proposal.height ?? 180)
            : CGSize(width: proposal.width ?? 180, height: proposal.height ?? 28)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider()
        let cell = NotchLevelCell()
        cell.trackingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.trackingChanged(editing)
        }
        slider.cell = cell
        slider.isVertical = vertical
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
        let lower = range.lowerBound
        let upper = max(lower, range.upperBound)
        if slider.minValue != lower { slider.minValue = lower }
        if slider.maxValue != upper { slider.maxValue = upper }
        if slider.isVertical != vertical { slider.isVertical = vertical }
        (slider.cell as? NotchLevelCell)?.fill = NSColor(tint)
        (slider.cell as? NotchLevelCell)?.marker = marker
        (slider.cell as? NotchLevelCell)?.trackThickness = trackThickness
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
    var marker: Double?
    var trackThickness: CGFloat?
    var trackingChanged: ((Bool) -> Void)?
    private var isFader: Bool { isVertical }

    override func barRect(flipped: Bool) -> NSRect {
        let bounds = controlView?.bounds ?? .zero
        if let trackThickness {
            return isFader
                ? bounds.insetBy(dx: max(1, (bounds.width - trackThickness) / 2), dy: 1)
                : bounds.insetBy(dx: 1, dy: max(1, (bounds.height - trackThickness) / 2))
        }
        // Proportional so the same control reads as a chunky level bar and as
        // a slim playback position without a second cell.
        return isFader
            ? bounds.insetBy(dx: max(1, bounds.width * 0.11), dy: 1)
            : bounds.insetBy(dx: 1, dy: max(1, bounds.height * 0.11))
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
        let radius = min(track.width, track.height) / 2
        let outline = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.14).setFill()
        track.fill()
        let span = maxValue - minValue
        let fraction = span > 0 ? min(1, max(0, (doubleValue - minValue) / span)) : 0
        fill.withAlphaComponent(isEnabled ? 0.92 : 0.3).setFill()
        if isFader {
            let height = track.height * fraction
            NSRect(x: track.minX, y: flipped ? track.maxY - height : track.minY, width: track.width, height: height).fill()
        } else {
            NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height).fill()
        }
        if let marker, span > 0, marker > minValue, marker < maxValue {
            let position = (marker - minValue) / span
            NSColor.white.withAlphaComponent(0.45).setFill()
            if isFader {
                let y = flipped ? track.maxY - track.height * position : track.minY + track.height * position
                NSRect(x: track.minX, y: y - 0.5, width: track.width, height: 1).fill()
            } else {
                NSRect(x: track.minX + track.width * position - 0.5, y: track.minY, width: 1, height: track.height).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawKnob(_ knobRect: NSRect) {}
}
