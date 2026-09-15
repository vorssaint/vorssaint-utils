// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

/// Production monitor bodies run against plain value doubles. No windows are
/// shown, no native monitors are installed and no keyboard input is generated.
enum NotchCaptureKeyboardContract {
    class NSPanel {
        var isVisible = true
        var attachedSheet: NSPanel?
        var firstResponder: Any?
    }
    final class NSText {}
    final class ScreenshotOverlayPanel: NSPanel { var overlayView = Overlay() }
    final class Overlay { var isDragging = false }
    enum ShortcutCapture { static var isCapturing = false }
    struct NSEvent {
        struct ModifierFlags: OptionSet {
            let rawValue: Int
            static let command = Self(rawValue: 1)
            static let control = Self(rawValue: 2)
            static let option = Self(rawValue: 4)
            static let shift = Self(rawValue: 8)
            static let deviceIndependentFlagsMask = Self(rawValue: 15)
        }
        struct EventTypeMask: OptionSet {
            let rawValue: Int
            static let keyDown = Self(rawValue: 1)
            static let keyUp = Self(rawValue: 2)
        }
        enum EventType { case keyDown, keyUp }
        let window: NSPanel?
        let keyCode: UInt16
        var modifierFlags: ModifierFlags = []
        var type: EventType = .keyDown
        static var handler: ((Self) -> Self?)?
        static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (Self) -> Self?) -> Any? {
            self.handler = handler
            return 1
        }
        static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (Self) -> Void) -> Any? { nil }
    }
}

enum NotchCaptureKeyboardTests {
    private typealias Contract = NotchCaptureKeyboardContract
    private typealias Event = Contract.NSEvent

    static func run(expect: (Bool, String) -> Void) {
        defer {
            Event.handler = nil
            Contract.ShortcutCapture.isCapturing = false
            Contract.NotchService.shared = Contract.NotchService()
        }
        preview(expect: expect)
        chooser(expect: expect)
    }

    private static func preview(expect: (Bool, String) -> Void) {
        let notch = Contract.NotchService()
        Contract.NotchService.shared = notch
        let preview = Contract.Preview()
        notch.captureID = preview.presentationID
        let panel = notch.presentationWindow!
        preview.attach(panel)
        let commands: [(Int, Event.ModifierFlags, Contract.Preview.Action)] = [
            (kVK_ANSI_E, [], .edit), (kVK_Return, [], .edit), (kVK_Delete, [], .discard),
            (kVK_ForwardDelete, [], .discard), (kVK_ANSI_C, .command, .copy),
            (kVK_ANSI_S, .command, .save), (kVK_Delete, .command, .discard),
        ]
        func check(_ label: String, accepts: Bool) {
            for (key, flags, action) in commands {
                preview.actions = []
                let event = Event(window: panel, keyCode: UInt16(key), modifierFlags: flags)
                let forwarded = Event.handler?(event) != nil
                expect(forwarded == !accepts && preview.actions == (accepts ? [action] : []), label)
            }
        }
        check("visible capture retains its existing keyboard actions", accepts: true)
        for module in NotchModule.allCases where module != .captures {
            notch.selected = module
            check("a hidden capture never edits, copies, saves or discards while another section owns the window", accepts: false)
        }
        notch.selected = .captures
        notch.showingSections = true
        check("section search keeps typing, deletion and clipboard shortcuts", accepts: false)
        notch.showingSections = false
        notch.showingAppPanel = true
        check("the app panel never inherits hidden capture commands", accepts: false)
        notch.showingAppPanel = false
        notch.expanded = false
        check("a collapsed capture cannot consume keyboard input", accepts: false)
        notch.expanded = true
        notch.captureControls = 1
        check("an active chooser cannot trigger actions on the previous capture", accepts: false)
        notch.captureControls = nil
        notch.captureID = UUID()
        check("a replaced preview cannot act on its successor", accepts: false)
        notch.captureID = preview.presentationID
        panel.firstResponder = Contract.NSText()
        check("text editing retains every preview shortcut", accepts: false)
        panel.firstResponder = nil
        panel.attachedSheet = Contract.NSPanel()
        check("a sheet owns input over its parent preview", accepts: false)
        panel.attachedSheet = nil
        Contract.ShortcutCapture.isCapturing = true
        check("shortcut recording cannot execute preview actions", accepts: false)
        Contract.ShortcutCapture.isCapturing = false
        preview.shownInNotch = false
        notch.expanded = false
        check("floating previews retain shortcuts independently of notch state", accepts: true)
        preview.actions = []
        _ = Event.handler?(Event(window: panel, keyCode: UInt16(kVK_Escape)))
        expect(preview.closed && preview.actions.isEmpty, "Escape closes without dispatching a destructive action")
        check("a closed preview ignores late keyboard callbacks", accepts: false)
    }

    private static func chooser(expect: (Bool, String) -> Void) {
        let selection = Contract.Selection()
        let notch = Contract.NotchService()
        Contract.NotchService.shared = notch
        let panel = notch.presentationWindow!
        selection.attach()
        for focused in [false, true] {
            selection.screenCaptureOptions?.hasFocusedControl = focused
            for key in [kVK_Tab, kVK_Space, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow] {
                for phase in [Event.EventType.keyDown, .keyUp] {
                    let event = Event(window: panel, keyCode: UInt16(key), type: phase)
                    expect(Event.handler?(event) != nil, "unhandled navigation and activation keys reach native controls")
                }
            }
        }
        let enter = Event(window: panel, keyCode: UInt16(kVK_Return))
        expect(Event.handler?(enter) != nil && selection.actions.isEmpty,
               "Return activates the focused control instead of taking an unexpected full-screen capture")
        selection.screenCaptureOptions?.hasFocusedControl = false
        expect(Event.handler?(enter) == nil && selection.actions == ["fullDisplay"],
               "Return still captures the display when no control owns it")
        selection.actions = []
        for focused in [false, true] {
            selection.screenCaptureOptions?.hasFocusedControl = focused
            let dragging = Contract.ScreenshotOverlayPanel()
            dragging.overlayView.isDragging = true
            selection.draggingPanel = dragging
            expect(Event.handler?(Event(window: panel, keyCode: UInt16(kVK_Space))) == nil && selection.spaceIsDown,
                   "Space still moves a selection even while a chooser control has focus")
            dragging.overlayView.isDragging = false
            expect(Event.handler?(Event(window: panel, keyCode: UInt16(kVK_Space), type: .keyUp)) == nil && !selection.spaceIsDown,
                   "releasing Space clears movement after the drag has ended")
        }
        expect(Event.handler?(Event(window: panel, keyCode: UInt16(kVK_Escape))) == nil && selection.actions == ["cancel"],
               "Escape retains chooser cancellation while controls are focused")
        selection.actions = []
        selection.screenCaptureOptions?.hasFocusedControl = false
        panel.firstResponder = Contract.NSText()
        expect(Event.handler?(enter) != nil && selection.actions.isEmpty, "a chooser text editor retains Return")
        panel.firstResponder = nil
        let unrelated = Contract.NSPanel()
        expect(Event.handler?(Event(window: unrelated, keyCode: UInt16(kVK_Return))) != nil,
               "capture selection leaves unrelated windows alone")
        let overlay = Contract.ScreenshotOverlayPanel()
        selection.screenCaptureOptions?.controlsInNotch = false
        expect(Event.handler?(Event(window: overlay, keyCode: UInt16(kVK_Return))) == nil && selection.actions == ["fullDisplay"],
               "the original floating chooser keeps full-display capture")
    }
}
