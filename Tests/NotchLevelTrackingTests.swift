// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Hosts the complete production representable and sends native input to its
/// NSSlider. The window stays hidden; mouse events enter only this process's
/// tracking queue. Bindings record values instead of seeking or writing hardware.
/// This covers AppKit delivery after hit testing, not physical input or window
/// activation. The fixture never posts CGEvents to another application.
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
        func point(_ fraction: Double) -> NSPoint {
            let p = CGFloat(fraction)
            let local = vertical
                ? NSPoint(x: track.midX, y: slider.isFlipped ? track.maxY - p * length : track.minY + p * length)
                : NSPoint(x: track.minX + p * length, y: track.midY)
            return slider.convert(local, to: nil)
        }
        var eventNumber = 0
        func mouse(_ type: NSEvent.EventType, _ fraction: Double) -> NSEvent? {
            eventNumber += 1
            return NSEvent.mouseEvent(with: type, location: point(fraction), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: eventNumber, clickCount: type == .leftMouseDragged ? 0 : 1,
                                      pressure: type == .leftMouseUp ? 0 : 1)
        }
        func gesture(from start: Double, to end: Double? = nil) {
            guard let down = mouse(.leftMouseDown, start),
                  let emergencyRelease = mouse(.leftMouseUp, end ?? start) else {
                suite.expect(false, "\(name): native mouse-down and mouse-up events can be constructed")
                return
            }
            let enabled = slider.isEnabled
            var postedDrag = false
            var postedRelease = false
            var writesBeforeDrag = 0
            var dragDeadline = Date.distantFuture
            // Do not offer a queued mouse-up before AppKit has handled the
            // synthetic drag. Deliver during the native tracking loop, then
            // wait for its action before releasing the button.
            let delivery = Timer(timeInterval: 0.02, repeats: true) { timer in
                MainActor.assumeIsolated {
                    if let end, !postedDrag {
                        suite.expect(state.edits == [true] && state.commits.isEmpty,
                                     "\(name): the native edit is open before delivering a drag")
                        guard let drag = mouse(.leftMouseDragged, end) else {
                            suite.expect(false, "\(name): a native drag event can be constructed")
                            NSApp.postEvent(emergencyRelease, atStart: false)
                            timer.invalidate()
                            return
                        }
                        writesBeforeDrag = state.values.count
                        dragDeadline = Date().addingTimeInterval(0.5)
                        postedDrag = true
                        NSApp.postEvent(drag, atStart: false)
                        return
                    }
                    if postedDrag {
                        let consumed = state.values.count > writesBeforeDrag
                        if !consumed && Date() < dragDeadline { return }
                        suite.expect(consumed,
                                     "\(name): AppKit must act on the posted drag before release; values \(state.values)")
                        suite.expect(state.edits == [true] && state.commits.isEmpty,
                                     "\(name): a native drag stays in one edit until mouse-up")
                    }
                    let up = mouse(.leftMouseUp, end ?? start)
                    suite.expect(up != nil, "\(name): a native mouse-up event can be constructed")
                    postedRelease = true
                    NSApp.postEvent(up ?? emergencyRelease, atStart: false)
                    timer.invalidate()
                }
            }
            RunLoop.main.add(delivery, forMode: .eventTracking)
            // Disabled controls return without entering tracking. Cancel their
            // delivery timer, and discard any remaining events from this process.
            defer {
                delivery.invalidate()
                NSApp.discardEvents(matching: [.leftMouseDragged, .leftMouseUp], before: nil)
            }
            slider.mouseDown(with: down)
            if enabled {
                suite.expect(postedRelease && (end == nil || postedDrag),
                             "\(name): native tracking consumed the scheduled gesture")
            }
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
            gesture(from: fraction)
            expectEdit(fraction, "click at \(fraction)")
        }
        for (start, end) in [(0.25, 0.75), (0.75, 0.25), (0.5, -0.2), (0.5, 1.2)] {
            reset()
            gesture(from: start, to: end)
            expectEdit(end, "drag from \(start) to \(end)")
        }

        // The preceding drag must leave editing closed for native keyboard
        // input, which has no cell start/stop-tracking callbacks.
        reset()
        let arrow = vertical ? "\u{F700}" : "\u{F703}"
        guard let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.numericPad, .function],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: arrow, charactersIgnoringModifiers: arrow,
                                         isARepeat: false, keyCode: vertical ? 126 : 124) else {
            suite.expect(false, "\(name): a native arrow event can be constructed")
            return
        }
        let focused = window.makeFirstResponder(slider)
        suite.expect(focused && window.firstResponder === slider,
                     "\(name): the native slider becomes the keyboard responder without showing its window")
        // Arrow keys first follow the key-equivalent path, then normal window
        // dispatch when unhandled. Calling keyDown directly bypasses that path.
        if !window.performKeyEquivalent(with: key) { window.sendEvent(key) }
        suite.expect(state.value > maximum / 2 && state.value <= maximum
                     && state.edits == [true, false] && state.commits == [state.value] && !state.wroteOutsideEdit,
                     "\(name): an arrow after dragging increments and commits once, got \(state.value), \(state.edits)")

        reset(disabled: true)
        suite.expect(!slider.isEnabled, "\(name): SwiftUI disabling reaches the native control")
        gesture(from: 0.25, to: 0.75)
        suite.expect(state.value == maximum / 2 && slider.doubleValue == maximum / 2
                     && state.values.isEmpty && state.edits.isEmpty && state.commits.isEmpty,
                     "\(name): disabled mouse input cannot change or commit a value")
        reset()
        gesture(from: 0.75)
        expectEdit(0.75, "click after re-enabling")
    }
}
