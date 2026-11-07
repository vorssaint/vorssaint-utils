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
    /// A level moved from outside, by a key, eases to its new place; the
    /// playback position and a drag follow at once.
    var easesChanges = false
    /// A scroll over the bar moves the level; the playback position is not
    /// scrolled, since each step would seek.
    var scrollable = true
    var onEditingChanged: ((Bool) -> Void)?
    /// A scroll came to rest on `marker`.
    var onSnap: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSlider, context: Context) -> CGSize? {
        vertical ? CGSize(width: proposal.width ?? 28, height: proposal.height ?? 180)
            : CGSize(width: proposal.width ?? 180, height: proposal.height ?? 28)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NotchLevelControl()
        let cell = NotchLevelCell()
        slider.trackingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.trackingChanged(editing)
        }
        cell.trackingChanged = { [weak coordinator = context.coordinator] editing in
            coordinator?.trackingChanged(editing)
        }
        slider.snapped = { [weak coordinator = context.coordinator] in coordinator?.parent.onSnap?() }
        slider.settled = { [weak coordinator = context.coordinator] in coordinator?.syncLevel() }
        slider.cell = cell
        slider.isVertical = vertical
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.altIncrementValue = 0.01
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        context.coordinator.slider = slider
        return slider
    }

    static func dismantleNSView(_ slider: NSSlider, coordinator: Coordinator) {
        (slider as? NotchLevelControl)?.cancelScroll()
        coordinator.stopEasing()
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        let lower = range.lowerBound
        let upper = max(lower, range.upperBound)
        if slider.minValue != lower { slider.minValue = lower }
        if slider.maxValue != upper { slider.maxValue = upper }
        if slider.isVertical != vertical { slider.isVertical = vertical }
        (slider as? NotchLevelControl)?.scrollable = scrollable
        (slider as? NotchLevelControl)?.reducesMotion = context.environment.accessibilityReduceMotion
        (slider.cell as? NotchLevelCell)?.leavesHoverRoom = scrollable
        (slider.cell as? NotchLevelCell)?.fill = NSColor(tint)
        (slider.cell as? NotchLevelCell)?.marker = marker
        (slider.cell as? NotchLevelCell)?.trackThickness = trackThickness
        let bounded = value.isFinite ? min(upper, max(lower, value)) : lower
        if slider.doubleValue != bounded, (slider as? NotchLevelControl)?.isGliding != true {
            let cell = slider.cell as? NotchLevelCell
            let drawn = cell?.drawnValue ?? slider.doubleValue
            slider.doubleValue = bounded
            // A slider not yet on screen starts at its level rather than
            // filling up from empty each time the page opens.
            if NotchSliderEasing.eases(enabled: easesChanges,
                                       onScreen: slider.window?.occlusionState.contains(.visible) == true,
                                       reduceMotion: context.environment.accessibilityReduceMotion,
                                       tracking: cell?.isTracking != false) {
                context.coordinator.ease(from: drawn, to: bounded)
            } else {
                context.coordinator.stopEasing()
            }
        }
        slider.isEnabled = context.environment.isEnabled
        if !scrollable || !slider.isEnabled { (slider as? NotchLevelControl)?.cancelScroll() }
        (slider as? NotchLevelControl)?.refreshHover()
        let span = upper - lower
        slider.setAccessibilityValueDescription(
            valueLabel ?? "\(Int((span > 0 ? (bounded - lower) / span * 100 : 0).rounded()))%")
        slider.setAccessibilityLabel(label)
    }

    final class Coordinator: NSObject {
        var parent: NotchLevelSlider
        weak var slider: NSSlider?
        private var editing = NotchSliderEditing()
        private var easing: NotchSliderEasing?
        private var timer: Timer?
        private var lastTracked: Double?
        init(_ parent: NotchLevelSlider) { self.parent = parent }
        func trackingChanged(_ value: Bool) {
            if value {
                stopEasing()
                lastTracked = nil
            }
            editing.trackingChanged(value, onEditingChanged: parent.onEditingChanged)
        }

        /// Takes up a level that changed while a scroll held it off.
        func syncLevel() {
            guard let slider, parent.value.isFinite else { return }
            let bounded = min(slider.maxValue, max(slider.minValue, parent.value))
            if slider.doubleValue != bounded { slider.doubleValue = bounded }
        }

        func ease(from: Double, to: Double) {
            easing = NotchSliderEasing(from: from, to: to, start: CACurrentMediaTime())
            (slider?.cell as? NotchLevelCell)?.drawnValue = from
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        func stopEasing() {
            timer?.invalidate()
            timer = nil
            easing = nil
            guard let slider, let cell = slider.cell as? NotchLevelCell, cell.drawnValue != nil else { return }
            cell.drawnValue = nil
            slider.needsDisplay = true
        }

        private func tick() {
            guard let easing, let slider, let cell = slider.cell as? NotchLevelCell else { return stopEasing() }
            let step = easing.value(at: CACurrentMediaTime())
            guard !step.done else { return stopEasing() }
            cell.drawnValue = step.value
            slider.needsDisplay = true
        }
        /// While dragged, the level pauses at the marker with a click.
        private func pauseAtMarker(_ slider: NSSlider) {
            guard let cell = slider.cell as? NotchLevelCell, cell.isTracking, let marker = parent.marker,
                  // An action can come with no new pointer position. The level
                  // it finds is already paused, and must not be paused again.
                  slider.doubleValue != lastTracked else { return }
            let track = cell.barRect(flipped: slider.isFlipped)
            let band = NotchSliderPause.band(trackLength: Double(slider.isVertical ? track.height : track.width),
                                             span: slider.maxValue - slider.minValue)
            let level = NotchSliderPause.value(pointer: slider.doubleValue, stop: marker, band: band,
                                                  range: slider.minValue...slider.maxValue)
            if level != slider.doubleValue { slider.doubleValue = level }
            if NotchSliderPause.arrived(from: lastTracked, to: level, stop: marker) { parent.onSnap?() }
            lastTracked = level
        }

        @objc func changed(_ sender: NSSlider) {
            stopEasing()
            pauseAtMarker(sender)
            editing.valueChanged({ parent.value = sender.doubleValue }, onEditingChanged: parent.onEditingChanged)
        }
    }
}

