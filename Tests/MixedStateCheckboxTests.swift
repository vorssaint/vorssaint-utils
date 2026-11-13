// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The production representable and coordinator inside a native host. No
/// window is shown; full Settings/panel layout and keyboard focus are separate checks.
enum MixedStateCheckboxTests {
    private typealias Selection = UninstallerSupport.BulkSelection

    private final class Model: ObservableObject {
        @Published var selection: Selection = .none
        @Published var enabled = true
    }

    private struct Host: View {
        @ObservedObject var model: Model
        let onToggle: () -> Void

        var body: some View {
            MixedStateCheckbox(title: "Select all", isOn: model.selection == .all,
                               isMixed: model.selection == .some, isEnabled: model.enabled,
                               onToggle: onToggle)
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { check(suite) }
    }

    @MainActor private static func check(_ suite: TestSuite) {
        _ = NSApplication.shared
        let model = Model()
        var firstCalls = 0
        var replacementCalls = 0
        let host = NSHostingView(rootView: Host(model: model) {
            firstCalls += 1
            model.selection = model.selection.nextInclude ? .all : .none
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        func findButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton { return button }
            return view.subviews.compactMap { findButton(in: $0) }.first
        }
        func settle(until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(0.25)
            repeat {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
                if condition() { return }
            } while Date() < deadline
        }
        settle { findButton(in: host) != nil }
        guard let button = findButton(in: host) else {
            suite.expect(false, "the production checkbox creates a native button")
            return
        }
        suite.expect(button.allowsMixedState && button.isEnabled && button.title == "Select all",
                     "the native checkbox carries its label and supports mixed selection")
        for (selection, native, next, nextNative): (Selection, NSControl.StateValue, Selection, NSControl.StateValue) in [
            (.none, .off, .all, .on), (.some, .mixed, .all, .on), (.all, .on, .none, .off),
        ] {
            let before = firstCalls
            model.selection = selection
            settle { button.state == native }
            suite.expect(button.state == native && firstCalls == before,
                         "a model update renders \(selection) without invoking the action")
            button.performClick(nil)
            settle { button.state == nextNative }
            suite.expect(firstCalls == before + 1 && model.selection == next && button.state == nextNative,
                         "a native click from \(selection) calls back once and renders the new model state")
        }

        let firstBeforeReplacement = firstCalls
        host.rootView = Host(model: model) {
            replacementCalls += 1
            model.selection = model.selection.nextInclude ? .all : .none
        }
        model.selection = .some
        settle { button.state == .mixed }
        suite.expect(findButton(in: host) === button,
                     "updating the callback retains the native control and its coordinator")
        button.performClick(nil)
        settle { button.state == .on }
        suite.expect(firstCalls == firstBeforeReplacement && replacementCalls == 1
                     && model.selection == .all && button.state == .on,
                     "the existing native control calls only the replacement callback")

        model.enabled = false
        settle { !button.isEnabled }
        for (selection, native): (Selection, NSControl.StateValue) in [(.none, .off), (.some, .mixed), (.all, .on)] {
            model.selection = selection
            settle { button.state == native }
            button.performClick(nil)
            settle { button.state == native }
            suite.expect(!button.isEnabled && button.state == native && model.selection == selection
                         && firstCalls == firstBeforeReplacement && replacementCalls == 1,
                         "a disabled native checkbox ignores clicks in \(selection)")
        }
        model.enabled = true
        settle { button.isEnabled }
        button.performClick(nil)
        settle { button.state == .off }
        suite.expect(firstCalls == firstBeforeReplacement && replacementCalls == 2
                     && model.selection == .none && button.state == .off,
                     "reenabling the same checkbox restores one action per click")
    }
}
