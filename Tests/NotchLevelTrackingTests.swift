// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Native contract after input delivery, using the complete production
/// representable, cell and coordinator in a hidden window. Clicks enter through
/// mouseDown. Drags call the cell's public start/continue/stop methods, with the
/// control dispatching its action after each update as a tracking loop would.
/// AppKit computes every value; the fixture never assigns a mapped drag value.
/// Keyboard checks invoke native movement commands, not keyDown transport.
/// This does not verify physical input, event routing or window activation.
/// Bindings record values instead of seeking or writing hardware; no CGEvents
/// are posted outside the test process.
enum NotchLevelTrackingTests {
    private final class State: ObservableObject {
        @Published var value = 0.0
        @Published var disabled = false
        var values: [Double] = []
        var edits: [Bool] = []
        var commits: [Double] = []
        var wroteOutsideEdit = false

        var binding: Binding<Double> {
            Binding(get: { self.value }, set: {
                self.wroteOutsideEdit = self.wroteOutsideEdit || self.edits.last != true
                self.value = $0
                self.values.append($0)
            })
        }

        func editing(_ editing: Bool) {
            edits.append(editing)
            if !editing { commits.append(value) }
        }

        func clearActions() {
            values = []
            edits = []
            commits = []
            wroteOutsideEdit = false
        }
    }

    private struct Host: View {
        @ObservedObject var state: State
        let vertical: Bool
        let maximum: Double
        let thickness: CGFloat?

        var body: some View {
            NotchLevelSlider(value: state.binding, label: "test level", range: 0...maximum,
                             vertical: vertical, trackThickness: thickness,
                             marker: maximum == 2 ? 1 : nil,
                             scrollable: maximum != 300, onEditingChanged: state.editing)
                .disabled(state.disabled)
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            check(suite, vertical: false, maximum: 1, thickness: 8, size: NSSize(width: 202, height: 24))
            check(suite, vertical: false, maximum: 300, thickness: nil, size: NSSize(width: 302, height: 10))
            check(suite, vertical: true, maximum: 1, thickness: 28, size: NSSize(width: 40, height: 182))
            check(suite, vertical: true, maximum: 2, thickness: 28, size: NSSize(width: 40, height: 182))
        }
    }

