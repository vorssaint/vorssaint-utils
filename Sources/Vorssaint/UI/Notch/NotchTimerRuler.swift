// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A native slider with a centered ruler, including mouse dragging on desktop.
struct NotchTimerRuler: NSViewRepresentable {
    @Binding var minutes: Int
    let label: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchTimerRulerControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? 82)
    }

    func makeNSView(context: Context) -> NotchTimerRulerControl {
        let control = NotchTimerRulerControl()
        control.focusRingType = .none
        control.minValue = 1
        control.maxValue = 180
        control.altIncrementValue = 1
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }

    func updateNSView(_ control: NotchTimerRulerControl, context: Context) {
        context.coordinator.parent = self
        control.synchronize(minutes: minutes)
        control.isEnabled = context.environment.isEnabled
        control.increasedContrast = context.environment.colorSchemeContrast == .increased
        control.setAccessibilityLabel(label)
        control.setAccessibilityValueDescription("\(minutes) \(label)")
        control.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: NotchTimerRuler
        init(_ parent: NotchTimerRuler) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            guard parent.minutes != sender.integerValue else { return }
            parent.minutes = sender.integerValue
            NotchService.shared.provideHapticFeedback()
        }
    }
}

final class NotchTimerRulerControl: NSSlider {
    var increasedContrast = false
    private var drag: (x: CGFloat, value: Double)?
    private var didDrag = false
    private var showsKeyboardFocus = false
    private var scrollValue: Double?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    func synchronize(minutes: Int) {
        let bounded = NotchTimerRulerScale.minute(Double(minutes))
        guard integerValue != bounded else { return }
        integerValue = bounded
        drag = nil
        scrollValue = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        showsKeyboardFocus = false
        needsDisplay = true
        drag = (convert(event.locationInWindow, from: nil).x, doubleValue)
        scrollValue = nil
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, let previous = drag else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let value = NotchTimerRulerScale.moving(previous.value, by: Double(x - previous.x))
        drag = (x, value)
        didDrag = true
        select(value)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, drag != nil else { drag = nil; return }
        if !didDrag {
            let offset = convert(event.locationInWindow, from: nil).x - bounds.midX
            select(NotchTimerRulerScale.moving(doubleValue, by: -Double(offset)))
        }
        drag = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, drag == nil else { return }
        if event.phase.contains(.began) { scrollValue = nil }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let points = Double(delta) * (event.hasPreciseScrollingDeltas ? 1 : NotchTimerRulerScale.spacing)
        let value = NotchTimerRulerScale.moving(scrollValue ?? doubleValue, by: points)
        scrollValue = value
        select(value)
        if !event.hasPreciseScrollingDeltas || event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) { scrollValue = nil }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection([.command, .control]).isEmpty else {
            super.keyDown(with: event); return
        }
        scrollValue = nil
        showsKeyboardFocus = true
        needsDisplay = true
        switch event.keyCode {
        case 123, 125: select(doubleValue - 1)
        case 124, 126: select(doubleValue + 1)
        case 115: select(minValue)
        case 119: select(maxValue)
        default: super.keyDown(with: event)
        }
    }

    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return }
        scrollValue = nil
        select(number.doubleValue)
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        scrollValue = nil
        select(doubleValue + 1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        scrollValue = nil
        select(doubleValue - 1)
        return true
    }

    private func select(_ value: Double) {
        guard isEnabled else { return }
        let minute = NotchTimerRulerScale.minute(value)
        guard integerValue != minute else { return }
        integerValue = minute
        setAccessibilityValueDescription("\(minute) \(accessibilityLabel() ?? "")")
        needsDisplay = true
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let edgeFade = max(1, bounds.width * 0.12)
        for minute in 1...180 {
            let x = bounds.midX + CGFloat(NotchTimerRulerScale.offset(of: minute, selected: integerValue))
            guard x >= bounds.minX - 16, x <= bounds.maxX + 16 else { continue }
            let fade = min(1, max(0, min(x - bounds.minX, bounds.maxX - x) / edgeFade))
            let strength = minute <= integerValue ? 1.0 : increasedContrast ? 0.65 : 0.35
            let color = NSColor.systemOrange.withAlphaComponent(fade * strength * (isEnabled ? 1 : 0.4))
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 2, y: 26, width: 4, height: 38), xRadius: 2, yRadius: 2).fill()
            if minute.isMultiple(of: 5) || minute == 1 {
                let title = NSAttributedString(string: String(minute), attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: color
                ])
                title.draw(at: NSPoint(x: x - title.size().width / 2, y: 0))
            }
        }
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: bounds.midX, y: 70))
        pointer.line(to: NSPoint(x: bounds.midX + 6, y: 80))
        pointer.line(to: NSPoint(x: bounds.midX - 6, y: 80))
        pointer.close()
        NSColor.systemOrange.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        pointer.fill()
        if window?.firstResponder === self, showsKeyboardFocus {
            NSColor.systemOrange.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            focus.lineWidth = 1
            focus.stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        showsKeyboardFocus = accepted
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        needsDisplay = true
        return accepted
    }
}
