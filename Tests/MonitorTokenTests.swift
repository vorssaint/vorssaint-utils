// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Clicks the production control inside its own off-screen window. Input is
/// delivered to that window only, without changing real preferences.
enum MonitorTokenTests {
    private enum Variant: CaseIterable { case plain, block, options }

    private final class State: ObservableObject {
        @Published var included = false
        @Published var available = true
        @Published var disabled = false
        var switches = 0
        var selections = 0
        var optionsPresented = 0

        var binding: Binding<Bool> {
            Binding(get: { self.included }, set: {
                self.included = $0
                self.switches += 1
            })
        }
    }

    private struct Host: View {
        @ObservedObject var state: State
        let variant: Variant

        private var select: (() -> Void)? {
            guard variant == .block else { return nil }
            return { state.selections += 1 }
        }

        var body: some View {
            MonitorToken(symbol: "cpu", title: "CPU", included: state.binding,
                         available: state.available,
                         options: variant == .options
                            ? AnyView(Text("Graphs").onAppear { state.optionsPresented += 1 }) : nil,
                         optionsSummary: "Graphs", large: variant == .block, select: select)
                .disabled(state.disabled)
        }
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        for variant in Variant.allCases { check(variant, suite: suite) }
    }

    private static func check(_ variant: Variant, suite: TestSuite) {
        let width: CGFloat = 210
        let height: CGFloat = variant == .block ? 40 : 28
        let state = State()
        let host = NSHostingView(rootView: Host(state: state, variant: variant))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        settle()

        func click(_ point: NSPoint) {
            state.switches = 0
            state.selections = 0
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil,
                                                     eventNumber: 1, clickCount: 1, pressure: 1) else {
                    suite.expect(false, "a monitor control click has an event")
                    return
                }
                window.sendEvent(event)
                settle(0.02)
            }
            settle()
        }

        let name = NSPoint(x: 80, y: height / 2)
        let checkmark = NSPoint(x: 15, y: height / 2)
        let trailing = NSPoint(x: width - 10, y: height / 2)
        var nameAreas: [(String, NSPoint)] = [
            ("name", name),
            ("left padding", NSPoint(x: 2, y: height / 2)),
            ("top padding", NSPoint(x: 80, y: height - 2)),
            ("bottom padding", NSPoint(x: 80, y: 2))
        ]
        if variant != .options { nameAreas.append(("right padding", NSPoint(x: width - 2, y: height / 2))) }
        for (area, point) in nameAreas {
            state.included = false
            settle()
            click(point)
            suite.expect(variant == .block
                         ? state.selections == 1 && state.switches == 0 && !state.included
                         : state.selections == 0 && state.switches == 1 && state.included,
                         "the \(variant) control's \(area) performs the name's action exactly once")
        }
        for initiallyIncluded in [false, true] {
            state.included = initiallyIncluded
            settle()
            click(checkmark)
            suite.expect(state.switches == 1 && state.selections == 0 && state.included != initiallyIncluded,
                         "the \(variant) checkmark only toggles inclusion from \(initiallyIncluded)")
        }
        state.included = true
        settle()
        click(name)
        suite.expect(variant == .block
                     ? state.selections == 1 && state.switches == 0 && state.included
                     : state.selections == 0 && state.switches == 1 && !state.included,
                     "the \(variant) name keeps its action when already included")

        let disabledAreas = nameAreas + [("checkmark", checkmark), ("trailing control", trailing)]
        for disabledByParent in [false, true] {
            state.included = true
            state.available = disabledByParent
            state.disabled = disabledByParent
            settle()
            for (area, point) in disabledAreas {
                let presentations = state.optionsPresented
                click(point)
                suite.expect(state.switches == 0 && state.selections == 0 && state.included
                             && state.optionsPresented == presentations,
                             "the disabled \(variant) control ignores its \(area), parent=\(disabledByParent)")
            }
        }

        guard variant == .options else { return }
        state.available = true
        state.disabled = false
        state.included = false
        settle()
        click(trailing)
        suite.expect(state.switches == 0 && state.selections == 0 && state.optionsPresented == 0,
                     "options stay disabled while their reading is hidden")
        state.included = true
        settle()
        click(trailing)
        let deadline = Date().addingTimeInterval(1)
        while state.optionsPresented == 0, Date() < deadline { settle() }
        suite.expect(state.optionsPresented > 0 && state.switches == 0 && state.selections == 0 && state.included,
                     "the options button opens its popover without switching the reading")
    }

    private static func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
