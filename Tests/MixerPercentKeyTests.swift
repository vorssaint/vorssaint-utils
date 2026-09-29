// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The mixer level field's production Escape monitor runs against plain
/// doubles. No field is shown, no monitor is installed and no key is posted.
enum MixerPercentKeyTests {
    struct NSEvent {
        struct EventTypeMask: OptionSet {
            let rawValue: UInt64
            static let keyDown = Self(rawValue: 1 << 10)
        }
        static var handler: ((Self) -> Self?)?
        let keyCode: UInt16
        let window: NSWindow?
        static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (Self) -> Self?) -> Any? {
            self.handler = handler
            return 1
        }
    }
    final class NSTextView {
        var composing = false
        func hasMarkedText() -> Bool { composing }
    }
    final class NSWindow { var firstResponder: AnyObject? }
    final class MixerPercentNativeTextField { var window: NSWindow? }
    static var cancels = 0

    class Fixture {
        var isActive = true
        var isFinishing = false
        var escapeMonitor: Any?
        var field: MixerPercentNativeTextField?
        var onCancel: () -> Void = { MixerPercentKeyTests.cancels += 1 }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSEvent.handler = nil
            cancels = 0
        }
        let panel = NSWindow()
        let settings = NSWindow()
        let editor = NSTextView()
        panel.firstResponder = editor
        settings.firstResponder = NSTextView()
        let field = MixerPercentNativeTextField()
        field.window = panel
        let coordinator = Coordinator()
        coordinator.field = field
        coordinator.startMonitoringEscape()
        suite.expect(NSEvent.handler?(NSEvent(keyCode: 53, window: settings)) != nil && cancels == 0,
                     "Esc in another app window such as Settings stays there and keeps the level being typed")
        field.window = nil
        suite.expect(NSEvent.handler?(NSEvent(keyCode: 53, window: nil)) != nil && cancels == 0,
                     "Esc with no key window never cancels a level field that left its window")
        field.window = panel
        editor.composing = true
        suite.expect(NSEvent.handler?(NSEvent(keyCode: 53, window: panel)) != nil && cancels == 0,
                     "a composing input method keeps Esc in the mixer level field")
        editor.composing = false
        suite.expect(NSEvent.handler?(NSEvent(keyCode: 53, window: panel)) == nil && cancels == 1,
                     "Esc cancels the level being typed once composition ends")
    }
}