    @MainActor private static func check(_ suite: TestSuite, vertical: Bool, maximum: Double,
                                         thickness: CGFloat?, size: NSSize) {
        let state = State()
        state.value = maximum / 2
        let host = NSHostingView(rootView: Host(state: state, vertical: vertical,
                                               maximum: maximum, thickness: thickness))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.setFrameSize(size)
        defer {
            window.contentView = nil
            window.close()
        }
        func settle(until ready: () -> Bool) {
            let deadline = Date().addingTimeInterval(0.25)
            repeat {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
                host.layoutSubtreeIfNeeded()
                if ready() { return }
            } while Date() < deadline
        }
        func findSlider(_ view: NSView) -> NSSlider? {
            if let slider = view as? NSSlider { return slider }
            return view.subviews.lazy.compactMap { findSlider($0) }.first
        }
        settle { findSlider(host) != nil }
        guard let slider = findSlider(host), let cell = slider.cell as? NSSliderCell else {
            suite.expect(false, "the production level representable creates an NSSlider and cell")
            return
        }
        // Initialize native drawing geometry without ordering the window on screen.
        guard let bitmap = slider.bitmapImageRepForCachingDisplay(in: slider.bounds) else {
            suite.expect(false, "the native slider can draw into an offscreen bitmap")
            return
        }
        slider.cacheDisplay(in: slider.bounds, to: bitmap)
        let track = cell.barRect(flipped: slider.isFlipped)
        let length = vertical ? track.height : track.width
        guard length > 0 else {
            suite.expect(false, "the hosted slider has a nonempty track")
            return
        }
        let name = "\(vertical ? "vertical" : "horizontal") level 0...\(maximum)"
        let tolerance = maximum * 0.5 / Double(length)
        suite.expect(slider.isVertical == vertical && slider.minValue == 0 && slider.maxValue == maximum,
                     "\(name): the production representable configures orientation and range")
        suite.expect(!window.isVisible, "native slider contracts never show their window")

        func reset(_ fraction: Double = 0.5, disabled: Bool = false) {
            state.value = fraction * maximum
            state.disabled = disabled
            settle { slider.doubleValue == state.value && slider.isEnabled == !disabled }
            suite.expect(slider.doubleValue == state.value && slider.isEnabled == !disabled,
                         "\(name): the binding and enabled state settle before native input")
            state.clearActions()
        }
        func localPoint(_ fraction: Double) -> NSPoint {
            let p = CGFloat(fraction)
            return vertical
                ? NSPoint(x: track.midX, y: slider.isFlipped ? track.maxY - p * length : track.minY + p * length)
                : NSPoint(x: track.minX + p * length, y: track.midY)
        }
        var eventNumber = 0
        func mouse(_ type: NSEvent.EventType, _ fraction: Double) -> NSEvent? {
            eventNumber += 1
            return NSEvent.mouseEvent(with: type, location: slider.convert(localPoint(fraction), to: nil), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: eventNumber, clickCount: 1,
                                      pressure: type == .leftMouseUp ? 0 : 1)
        }
        func click(at fraction: Double) {
            guard let down = mouse(.leftMouseDown, fraction), let up = mouse(.leftMouseUp, fraction) else {
                suite.expect(false, "\(name): native mouse-down and mouse-up events can be constructed")
                return
            }
            NSApp.postEvent(up, atStart: false)
            // A disabled control does not consume the release. Keep this
            // process's queue clear before the next case.
            defer { NSApp.discardEvents(matching: [.leftMouseUp], before: nil) }
            slider.mouseDown(with: down)
        }
        func drag(from start: Double, to end: Double) {
            let first = localPoint(start)
            let last = localPoint(end)
            guard cell.startTracking(at: first, in: slider) else {
                suite.expect(false, "\(name): the native cell starts continuous tracking")
                return
            }
            defer { cell.stopTracking(last: first, current: last, in: slider, mouseIsUp: true) }
            suite.expect(state.edits == [true] && state.commits.isEmpty,
                         "\(name): the production cell opens one edit before the first value")
            // These public callbacks calculate the native slider value, but
            // outside NSControl's event loop they do not dispatch target/action.
            // Send the real control's action without calculating or assigning
            // the value, so the production coordinator still owns the binding.
            suite.expect(slider.sendAction(slider.action, to: slider.target),
                         "\(name): the control dispatches its initial tracking value")
            suite.expect(cell.continueTracking(last: first, current: last, in: slider),
                         "\(name): native tracking continues, including beyond the ends")
            suite.expect(slider.sendAction(slider.action, to: slider.target),
                         "\(name): the control dispatches its updated tracking value")
            suite.expect(state.edits == [true] && state.commits.isEmpty && !state.wroteOutsideEdit,
                         "\(name): continuous updates do not finish or restart the edit")
        }
        func expectEdit(_ fraction: Double, _ action: String) {
            let expected = min(1, max(0, fraction)) * maximum
            suite.expectClose(slider.doubleValue, expected, "\(name): \(action) follows the pointer", tol: tolerance)
            suite.expectClose(state.value, expected, "\(name): \(action) updates the binding", tol: tolerance)
            suite.expect(state.edits == [true, false] && state.commits.count == 1 && !state.wroteOutsideEdit,
                         "\(name): \(action) has one complete edit, got \(state.edits) and \(state.commits)")
            if let committed = state.commits.first {
                suite.expectClose(committed, expected, "\(name): \(action) commits the final value", tol: tolerance)
            }
            suite.expect(!state.values.isEmpty && state.values.allSatisfy { $0.isFinite && (0...maximum).contains($0) },
                         "\(name): \(action) only publishes finite values within its range")
        }

        // 0.525 is inside the old invisible knob near the starting value. It
        // must jump to the pointer as any other click does, rather than grab
        // the old value with an offset. Quarter points expose the old scale.
        for fraction in [0.0, 0.1, 0.25, 0.525, 0.75, 0.9, 1.0] {
            reset()
            click(at: fraction)
            expectEdit(fraction, "click at \(fraction)")
        }
        for (start, end) in [(0.25, 0.75), (0.75, 0.25), (0.5, -0.2), (0.5, 1.2)] {
            reset()
            drag(from: start, to: end)
            expectEdit(end, "drag from \(start) to \(end)")
        }

        // The preceding drag must leave editing closed for native movement
        // commands, which have no cell start/stop-tracking callbacks. Calling
        // the command tests its value and action semantics, not keyDown routing
        // through an inactive window.
        reset()
        let focused = window.makeFirstResponder(slider)
        suite.expect(focused && window.firstResponder === slider,
                     "\(name): the native slider becomes the keyboard responder without showing its window")
        if vertical { slider.moveUp(nil) } else { slider.moveRight(nil) }
        suite.expect(state.value > maximum / 2 && state.value <= maximum
                     && state.edits == [true, false] && state.commits == [state.value] && !state.wroteOutsideEdit,
                     "\(name): a native movement command after dragging increments and commits once, got \(state.value), \(state.edits)")

        reset(disabled: true)
        suite.expect(!slider.isEnabled, "\(name): SwiftUI disabling reaches the native control")
        click(at: 0.25)
        click(at: 0.75)
        suite.expect(state.value == maximum / 2 && slider.doubleValue == maximum / 2
                     && state.values.isEmpty && state.edits.isEmpty && state.commits.isEmpty,
                     "\(name): disabled mouse input cannot change or commit a value")
        reset()
        click(at: 0.75)
        expectEdit(0.75, "click after re-enabling")

        guard vertical else { return }
        // The mixer binds these ranges to output/microphone gain and app
        // volume. Here every write by the production coordinator stays in State.
        var time: CGEventTimestamp = 10_000_000_000
        func scroll(_ phase: CGScrollPhase?, dx: Int32 = 0, dy: Int32 = 0,
                    momentum: CGMomentumScrollPhase = .none, units: CGScrollEventUnit = .pixel) {
            time += 10_000_000
            slider.scrollWheel(with: SliderScrollRoutingTests.event(phase, delta: dy, sideways: dx,
                                                                     momentum: momentum, units: units, timestamp: time))
        }
        reset()
        scroll(.began, dx: 5)
        scroll(.changed, dy: 6)
        scroll(.changed, dy: 24)
        scroll(.ended)
        scroll(nil, dy: -4)
        scroll(nil, dx: 12, momentum: .begin)
        scroll(nil, momentum: .end)
        suite.expect(state.value == maximum / 2 && state.values.isEmpty,
                     "\(name): a sideways swipe, its vertical tail and momentum never write the audio binding")
        scroll(nil, dy: 1, units: .line)
        suite.expectClose(abs(state.value - maximum / 2), maximum * 0.05,
                          "\(name): an independent mouse wheel tick still adjusts the volume during the lift gap")

        reset()
        scroll(.began, dy: 4)
        scroll(.changed, dy: 16)
        scroll(.changed, dx: 40)
        scroll(.ended)
        scroll(nil, dy: 8)
        scroll(nil, dy: 20, momentum: .begin)
        scroll(nil, momentum: .end)
        suite.expectClose(abs(state.value - maximum / 2), maximum * 0.1,
                          "\(name): a vertical swipe includes its first four points and ignores sideways drift")
        suite.expect(state.values.count == 1 && !state.wroteOutsideEdit,
                     "\(name): the volume binding receives one edit and no write from the tail")
        if maximum == 1 {
            reset(disabled: true)
            scroll(.began, dy: 20)
            scroll(.ended)
            scroll(nil, dy: 1, units: .line)
            suite.expect(state.value == 0.5 && state.values.isEmpty,
                         "the disabled microphone fader leaves its simulated input gain alone")
        }
    }
}
