// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The production confirmation and alert helper run with an inert Trash action.
/// Windows stay hidden, and the modal double reproduces AppKit's level resets.
enum QuickTogglesAlertTests {
    enum Action { case emptyTrash }
    enum RunState { case running }
    class Fixture {
        var available = true
        var states: [Action: RunState] = [:]
        var confirmations = 0
        func emptyTrashConfirmed() { confirmations += 1 }
    }
    enum FeatureStrings {
        struct Strings {
            let emptyTrashConfirmTitle = "Empty the Trash?"
            let emptyTrashConfirmMessage = "This cannot be undone."
            let emptyTrashConfirmButton = "Empty the Trash"
        }
        static func quickToggles(_ language: Int) -> Strings { Strings() }
    }
    enum L10n {
        struct Strings { let uninstallerCancel = "Cancel" }
        struct Localized {
            let language = 0
            let s = Strings()
        }
        static let shared = Localized()
    }
    struct Event { let window: NSWindow? }
    struct Application {
        var currentEvent: Event?
        var keyWindow: NSWindow?
        func activate(ignoringOtherApps: Bool) {}
    }
    static var NSApp = Application()
    final class NotchService {
        static let shared = NotchService()
        var presentationWindow: NSWindow?
    }
    final class Window: NSWindow {
        var simulatedVisible = true
        var keyReturns = 0
        override var isVisible: Bool { simulatedVisible }
        override func makeKey() { keyReturns += 1 }
    }
    final class Alert: AppKit.NSAlert {
        static var latest: Alert?
        static var response = NSApplication.ModalResponse.alertSecondButtonReturn
        static var beforeReturn: (() -> Void)?
        var modalLevels: [NSWindow.Level] = []
        override func runModal() -> NSApplication.ModalResponse {
            Self.latest = self
            layout()
            for name in [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification] {
                window.level = .modalPanel
                NotificationCenter.default.post(name: name, object: window)
                modalLevels.append(window.level)
            }
            Self.beforeReturn?()
            return Self.response
        }
    }
    typealias NSAlert = Alert
    private enum Origin: CaseIterable { case event, key, other, hidden, absent }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let policy = AppKit.NSApp.activationPolicy()
        AppKit.NSApp.setActivationPolicy(.prohibited)
        defer {
            Alert.latest = nil
            Alert.beforeReturn = nil
            NotchService.shared.presentationWindow = nil
            NSApp = Application()
            AppKit.NSApp.setActivationPolicy(policy)
        }
        for response in [NSApplication.ModalResponse.alertFirstButtonReturn, .alertSecondButtonReturn, .abort] {
            for origin in Origin.allCases {
                let island = makeWindow(), other = makeWindow()
                defer {
                    island.simulatedVisible = false
                    island.close()
                    other.simulatedVisible = false
                    other.close()
                }
                NSApp = Application()
                NSApp.keyWindow = origin == .key || origin == .hidden ? island : other
                if origin == .event { NSApp.currentEvent = Event(window: island) }
                if origin == .other { NSApp.currentEvent = Event(window: other) }
                island.simulatedVisible = origin != .hidden
                NotchService.shared.presentationWindow = origin == .absent ? nil : island
                Alert.latest = nil
                Alert.response = response
                let host = Host()
                host.emptyTrash()
                guard let alert = Alert.latest else {
                    suite.expect(false, "the Trash action presents its confirmation")
                    continue
                }
                defer { alert.window.close() }
                let fromIsland = origin == .event || origin == .key
                suite.expect(alert.modalLevels.count == 2 && alert.modalLevels.allSatisfy {
                    fromIsland ? $0.rawValue > island.level.rawValue : $0 == .modalPanel
                }, "the Trash confirmation stays above its island after key and activation resets, "
                   + "while other entry points keep the native modal level")
                suite.expect(island.keyReturns == (fromIsland ? 1 : 0),
                       "focus returns only to the island that opened the confirmation")
                suite.expect(host.confirmations == (response == .alertFirstButtonReturn ? 1 : 0),
                       "only the primary confirmation allows emptying, never Cancel or an aborted dialog")
                suite.expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"],
                       "Return confirms the alert and Escape cancels it")
                drainMainQueue()
                alert.window.level = .modalPanel
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: alert.window)
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: alert.window)
                suite.expect(alert.window.level == .modalPanel,
                       "a completed confirmation leaves no observers that raise the alert again")
            }
        }
        let island = makeWindow()
        defer {
            island.simulatedVisible = false
            island.close()
        }
        NotchService.shared.presentationWindow = island
        NSApp.keyWindow = island
        Alert.response = .alertSecondButtonReturn
        Alert.beforeReturn = { island.simulatedVisible = false }
        Host().emptyTrash()
        drainMainQueue()
        suite.expect(island.keyReturns == 0, "a hidden island does not take focus when the confirmation closes")
        Alert.beforeReturn = nil
        for unavailable in [true, false] {
            Alert.latest = nil
            let host = Host()
            host.available = !unavailable
            if !unavailable { host.states[.emptyTrash] = .running }
            host.emptyTrash()
            suite.expect(Alert.latest == nil && host.confirmations == 0,
                   "an unavailable or already-running Trash action opens no confirmation and does no work")
        }
    }

    private static func makeWindow() -> Window {
        let window = Window(contentRect: CGRect(x: -4000, y: -4000, width: 200, height: 80),
                            styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        return window
    }

    private static func drainMainQueue() {
        var drained = false
        DispatchQueue.main.async { drained = true }
        let deadline = Date(timeIntervalSinceNow: 2)
        while !drained && Date() < deadline {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }
}
