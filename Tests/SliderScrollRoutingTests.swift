// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Actual AppKit scroll delivery and production editing/restoration methods.
/// No window is shown and the hardware write is replaced by a no-op.
enum SliderScrollRoutingTests {
    class LightState {
        var keyboardLightLevel: Float? = 0.8
        var keyboardLightEnabled: Bool? = true
        var keyboardDragStart: Float??
        var lastKeyboardLightLevel: Float = 0.8
        var keyboardLevelWork: DispatchWorkItem? = DispatchWorkItem {}
        func commitKeyboardLightLevel() {}
    }
    final class Target: NSObject {
        let light = Light()
        var editing = NotchSliderEditing()
        var callbacks: [Bool] = []
        func tracking(_ value: Bool) {
            editing.trackingChanged(value, onEditingChanged: callback)
        }
        func callback(_ value: Bool) {
            callbacks.append(value)
            light.keyboardLightDragChanged(value)
        }
        @objc func changed(_ sender: NSSlider) {
            editing.valueChanged({ light.setKeyboardLightLevel(Float(sender.doubleValue)) },
                                 onEditingChanged: callback)
        }
    }

    /// A scroll view without a window does not move, so it records its input.
    final class Strip: NSScrollView {
        var received: [NSEvent] = []
        override func scrollWheel(with event: NSEvent) {
            received.append(event)
            super.scrollWheel(with: event)
        }
    }

    static func event(_ phase: CGScrollPhase?, delta: Int32 = 0, sideways: Int32 = 0,
                      momentum: CGMomentumScrollPhase = .none, units: CGScrollEventUnit = .pixel,
                      timestamp: CGEventTimestamp? = nil) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: units, wheelCount: 2,
                         wheel1: delta, wheel2: sideways, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum.rawValue))
        if let timestamp { cg.timestamp = timestamp }
        return NSEvent(cgEvent: cg)!
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let slider = NotchLevelControl(frame: NSRect(x: 0, y: 0, width: 28, height: 80))
        slider.minValue = 0
        slider.maxValue = 1
        let target = Target()
        slider.target = target
        slider.action = #selector(Target.changed(_:))
        slider.trackingChanged = { target.tracking($0) }
        func begin() {
            slider.cancelScroll()
            slider.doubleValue = 0.8
            target.light.keyboardLightLevel = 0.8
            target.light.lastKeyboardLightLevel = 0.8
            target.callbacks = []
            slider.scrollWheel(with: event(.began))
            slider.scrollWheel(with: event(.changed, delta: -120))
            slider.scrollWheel(with: event(.changed, delta: -200))
        }
        begin()
        suite.expect(slider.doubleValue == 0 && target.light.keyboardLightLevel == 0
                     && target.callbacks == [true],
                     "native phased scroll actions keep one edit open while the keyboard light reaches zero (value \(slider.doubleValue), light \(String(describing: target.light.keyboardLightLevel)), edits \(target.callbacks))")
        slider.scrollWheel(with: event(.ended))
        suite.expect(target.callbacks == [true, false] && target.light.lastKeyboardLightLevel == 0.8
                     && target.light.keyboardDragStart == nil,
                     "ending the native scroll preserves the pre-gesture keyboard light level for restoration")
        begin()
        slider.scrollWheel(with: event(.cancelled))
        suite.expect(target.callbacks == [true, false] && target.light.lastKeyboardLightLevel == 0.8,
                     "a cancelled scroll closes the edit once and preserves restoration")
        begin()
        slider.isEnabled = false
        slider.scrollWheel(with: event(.changed, delta: 50))
        suite.expect(target.callbacks == [true, false] && slider.doubleValue == 0,
                     "disabling a slider during a gesture finishes the edit without another value change (value \(slider.doubleValue), edits \(target.callbacks))")
        slider.isEnabled = true
        begin()
        slider.cancelScroll()
        slider.cancelScroll()
        suite.expect(target.callbacks == [true, false],
                     "dismantling or detaching a scrolled control closes its edit only once")

        let strip = Strip(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 50))
        strip.documentView = document
        document.addSubview(slider)
        let child = NSView(frame: .zero)
        slider.addSubview(child)
        suite.expect(Route.sidewaysStrip(at: slider) == nil && Route.sidewaysStrip(at: child) == nil,
                     "an enabled slider and its descendants retain the wheel in an overflowing horizontal strip")
        slider.isEnabled = false
        suite.expect(Route.sidewaysStrip(at: slider) === strip,
                     "a disabled slider leaves horizontal wheel navigation available")
        slider.isEnabled = true
        slider.scrollable = false
        suite.expect(Route.sidewaysStrip(at: slider) === strip,
                     "a playback-position control does not claim scroll input")
        slider.scrollable = true
        suite.expect(Route.sidewaysStrip(at: document) === strip,
                     "scrolling the surrounding app list still navigates the strip")
        slider.isVertical = true
        slider.cancelScroll()
        slider.doubleValue = 0.5
        func expectStripSwipe(_ events: [NSEvent], _ label: String) {
            strip.received.removeAll()
            target.callbacks = []
            for event in events { slider.scrollWheel(with: event) }
            let delivered = strip.received.elementsEqual(events) {
                $0.phase == $1.phase && $0.momentumPhase == $1.momentumPhase
                    && $0.scrollingDeltaX == $1.scrollingDeltaX && $0.scrollingDeltaY == $1.scrollingDeltaY
            }
            suite.expect(slider.doubleValue == 0.5 && delivered && target.callbacks == [true, false],
                         "\(label) (level \(slider.doubleValue), horizontal deltas \(strip.received.map(\.scrollingDeltaX)), edits \(target.callbacks))")
        }
        expectStripSwipe([event(.began), event(.changed, sideways: -40), event(.changed, sideways: -40), event(.ended)],
                        "a sideways swipe reaches the strip with its begin and leaves the level alone")
        expectStripSwipe([event(.began), event(.changed, sideways: 5), event(.changed, delta: 6),
                          event(.changed, delta: 24), event(.ended), event(nil, delta: -4),
                          event(nil, sideways: 12, momentum: .begin), event(nil, momentum: .end)],
                        "the strip gets the held horizontal travel, the vertical turn, the lift and all of its tail")
        expectStripSwipe([event(.began, sideways: -2), event(.changed, sideways: -1), event(.ended),
                          event(nil, sideways: -8, momentum: .begin), event(nil, momentum: .end)],
                        "a short sideways flick reaches the strip even when the fingers lift below the threshold")

        slider.scrollWheel(with: event(.began, sideways: 3))
        slider.cancelScroll()
        expectStripSwipe([event(.began), event(.changed, sideways: -12), event(.cancelled)],
                        "a new swipe never replays movement left by a cancelled edit")
        slider.isVertical = false
        document.setFrameSize(NSSize(width: 80, height: 50))
        suite.expect(Route.sidewaysStrip(at: slider) == nil && Route.sidewaysStrip(at: document) == nil,
                     "slider priority is independent of whether the app list overflows")
    }
}
