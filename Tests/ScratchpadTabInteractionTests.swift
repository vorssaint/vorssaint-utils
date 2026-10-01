// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The generated tab bodies and island button style come from production.
/// Synthetic mouse events go only to an offscreen window with an in-memory model.
enum ScratchpadTabInteractionTests {
    final class Model: ObservableObject {
        @Published var selectedPadID: UUID? = UUID()
        let canClosePad = true
        var renamed: [UUID] = []
        var closed: [UUID] = []
        func selectPad(_ id: UUID) { selectedPadID = id }
    }

    struct Floating: View {
        @ObservedObject var service: Model
        let entry: ScratchpadPad
        @State var hoveredPadID: UUID?
        let text = FeatureStrings.scratchpad(.enUS)
        var body: some View { tabButton(entry).frame(width: 150, height: 60) }
        func presentRename(_ entry: ScratchpadPad) { service.renamed.append(entry.id) }
        func requestClose(_ entry: ScratchpadPad) { service.closed.append(entry.id) }
    }

    struct Island: View {
        typealias NotchButtonStyle = ScratchpadTabInteractionTests.NotchButtonStyle
        @ObservedObject var pad: Model
        let entry: ScratchpadPad
        @State var hoveredPadID: UUID?
        let text = FeatureStrings.scratchpad(.enUS)
        var body: some View { tab(entry).frame(width: 150, height: 60) }
        func presentRename(_ entry: ScratchpadPad) { pad.renamed.append(entry.id) }
        func requestClose(_ entry: ScratchpadPad) { pad.closed.append(entry.id) }
    }

    private final class Window: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    static func run(_ suite: TestSuite) {
        let app = NSApplication.shared
        let previousPolicy = app.activationPolicy()
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        defer { app.setActivationPolicy(previousPolicy) }

        for island in [false, true] {
            let name = island ? "island" : "floating"
            let model = Model()
            let entry = ScratchpadPad(id: UUID(), name: "Sample note", text: "", modifiedAt: nil)
            let root = island ? AnyView(Island(pad: model, entry: entry))
                : AnyView(Floating(service: model, entry: entry))
            let host = NSHostingView(rootView: root)
            let window = Window(contentRect: NSRect(x: -10000, y: -10000, width: 150, height: 60),
                                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            settle(0.3)
            host.layoutSubtreeIfNeeded()

            // Check before the system's double-click timeout, not after it:
            // the old title gesture eventually selected, but held up every click.
            let responseWindow = min(0.09, NSEvent.doubleClickInterval / 4)
            click(60, count: 1, in: window, responseWindow: responseWindow)
            suite.expect(model.selectedPadID == entry.id,
                         "\(name): a title click selects before the double-click timeout")
            suite.expect(model.renamed.isEmpty && model.closed.isEmpty,
                         "\(name): a single title click neither renames nor closes")
            settle(NSEvent.doubleClickInterval + 0.1)

            // Start a double click on a different, unselected tab as well.
            model.selectedPadID = UUID()
            settle(0.1)
            click(60, count: 1, in: window, responseWindow: responseWindow)
            suite.expect(model.selectedPadID == entry.id && model.renamed.isEmpty,
                         "\(name): the first half of a double click selects immediately")
            click(60, count: 2, in: window, responseWindow: responseWindow)
            suite.expect(model.renamed == [entry.id] && model.closed.isEmpty,
                         "\(name): the second click renames exactly the clicked tab")
            settle(NSEvent.doubleClickInterval + 0.1)

            // The selected tab's close target is separate from its title.
            click(108, count: 1, in: window, responseWindow: responseWindow)
            suite.expect(model.closed == [entry.id] && model.renamed == [entry.id],
                         "\(name): close stays immediate and does not trigger rename")
        }
    }

    private static func settle(_ duration: TimeInterval) {
        let deadline = Date().addingTimeInterval(duration)
        repeat {
            while let event = NSApp.nextEvent(matching: .any, until: Date(),
                                              inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        } while Date() < deadline
    }

    private static func click(_ x: CGFloat, count: Int, in window: NSWindow,
                              responseWindow: TimeInterval) {
        let app = NSApplication.shared
        let timestamp = ProcessInfo.processInfo.systemUptime
        // Queue both events before dispatch: a button can track mouse-up from
        // inside its mouse-down handler. No events are posted to other apps.
        for (type, delta) in [(NSEvent.EventType.leftMouseDown, 0.0), (.leftMouseUp, 0.025)] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 30),
                                          modifierFlags: [], timestamp: timestamp + delta,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: count, clickCount: count,
                                          pressure: type == .leftMouseDown ? 1 : 0)!
            app.postEvent(event, atStart: false)
        }
        let deadline = Date().addingTimeInterval(responseWindow)
        while Date() < deadline {
            if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.005),
                                         inMode: .default, dequeue: true) {
                if event.windowNumber == window.windowNumber {
                    window.sendEvent(event)
                } else {
                    app.sendEvent(event)
                }
            }
            settle(0.005)
        }
    }
}
