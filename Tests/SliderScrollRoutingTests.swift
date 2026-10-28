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

    private static func event(_ phase: CGScrollPhase, delta: Int32 = 0) -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                         wheel1: delta, wheel2: 0, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
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

        let strip = NSScrollView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
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
        document.setFrameSize(NSSize(width: 80, height: 50))
        suite.expect(Route.sidewaysStrip(at: slider) == nil && Route.sidewaysStrip(at: document) == nil,
                     "slider priority is independent of whether the app list overflows")
    }
}
