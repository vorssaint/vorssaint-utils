// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Clicks the Settings alert tile where people click it: the tile's edge,
/// its badge and its limit line switch the alert, the limit's stepper only
/// moves the limit.
enum MonitorAlertTileTests {
    private final class State: ObservableObject {
        @Published var on = false
        @Published var limit = 90
        var switches = 0
    }

    private struct Host: View {
        @ObservedObject var state: State
        var body: some View {
            AlertTile(title: "CPU", symbol: "cpu",
                      isOn: Binding(get: { state.on }, set: { state.on = $0; state.switches += 1 }),
                      limit: .init(label: "Above", value: $state.limit, range: 50...100, step: 5,
                                   formatValue: { "\($0)%" }))
                .frame(width: 200)
        }
    }

    static func run(_ suite: TestSuite) {
        let state = State()
        let host = NSHostingView(rootView: Host(state: state))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 200, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        settle()

        func click(_ point: NSPoint) -> Int {
            let before = state.switches
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 1, clickCount: 1, pressure: 1) else { return -1 }
                window.sendEvent(event)
                settle(0.05)
            }
            settle()
            return state.switches - before
        }
        let bounds = host.bounds
        suite.expect(click(NSPoint(x: 40, y: bounds.height - 40)) == 1 && state.on, "the tile's name switches the alert")
        suite.expect(click(NSPoint(x: bounds.width - 14, y: bounds.height - 14)) == 1 && !state.on,
                     "the badge in the corner switches it")
        suite.expect(click(NSPoint(x: 3, y: bounds.height / 2)) == 1 && state.on, "the tile's edge switches it")
        guard let stepper = descendants(host).first(where: { $0 is NSStepper })
                .map({ $0.convert($0.bounds, to: nil) }) else {
            suite.expect(false, "an alert that is on shows the stepper for its limit")
            return
        }
        suite.expect(click(NSPoint(x: 30, y: stepper.midY)) == 1 && !state.on, "the limit's line switches it")
        _ = click(NSPoint(x: 3, y: bounds.height / 2))
        suite.expect(click(NSPoint(x: stepper.midX, y: stepper.minY + 3)) == 0 && state.on && state.limit == 85,
                     "the stepper moves the limit without switching the alert off")
    }

    private static func settle(_ seconds: TimeInterval = 0.2) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
