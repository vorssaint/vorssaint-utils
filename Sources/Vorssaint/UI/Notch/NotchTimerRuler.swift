// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A native duration ruler, including mouse dragging on desktop.
struct NotchTimerRuler: NSViewRepresentable {
    @Binding var minutes: Int
    let label: String
    let locale: Locale
    var range: ClosedRange<Int> = 1...180

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchTimerRulerControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? NotchLayout.timerRulerHeight)
    }

    func makeNSView(context: Context) -> NotchTimerRulerControl {
        let control = NotchTimerRulerControl()
        control.focusRingType = .none
        control.altIncrementValue = 1
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }

    func updateNSView(_ control: NotchTimerRulerControl, context: Context) {
        context.coordinator.parent = self
        control.durationLocale = locale
        control.minValue = Double(range.lowerBound)
        control.maxValue = Double(range.upperBound)
        control.synchronize(minutes: minutes)
        control.isEnabled = context.environment.isEnabled
        control.increasedContrast = context.environment.colorSchemeContrast == .increased
        control.setAccessibilityLabel(label)
        control.setAccessibilityValueDescription(minutes == 0 ? "0" : NotchTimerSupport.compactText(Double(minutes) * 60, locale: locale))
        control.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: NotchTimerRuler
        init(_ parent: NotchTimerRuler) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            let changed = parent.minutes != sender.integerValue
            parent.minutes = sender.integerValue
            if changed { NotchService.shared.provideHapticFeedback() }
        }
    }
}

final class NotchTimerRulerControl: NSSlider {
    private var minuteRange: ClosedRange<Int> { Int(minValue)...Int(maxValue) }
    var increasedContrast = false
    var durationLocale = Locale.current
    private var drag: (x: CGFloat, value: Double)?
    private var didDrag = false
    private var showsKeyboardFocus = false
    private var scrollValue: Double?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    private var selectionX: CGFloat {
        bounds.minX + CGFloat(NotchTimerRulerScale.selectionX(selected: integerValue, width: Double(bounds.width), range: minuteRange))
    }

    func synchronize(minutes: Int) {
        let bounded = NotchTimerRulerScale.minute(Double(minutes), range: minuteRange)
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
        let value = NotchTimerRulerScale.moving(previous.value, by: Double(x - previous.x), range: minuteRange)
        drag = (x, value)
        didDrag = true
        select(value)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, drag != nil else { drag = nil; return }
        if !didDrag {
            let offset = convert(event.locationInWindow, from: nil).x - selectionX
            select(NotchTimerRulerScale.moving(doubleValue, by: -Double(offset), range: minuteRange))
        }
        drag = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, drag == nil else { return }
        if event.phase.contains(.began) { scrollValue = nil }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let points = Double(delta) * (event.hasPreciseScrollingDeltas ? 1 : NotchTimerRulerScale.spacing)
        let value = NotchTimerRulerScale.moving(scrollValue ?? doubleValue, by: points, range: minuteRange)
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
        let minute = NotchTimerRulerScale.minute(value, range: minuteRange)
        if integerValue != minute {
            integerValue = minute
            setAccessibilityValueDescription(minute == 0 ? "0" : NotchTimerSupport.compactText(Double(minute) * 60, locale: durationLocale))
            needsDisplay = true
        }
        // Even a drag within one minute commits that minute, clearing typed seconds.
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        let edgeFade = max(1, bounds.width * 0.12)
        // Drawn for the full ruler height; a shorter island compresses the
        // ticks and pointer below the labels instead of cutting them off.
        let scale = bounds.height / NotchLayout.timerRulerHeight
        let selectionX = self.selectionX
        for minute in minuteRange {
            let x = selectionX + CGFloat(NotchTimerRulerScale.offset(of: minute, selected: integerValue))
            guard x >= bounds.minX - 16, x <= bounds.maxX + 16 else { continue }
            let fade = minute == integerValue ? 1 : min(1, max(0, min(x - bounds.minX, bounds.maxX - x) / edgeFade))
            let strength = minute <= integerValue ? 1.0 : increasedContrast ? 0.65 : 0.35
            let color = NSColor.systemOrange.withAlphaComponent(fade * strength * (isEnabled ? 1 : 0.4))
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 2, y: 26 * scale, width: 4, height: 38 * scale), xRadius: 2, yRadius: 2).fill()
            if minute.isMultiple(of: 5) || minute == minuteRange.lowerBound {
                let title = NSAttributedString(string: NotchTimerRulerScale.label(for: minute), attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: color
                ])
                title.draw(at: NSPoint(x: x - title.size().width / 2, y: 0))
            }
        }
        let pointer = NSBezierPath()
        pointer.move(to: NSPoint(x: selectionX, y: 70 * scale))
        pointer.line(to: NSPoint(x: selectionX + 6, y: 80 * scale))
        pointer.line(to: NSPoint(x: selectionX - 6, y: 80 * scale))
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