private final class NotchLevelControl: NSSlider, SliderScrollTarget {
    var scrollable = true
    var acceptsSliderScroll: Bool { scrollable && isEnabled }
    var trackingChanged: ((Bool) -> Void)?
    var snapped: (() -> Void)?
    var settled: (() -> Void)?
    var reducesMotion = false
    /// A level from outside waits while the drawn bar follows a scroll.
    var isGliding: Bool { link != nil && CACurrentMediaTime() - lastMove < NotchSliderGlide.hold }
    private var scroll = SliderScroll()
    private var scrolling = false { didSet { refreshHover() } }
    private var hovering = false { didSet { refreshHover() } }
    private var hoverArea: NSTrackingArea?
    private var hoverTarget: CGFloat = 0
    private var hoverLink: CADisplayLink?
    private var hoverFade = NotchSliderGlide(drawn: 0)
    private var lastHoverFrame: CFTimeInterval?
    private var link: CADisplayLink?
    private var glide = NotchSliderGlide(drawn: 0)
    private var lastFrame: CFTimeInterval?
    private var lastMove: CFTimeInterval = 0
    private var lastWrite: CFTimeInterval = 0
    private var writePending = false
    private var pendingScrollEvents: [NSEvent] = []

    func cancelScroll() {
        finishScrollEditing()
        scroll = SliderScroll()
        pendingScrollEvents.removeAll()
        stopGlide()
    }

    private func flushWrite() {
        guard writePending else { return }
        writePending = false
        lastWrite = CACurrentMediaTime()
        sendAction(action, to: target)
    }

    private func finishScrollEditing() {
        flushWrite()
        guard scrolling else { return }
        scrolling = false
        trackingChanged?(false)
    }

