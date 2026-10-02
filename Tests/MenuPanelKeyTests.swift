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
        var parent: NSWindow?
        func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSTextView? { nil }
    }
    final class View { var window: NSWindow? }
    final class Controller { let view = View() }
    final class Popover {
        var isShown = true
        var isDetached = false
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
        let window = NSWindow()
        let field = NSTextView()
        window.firstResponder = field
        func shownPanel() -> Host {
            let host = Host()
            host.popover.contentViewController?.view.window = window
            return host
        }
        func panelKeepsEscape(from eventWindow: NSWindow?) -> Bool {
            let host = shownPanel()
            return host.handlePopoverKeyDown(NSEvent(keyCode: UInt16(kVK_Escape), window: eventWindow)) != nil
                && host.popover.isShown && host.closeReasons.isEmpty
        }
        let settings = NSWindow()
        settings.firstResponder = NSTextView()
        suite.expect(panelKeepsEscape(from: settings),
                     "Esc in Settings beside the open panel stays there, for its search field or sheet")
        suite.expect(panelKeepsEscape(from: nil), "Esc with no key window leaves the panel open")
        let picker = NSWindow()
        picker.parent = window
        suite.expect(panelKeepsEscape(from: picker),
                     "Esc in a popover opened from the panel, such as the Keep Awake end time, closes that popover first")

        let host = shownPanel()
        let escape = NSEvent(keyCode: UInt16(kVK_Escape), window: window)
        field.composing = true
        suite.expect(host.handlePopoverKeyDown(escape) != nil && host.popover.isShown && host.closeReasons.isEmpty,
                     "a composing input method keeps Esc in a panel field such as the Homebrew search")
        field.composing = false
        suite.expect(host.handlePopoverKeyDown(escape) == nil && !host.popover.isShown
                     && host.closeReasons == [.escape],
                     "Esc closes the panel once composition ends")
        host.popover.isShown = true
        host.popover.isDetached = true
        suite.expect(host.handlePopoverKeyDown(escape) != nil && host.popover.isShown
                     && host.closeReasons == [.escape],
                     "Esc leaves a panel dragged off the menu bar open")
    }
}
