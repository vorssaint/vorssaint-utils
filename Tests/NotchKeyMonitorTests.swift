// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's production event monitor runs against plain doubles. No
/// window is shown, no native monitor is installed and no key is posted.
enum NotchKeyMonitorTests {
    struct NSEvent {
        struct ModifierFlags: OptionSet {
            let rawValue: Int
            static let command = Self(rawValue: 1)
            static let control = Self(rawValue: 2)
            static let option = Self(rawValue: 4)
            static let shift = Self(rawValue: 8)
        }
        enum EventType: UInt { case leftMouseDown = 1, rightMouseDown = 3, keyDown = 10, otherMouseDown = 25 }
        struct EventTypeMask: OptionSet {
            let rawValue: UInt64
            static let leftMouseDown = Self(rawValue: 1 << 1)
            static let rightMouseDown = Self(rawValue: 1 << 3)
            static let keyDown = Self(rawValue: 1 << 10)
            static let otherMouseDown = Self(rawValue: 1 << 25)
        }
        static let mouseLocation = CGPoint.zero
        static var handler: ((Self) -> Self?)?
        var type = EventType.keyDown
        let window: Panel?
        let keyCode: UInt16
        var modifierFlags: ModifierFlags = []
        var charactersIgnoringModifiers: String?
        static func addGlobalMonitorForEvents(matching: EventTypeMask, handler: @escaping (Self) -> Void) -> Any? { nil }
        static func addLocalMonitorForEvents(matching: EventTypeMask, handler: @escaping (Self) -> Self?) -> Any? {
            self.handler = handler
            return 1
        }
    }
    final class Panel { var firstResponder: AnyObject? }
    final class NSTextView {
        let isFieldEditor: Bool
        let delegate: AnyObject? = nil
        var composing = false
        init(isFieldEditor: Bool) { self.isFieldEditor = isFieldEditor }
        func hasMarkedText() -> Bool { composing }
    }
    final class MixerPercentNativeTextField {}
    enum PlainTextEditor { static func findBarHasKeyboard(in window: Panel?) -> Bool { false } }
    final class Host { func contains(_ point: CGPoint) -> Bool { false } }
    final class AppDelegate { func isOverStatusItem(_ point: CGPoint) -> Bool { false } }
    struct Application { let delegate: AnyObject? = nil }
    static let NSApp = Application()
    enum AssistiveKeyboard { static func ownsCocoaPoint(_ point: CGPoint) -> Bool { false } }
    /// What each Escape did: the gallery toggled, Tools took it or the island closed.
    static var actions: [String] = []
    final class Launcher {
        var isEditing = false
        var visibleItems = [0, 1, 2]
        func handlePanelKey(_ event: NSEvent, flow: QuickToolsSupport.GridFlow) -> NSEvent? {
            NotchKeyMonitorTests.actions.append("tools")
            return nil
        }
    }
    enum QuickLauncherService { static let shared = Launcher() }

    class State {
        var eventMonitors: [Any] = []
        var clickedSinceOpening = false
        var keepsWorkingSurface = false
        let panel: Panel? = Panel()
        var windowHost: Host? = Host()
        var captureControls: Int?
        var modules = NotchModule.allCases
        var selected = NotchModule.controls
        var showingAppPanel = false
        var showingSections = false
        var geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1470, height: 956),
                                     safeAreaTop: 32, cameraWidth: 180)
        func collapse() { NotchKeyMonitorTests.actions.append("collapse") }
        func stepBack() { NotchKeyMonitorTests.actions.append("stepBack") }
        func toggleSections() { NotchKeyMonitorTests.actions.append("sections") }
        func select(_ module: NotchModule) { selected = module }
        func handleSectionKey(_ event: NSEvent) -> Bool { false }
        func handleScratchpadKey(_ event: NSEvent) -> Bool { false }
        func handleClipboardPasteKey(_ event: NSEvent) -> Bool { false }
        func ownsWindow(_ window: Panel?) -> Bool { window === panel }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSEvent.handler = nil
            actions = []
        }
        let service = Service()
        service.installEventMonitors()
        let escape = NSEvent(window: service.panel, keyCode: 53)
        // Each Escape branch, reached from a field that can hold a composing
        // input method: the gallery search, a field in a Tools utility, one
        // in the app panel and the Scratchpad editor.
        let destinations: [(name: String, module: NotchModule, sections: Bool, appPanel: Bool,
                            field: NSTextView, action: String)] = [
            ("the gallery search", .controls, true, false, NSTextView(isFieldEditor: true), "sections"),
            ("a Tools utility", .tools, false, false, NSTextView(isFieldEditor: true), "tools"),
            ("the app panel", .tools, false, true, NSTextView(isFieldEditor: true), "stepBack"),
            ("the Scratchpad editor", .scratchpad, false, false, NSTextView(isFieldEditor: false), "stepBack"),
        ]
        for destination in destinations {
            service.selected = destination.module
            service.showingSections = destination.sections
            service.showingAppPanel = destination.appPanel
            service.panel?.firstResponder = destination.field
            destination.field.composing = true
            actions = []
            suite.expect(NSEvent.handler?(escape) != nil && actions.isEmpty,
                         "a composing input method keeps Esc in \(destination.name)")
            destination.field.composing = false
            actions = []
            suite.expect(NSEvent.handler?(escape) == nil && actions == [destination.action],
                         "Esc reaches the island from \(destination.name) once composition ends")
        }
    }
}
