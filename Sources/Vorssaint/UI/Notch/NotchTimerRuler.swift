// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A native duration ruler, including mouse dragging on desktop.
struct NotchTimerRuler: NSViewRepresentable {
    @Binding var minutes: Int
    let label: String
    let locale: Locale

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotchTimerRulerControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? NotchLayout.timerRulerHeight)
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
        control.durationLocale = locale
        control.reduceMotion = context.environment.accessibilityReduceMotion
        control.synchronize(minutes: minutes)
        control.isEnabled = context.environment.isEnabled
        control.increasedContrast = context.environment.colorSchemeContrast == .increased
        control.setAccessibilityLabel(label)
        control.setAccessibilityValueDescription(NotchTimerSupport.compactText(Double(minutes) * 60, locale: locale))
        control.needsDisplay = true
    }

    final class Coordinator: NSObject {
        var parent: NotchTimerRuler
        init(_ parent: NotchTimerRuler) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) {
            guard parent.minutes != sender.integerValue else { return }
            parent.minutes = sender.integerValue
            let pattern = (sender as? NotchTimerRulerControl)?.pendingScrubFeedback ?? .alignment
            (sender as? NotchTimerRulerControl)?.pendingScrubFeedback = nil
            NotchService.shared.provideHapticFeedback(pattern: pattern)
        }
    }
}

