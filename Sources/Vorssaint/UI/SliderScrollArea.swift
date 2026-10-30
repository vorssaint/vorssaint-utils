// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Enabled level controls receive the wheel before an enclosing horizontal strip.
protocol SliderScrollTarget: AnyObject {
    var acceptsSliderScroll: Bool { get }
}

extension SliderScroll {
    mutating func handle(_ event: NSEvent, current: Double, range: ClosedRange<Double>) -> Outcome {
        let phase: Phase
        if !event.momentumPhase.isEmpty { phase = .momentum }
        else if event.phase.contains(.began) { phase = .began }
        else if !event.phase.intersection([.changed, .stationary]).isEmpty { phase = .changed }
        else if event.phase.isEmpty { phase = .none }
        else { phase = .ended }
        return handle(phase, dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY),
                      precise: event.hasPreciseScrollingDeltas, inverted: event.isDirectionInvertedFromDevice,
                      timestamp: event.timestamp, current: current, range: range)
    }

    /// A scroll the bar does not take goes on to the list around it.
    static func pass(_ event: NSEvent, from view: NSView) {
        if let scroll = view.enclosingScrollView { scroll.scrollWheel(with: event) }
        else { view.nextResponder?.scrollWheel(with: event) }
    }
}

/// Laid over a SwiftUI slider, it takes only scroll events; clicks and drags
/// reach the slider underneath.
struct SliderScrollArea: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeNSView(context: Context) -> AreaView { AreaView() }

    func updateNSView(_ view: AreaView, context: Context) {
        view.area = self
        view.isEnabled = context.environment.isEnabled
    }

    final class AreaView: NSView, SliderScrollTarget {
        var area: SliderScrollArea?
        var isEnabled = true
        var acceptsSliderScroll: Bool { isEnabled && area != nil }
        private var scroll = SliderScroll()

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .scrollWheel else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            guard let area, isEnabled else { return SliderScroll.pass(event, from: self) }
            switch scroll.handle(event, current: area.value, range: area.range) {
            case .pass: SliderScroll.pass(event, from: self)
            case .hold: break
            case .move(let value): area.value = value
            }
        }
    }
}
