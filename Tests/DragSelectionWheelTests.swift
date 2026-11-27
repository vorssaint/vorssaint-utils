// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// A real text view runs its own selection loop while the drag, wheel and
/// release events arrive one by one, as they would from the mouse.
enum DragSelectionWheelTests {
    private final class Panel: NSPanel {
        var routesWheel = true
        override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                                inMode mode: RunLoop.Mode, dequeue deqFlag: Bool) -> NSEvent? {
            guard routesWheel else {
                return super.nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: deqFlag)
            }
            return DragSelectionWheel.nextEvent(matching: mask, dequeue: deqFlag, next: {
                super.nextEvent(matching: $0, until: expiration, inMode: mode, dequeue: deqFlag)
            }, scroll: { ($0.window ?? self).sendEvent($0) })
        }
    }

    /// Posts one event per tick while the selection loop runs.
    private final class Feeder: NSObject {
        var events: [NSEvent]
        init(events: [NSEvent]) { self.events = events }
        @objc func post(_ timer: Timer) {
            guard !events.isEmpty else { timer.invalidate(); return }
            NSApp.postEvent(events.removeFirst(), atStart: false)
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.prohibited)
            defer { NSApp.setActivationPolicy(previousPolicy) }
            let routed = select(routesWheel: true)
            let stock = select(routesWheel: false)
            suite.expect(routed.scrolled > 0 && routed.selected > stock.selected,
                         "the wheel scrolls the text while it is being selected, and the selection follows")
            suite.expect(stock.scrolled == 0,
                         "without routing, AppKit's selection loop leaves the wheel waiting for the release")
        }
        passThrough(suite)
    }

    /// Requests that are not a drag-tracking loop's are left exactly as asked.
    private static func passThrough(_ suite: TestSuite) {
        for (mask, dequeue) in [(NSEvent.EventTypeMask.any, true),
                                ([.leftMouseUp, .leftMouseDragged], false),
                                ([.leftMouseDragged, .scrollWheel], true)] {
            var asked: [NSEvent.EventTypeMask] = []
            _ = DragSelectionWheel.nextEvent(matching: mask, dequeue: dequeue,
                                             next: { asked.append($0); return nil }, scroll: { _ in })
            suite.expect(asked == [mask], "a request for 0x\(String(mask.rawValue, radix: 16)) passes through unchanged")
        }
    }

    @MainActor private static func select(routesWheel: Bool) -> (scrolled: CGFloat, selected: Int) {
        let window = Panel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.routesWheel = routesWheel
        // An event built without a window keeps its screen location, which
        // matches the window's own coordinates at the screen origin.
        window.setFrameOrigin(.zero)
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = window.contentView?.bounds ?? .zero
        window.contentView?.addSubview(scroll)
        // Mouse events reach only an ordered-in window; a clear one is never seen.
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer { window.close() }
        guard let textView = scroll.documentView as? NSTextView else { return (0, 0) }
        textView.string = (1...300).map { "line \($0)" }.joined(separator: "\n")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scroll(.zero)

        let point = NSPoint(x: 150, y: 150)
        func mouse(_ type: NSEvent.EventType, _ location: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        func wheel() -> NSEvent? {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                      wheel1: -5, wheel2: 0, wheel3: 0) else { return nil }
            event.location = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
            return NSEvent(cgEvent: event)
        }
        let feeder = Feeder(events: [mouse(.leftMouseDragged, point), wheel(), wheel(), wheel(),
                                     mouse(.leftMouseUp, point)].compactMap { $0 })
        guard feeder.events.count == 5, let down = mouse(.leftMouseDown, NSPoint(x: 100, y: 150)) else { return (0, 0) }
        let timer = Timer(timeInterval: 0.02, target: feeder, selector: #selector(Feeder.post(_:)),
                          userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
        defer { timer.invalidate() }
        // Returns on the release, before any wheel it left waiting is handled.
        textView.mouseDown(with: down)
        let result = (scroll.contentView.bounds.origin.y, textView.selectedRange().length)
        // Drop whatever the stock loop left in the queue for the next check.
        while NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) != nil {}
        return result
    }
}