final class NotchTimerRulerControl: NSSlider {
    var increasedContrast = false
    var durationLocale = Locale.current
    var reduceMotion = false
    private var drag: NotchTimerRulerDrag?
    private var didDrag = false
    private var showsKeyboardFocus = false
    private var scrollValue: Double?
    private var scrollTimestamp: TimeInterval?
    private var scrollVelocity = 0.0
    var pendingScrubFeedback: NSHapticFeedbackManager.FeedbackPattern?
    private var animation: NotchTimerRulerAnimation?
    private var animationTimer: Timer?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }

    private var selectionX: CGFloat {
        bounds.minX + CGFloat(NotchTimerRulerScale.selectionX(selected: displayedValue,
                                                               width: Double(bounds.width)))
    }

    private var displayedValue: Double {
        animation?.value(at: ProcessInfo.processInfo.systemUptime) ?? doubleValue
    }

    func synchronize(minutes: Int) {
        let bounded = NotchTimerRulerScale.minute(Double(minutes))
        guard integerValue != bounded else { return }
        integerValue = bounded
        drag = nil
        scrollValue = nil
        scrollTimestamp = nil
        scrollVelocity = 0
        pendingScrubFeedback = nil
        animation = nil
        animationTimer?.invalidate()
        animationTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        showsKeyboardFocus = false
        needsDisplay = true
        drag = NotchTimerRulerDrag(
            x: Double(convert(event.locationInWindow, from: nil).x),
            value: doubleValue,
            timestamp: event.timestamp
        )
        scrollValue = nil
        scrollTimestamp = nil
        scrollVelocity = 0
        pendingScrubFeedback = nil
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, var current = drag else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let previous = current.value
        let value = current.move(to: Double(x), at: event.timestamp)
        drag = current
        didDrag = true
        pendingScrubFeedback = NotchTimerRulerFeedback.pattern(distance: abs(value - previous), speed: current.speed)
        select(value, animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, drag != nil else { drag = nil; return }
        if !didDrag {
            let visibleValue = displayedValue
            let offset = convert(event.locationInWindow, from: nil).x - selectionX
            select(NotchTimerRulerScale.moving(visibleValue, by: -Double(offset)))
        }
        drag = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard isEnabled, drag == nil else { return }
        if event.phase.contains(.began) {
            scrollValue = nil
            scrollTimestamp = event.timestamp
            scrollVelocity = 0
        }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX : event.scrollingDeltaY
        let points = Double(delta) * (event.hasPreciseScrollingDeltas ? 1 : NotchTimerRulerScale.spacing)
        let previous = scrollValue ?? doubleValue
        let value = NotchTimerRulerScale.moving(previous, by: points)
        let elapsed = event.timestamp - (scrollTimestamp ?? event.timestamp)
        if event.hasPreciseScrollingDeltas, elapsed > 0, elapsed.isFinite {
            let instantaneousSpeed = abs(Double(delta)) / elapsed
            let response = 1 - exp(-elapsed / NotchTimerRulerScale.velocitySmoothingDuration)
            scrollVelocity += (instantaneousSpeed - scrollVelocity) * response
        } else {
            scrollVelocity = 0
        }
        scrollTimestamp = event.timestamp
        scrollValue = value
        pendingScrubFeedback = NotchTimerRulerFeedback.pattern(distance: abs(value - previous),
                                                                speed: scrollVelocity)
        select(value, animated: true)
        if !event.hasPreciseScrollingDeltas || event.phase.contains(.ended) || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended) {
            scrollValue = nil
            scrollTimestamp = nil
            scrollVelocity = 0
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection([.command, .control]).isEmpty else {
            super.keyDown(with: event); return
        }
        scrollValue = nil
        scrollTimestamp = nil
        scrollVelocity = 0
        pendingScrubFeedback = nil
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

    private func select(_ value: Double, animated: Bool = false) {
        guard isEnabled else { pendingScrubFeedback = nil; return }
        let minute = NotchTimerRulerScale.minute(value)
        guard integerValue != minute else { pendingScrubFeedback = nil; return }
        let now = ProcessInfo.processInfo.systemUptime
        let from = displayedValue
        integerValue = minute
        if animated, !reduceMotion {
            animation = NotchTimerRulerAnimation(from: from, to: Double(minute), startTime: now, duration: 0.12)
            scheduleAnimationRedraw()
        } else {
            animation = nil
            animationTimer?.invalidate()
            animationTimer = nil
        }
        setAccessibilityValueDescription(NotchTimerSupport.compactText(Double(minute) * 60, locale: durationLocale))
        needsDisplay = true
        sendAction(action, to: target)
    }

    private func scheduleAnimationRedraw() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let animation = self.animation else {
                self.animationTimer?.invalidate()
                self.animationTimer = nil
                return
            }
            self.needsDisplay = true
            if animation.isComplete(at: ProcessInfo.processInfo.systemUptime) {
                self.animation = nil
                self.animationTimer?.invalidate()
                self.animationTimer = nil
                self.needsDisplay = true
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func draw(_ dirtyRect: NSRect) {
        let edgeFade = max(1, bounds.width * 0.12)
        // Drawn for the full ruler height; a shorter island compresses the
        // ticks and pointer below the labels instead of cutting them off.
        let scale = bounds.height / NotchLayout.timerRulerHeight
        let selectionX = self.selectionX
        for minute in 1...180 {
            let x = selectionX + CGFloat(NotchTimerRulerScale.offset(of: minute, selected: displayedValue))
            guard x >= bounds.minX - 16, x <= bounds.maxX + 16 else { continue }
            let fade = minute == integerValue ? 1 : min(1, max(0, min(x - bounds.minX, bounds.maxX - x) / edgeFade))
            let strength = minute <= integerValue ? 1.0 : increasedContrast ? 0.65 : 0.35
            let color = NSColor.systemOrange.withAlphaComponent(fade * strength * (isEnabled ? 1 : 0.4))
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 2, y: 26 * scale, width: 4, height: 38 * scale), xRadius: 2, yRadius: 2).fill()
            if minute.isMultiple(of: 5) || minute == 1 {
                let title = NSAttributedString(string: NotchTimerRulerScale.label(for: minute), attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: color
                ])
                title.draw(at: NSPoint(x: x - title.size().width / 2, y: 0))
            }
        }
        let pointer = roundedPointerPath(at: selectionX, scale: scale)
        NSColor.systemOrange.withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        pointer.fill()
        if window?.firstResponder === self, showsKeyboardFocus {
            NSColor.systemOrange.setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            focus.lineWidth = 1
            focus.stroke()
        }
    }

    private func roundedPointerPath(at x: CGFloat, scale: CGFloat) -> NSBezierPath {
        let vertices = [
            CGPoint(x: x, y: 70 * scale),
            CGPoint(x: x - 6, y: 80 * scale),
            CGPoint(x: x + 6, y: 80 * scale)
        ]
        let radius = 2.5 * scale

        func cornerPoint(_ vertex: CGPoint, toward neighbor: CGPoint) -> CGPoint {
            let dx = neighbor.x - vertex.x
            let dy = neighbor.y - vertex.y
            let length = hypot(dx, dy)
            guard length > 0 else { return vertex }
            let distance = min(radius, length / 2)
            return CGPoint(x: vertex.x + dx / length * distance,
                           y: vertex.y + dy / length * distance)
        }

        let path = NSBezierPath()
        path.move(to: cornerPoint(vertices[0], toward: vertices[2]))
        for index in vertices.indices {
            let vertex = vertices[index]
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let next = vertices[(index + 1) % vertices.count]
            path.line(to: cornerPoint(vertex, toward: previous))
            let outgoing = cornerPoint(vertex, toward: next)
            path.curve(to: outgoing, controlPoint1: vertex, controlPoint2: vertex)
            path.line(to: cornerPoint(next, toward: vertex))
        }
        path.close()
        return path
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

    deinit {
        animationTimer?.invalidate()
    }
}