    /// The bar shows it will take a scroll while the pointer is on it, and
    /// keeps showing it for a swipe that drifts off. The bar swells in and out.
    func refreshHover() {
        let target: CGFloat = acceptsSliderScroll && (hovering || scrolling) ? 1 : 0
        guard let cell = cell as? NotchLevelCell, hoverTarget != target else { return }
        hoverTarget = target
        guard window != nil, !reducesMotion else {
            stopHoverFade()
            cell.hoverAmount = target
            return
        }
        guard hoverLink == nil else { return }
        hoverFade = NotchSliderGlide(drawn: Double(cell.hoverAmount))
        lastHoverFrame = nil
        let link = displayLink(target: self, selector: #selector(hoverFrame(_:)))
        link.add(to: .main, forMode: .common)
        hoverLink = link
    }

    private func stopHoverFade() {
        hoverLink?.invalidate()
        hoverLink = nil
    }

    @objc private func hoverFrame(_ link: CADisplayLink) {
        let interval = lastHoverFrame.map { link.targetTimestamp - $0 } ?? link.targetTimestamp - link.timestamp
        lastHoverFrame = link.targetTimestamp
        let arrived = hoverFade.advance(toward: Double(hoverTarget), interval: interval, span: 1,
                                        reduceMotion: reducesMotion)
        (cell as? NotchLevelCell)?.hoverAmount = CGFloat(hoverFade.drawn)
        if arrived { stopHoverFade() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self)
            addTrackingArea(area)
            hoverArea = area
        }
        if let window { hovering = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    /// As the level moves, AppKit marks only strips around the hidden knob
    /// for redrawing. The cell draws the whole bar, fill and swell together,
    /// so a strip redrawn alone left stale blocks of the old bar beside it.
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        super.setNeedsDisplay(bounds)
    }

    private func startGlide(from drawn: Double) {
        lastMove = CACurrentMediaTime()
        guard link == nil, window != nil else { return }
        glide = NotchSliderGlide(drawn: drawn)
        (cell as? NotchLevelCell)?.scrollDrawn = drawn
        lastFrame = nil
        let link = displayLink(target: self, selector: #selector(glideFrame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopGlide() {
        link?.invalidate()
        link = nil
        guard let cell = cell as? NotchLevelCell, cell.scrollDrawn != nil else { return }
        cell.scrollDrawn = nil
        needsDisplay = true
    }

    @objc private func glideFrame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        // Stepped by when the frame shows, not when this runs, which varies.
        let frame = link.targetTimestamp
        let interval = lastFrame.map { frame - $0 } ?? link.targetTimestamp - link.timestamp
        let arrived = glide.advance(toward: doubleValue, interval: interval, span: maxValue - minValue,
                                    reduceMotion: reducesMotion)
        lastFrame = frame
        (cell as? NotchLevelCell)?.scrollDrawn = glide.drawn
        needsDisplay = true
        if now - lastWrite >= NotchSliderGlide.writeInterval { flushWrite() }
        guard arrived, now - lastMove >= NotchSliderGlide.hold else { return }
        flushWrite()
        stopGlide()
        settled?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelScroll()
            hovering = false
            stopHoverFade()
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelScroll()
        writePending = false
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard acceptsSliderScroll, maxValue >= minValue else {
            cancelScroll()
            return SliderScroll.pass(event, from: self)
        }
        if scroll.verticalOnly != isVertical {
            cancelScroll()
            scroll.verticalOnly = isVertical
        }
        if event.phase.contains(.began) {
            finishScrollEditing()
            pendingScrollEvents.removeAll(keepingCapacity: true)
            scrolling = true
            trackingChanged?(true)
        }
        defer {
            if !event.phase.intersection([.ended, .cancelled]).isEmpty
                || !event.momentumPhase.isEmpty || event.phase.isEmpty {
                finishScrollEditing()
            }
        }
        scroll.stop = (cell as? NotchLevelCell)?.marker
        let outcome = scroll.handle(event, current: doubleValue, range: minValue...maxValue)
        if scroll.isChoosingAxis {
            if event.phase.contains(.began) || event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                pendingScrollEvents.append(event)
            }
            return
        }
        // The strip gets the original begin and small deltas in order, even
        // when the deciding event only moves up.
        let pending = pendingScrollEvents
        pendingScrollEvents.removeAll()
        switch outcome {
        case .pass:
            // A gesture handed to the strip may never come back to end here,
            // and a scroll left open would keep the bar swelled.
            finishScrollEditing()
            SliderScroll.pass(event, from: self, after: pending)
        case .hold: break
        case .move(let value):
            guard value != doubleValue else { return }
            startGlide(from: doubleValue)
            doubleValue = value
            writePending = true
            let snap = scroll.takeSnap()
            if link == nil || snap || CACurrentMediaTime() - lastWrite >= NotchSliderGlide.writeInterval { flushWrite() }
            if snap { snapped?() }
        }
    }
}

