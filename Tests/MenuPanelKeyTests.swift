// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

/// The menu bar panel's production key handler runs against plain doubles.
/// No popover is shown, no monitor is installed and no key is posted.
enum MenuPanelKeyTests {
    struct NSEvent {
        struct ModifierFlags: OptionSet {
            let rawValue: Int
            static let command = Self(rawValue: 1)
            static let control = Self(rawValue: 2)
            static let option = Self(rawValue: 4)
        }
        let keyCode: UInt16
        let window: NSWindow?
        var modifierFlags: ModifierFlags = []
    }
    class NSResponder { func keyDown(with event: NSEvent) {} }
    final class NSTextView: NSResponder {
        var composing = false
        func hasMarkedText() -> Bool { composing }
    }
    final class NSTextField: NSResponder {}
    final class NSWindow {
        var firstResponder: NSResponder?
        func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSTextView? { nil }
    }
    final class View { var window: NSWindow? }
    final class Controller { let view = View() }
    final class Popover {
        var isShown = true
        let contentViewController: Controller? = Controller()
    }
    final class PanelInteractionState {
        static let shared = PanelInteractionState()
        var viewKeepsPopoverOpen = false
    }
    struct Application { var keyWindow: NSWindow? }
    static let NSApp = Application()

    class Fixture {
        let popover = Popover()
        var closeReasons: [PanelCloseReason] = []
        func closePopover(reason: PanelCloseReason) {
            closeReasons.append(reason)
            popover.isShown = false
        }
    }

    static func run(_ suite: TestSuite) {
        let host = Host()
        let window = NSWindow()
        let field = NSTextView()
        window.firstResponder = field
        host.popover.contentViewController?.view.window = window
        let escape = NSEvent(keyCode: UInt16(kVK_Escape), window: window)
        field.composing = true
        suite.expect(host.handlePopoverKeyDown(escape) != nil && host.popover.isShown && host.closeReasons.isEmpty,
                     "a composing input method keeps Esc in a panel field such as the Homebrew search")
        field.composing = false
        suite.expect(host.handlePopoverKeyDown(escape) == nil && !host.popover.isShown
                     && host.closeReasons == [.escape],
                     "Esc closes the panel once composition ends")
    }
}