private final class NotchLevelCell: NSSliderCell {
    var fill: NSColor = .white
    var marker: Double?
    var trackThickness: CGFloat?
    var trackingChanged: ((Bool) -> Void)?
    /// Where the bar is drawn while it eases to the slider's value.
    var drawnValue: Double?
    /// Where the bar is drawn while it follows a scroll.
    var scrollDrawn: Double?
    /// A bar that takes a scroll keeps room around it to swell into on hover,
    /// so nothing beside it moves when it does.
    var leavesHoverRoom = false
    private static let hoverRoom: CGFloat = 4
    /// How much thicker a hovered bar draws on each side. Only its thickness
    /// grows, so the level under the pointer stays where it was.
    private static let hoverGrowth: CGFloat = 3
    /// How far the bar has swelled for the hover, from 0 to 1.
    var hoverAmount: CGFloat = 0 {
        didSet { if hoverAmount != oldValue { controlView?.needsDisplay = true } }
    }
    private(set) var isTracking = false
    private var isFader: Bool { isVertical }

    override func barRect(flipped: Bool) -> NSRect {
        let bounds = controlView?.bounds ?? .zero
        let room = leavesHoverRoom ? Self.hoverRoom : 1
        if let trackThickness {
            return isFader
                ? bounds.insetBy(dx: max(room, (bounds.width - trackThickness) / 2), dy: room)
                : bounds.insetBy(dx: room, dy: max(room, (bounds.height - trackThickness) / 2))
        }
        // Proportional so the same control reads as a chunky level bar and as
        // a slim playback position without a second cell.
        return isFader
            ? bounds.insetBy(dx: max(room, bounds.width * 0.11), dy: room)
            : bounds.insetBy(dx: room, dy: max(room, bounds.height * 0.11))
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        let started = super.startTracking(at: startPoint, in: controlView)
        if started {
            isTracking = true
            trackingChanged?(true)
        }
        return started
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint,
                               in controlView: NSView, mouseIsUp flag: Bool) {
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
        isTracking = false
        trackingChanged?(false)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let grow = Self.hoverGrowth * hoverAmount
        let track = barRect(flipped: flipped).insetBy(dx: isFader ? -grow : 0, dy: isFader ? 0 : -grow)
        guard track.width > 0, track.height > 0 else { return }
        let radius = min(track.width, track.height) / 2
        let outline = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        NSColor.white.withAlphaComponent(0.14 + 0.08 * hoverAmount).setFill()
        track.fill()
        let span = maxValue - minValue
        let fraction = span > 0 ? min(1, max(0, ((scrollDrawn ?? drawnValue ?? doubleValue) - minValue) / span)) : 0
        fill.withAlphaComponent(isEnabled ? 0.92 + 0.08 * hoverAmount : 0.3).setFill()
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

    /// The knob is never drawn, so it has no length either. AppKit then maps
    /// the pointer across the whole track, as the fill is drawn, rather than
    /// along a run shortened by half a hidden knob at each end, which left the
    /// fill behind the pointer near the start and ahead of it near the end.
    override func knobRect(flipped: Bool) -> NSRect {
        let knob = super.knobRect(flipped: flipped)
        return isFader ? NSRect(x: knob.minX, y: knob.midY, width: knob.width, height: 0)
            : NSRect(x: knob.midX, y: knob.minY, width: 0, height: knob.height)
    }
}
