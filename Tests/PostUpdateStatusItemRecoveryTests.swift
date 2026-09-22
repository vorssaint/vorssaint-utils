// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production callbacks run against a controlled queue and menu bar; no real
/// status items, windows, settings or session state are changed by these tests.
enum PostUpdateStatusItemRecoveryTests {
    final class Window { var frame: CGRect = .zero }
    final class Button { var window: Window? = Window() }
    final class NSStatusItem {
        var button: Button? = Button()
        var menu: NSMenu?
        var isVisible = true
    }
    final class StatusController {
        var statusItem: NSStatusItem! = NSStatusItem()
        var recreations = 0
        var replacementFrame: CGRect = .zero
        func recreateStatusItem() {
            recreations += 1
            statusItem = NSStatusItem()
            statusItem.button?.window?.frame = replacementFrame
        }
    }
    final class NSMenu {
        static var visible = true
        static func menuBarVisible() -> Bool { visible }
    }
    struct Screen { var frame: CGRect }
    enum NSScreen {
        static var screens = [Screen(frame: CGRect(x: 0, y: 0, width: 1470, height: 956))]
    }
    final class Popover { var isShown = false }
    enum NSEvent { static var pressedMouseButtons = 0 }
    final class Application {
        var currentSystemPresentationOptions: NSApplication.PresentationOptions = []
    }
    static var NSApp = Application()
    static var session: [String: Any]? = [kCGSessionOnConsoleKey as String: true]
    static func CGSessionCopyCurrentDictionary() -> CFDictionary? { session as CFDictionary? }
    enum AppInfo {
        static var version = "3.4.0-beta.3"
        static var isDeveloperBuild = false
    }
    enum UserDefaults {
        static var standard = Preferences()
        final class Preferences {
            var hideIcon = false
            func bool(forKey key: String) -> Bool { hideIcon }
        }
    }
    enum DispatchQueue {
        static var main = Queue()
        final class Queue {
            var jobs: [() -> Void] = []
            func asyncAfter(deadline: DispatchTime, execute action: @escaping () -> Void) {
                jobs.append(action)
            }
            func next() {
                guard !jobs.isEmpty else { return }
                jobs.removeFirst()()
            }
            func drain() {
                // A regression that polls forever must fail rather than hang.
                for _ in 0..<100 where !jobs.isEmpty { next() }
            }
        }
    }
    class Fixture {
        var statusController: StatusController? = StatusController()
        let popover = Popover()
        var isTerminating = false
        var isReshowingStatusItem = false
        static let reshowVerifyInterval: TimeInterval = 0.8
        static var manager: String?
        static func runningMenuBarManagerName() -> String? { manager }
        var logs: [String] = []
        func logStatusItemPlacement(_ stage: String) { logs.append(stage) }
    }
    static let visibleFrame = CGRect(x: 1135, y: 926, width: 36, height: 30)

    static func reset() -> Host {
        NSMenu.visible = true
        NSScreen.screens = [Screen(frame: CGRect(x: 0, y: 0, width: 1470, height: 956))]
        NSApp = Application()
        NSEvent.pressedMouseButtons = 0
        session = [kCGSessionOnConsoleKey as String: true]
        AppInfo.version = "3.4.0-beta.3"
        AppInfo.isDeveloperBuild = false
        UserDefaults.standard = UserDefaults.Preferences()
        DispatchQueue.main = DispatchQueue.Queue()
        Fixture.manager = nil
        return Host()
    }

    static func run(_ suite: TestSuite) {
        for previous in [nil, "", "dev", "3.4.0-beta.3", "3.4.0", "3.5.0"] as [String?] {
            let host = reset()
            host.recoverStatusItemAfterUpdate(previousVersion: previous)
            suite.expect(DispatchQueue.main.jobs.isEmpty,
                         "first installs, unchanged versions and downgrades never schedule recovery: \(previous ?? "nil")")
        }
        for previous in ["3.3.5", "3.4.0-beta.2.1"] {
            let host = reset()
            host.statusController?.statusItem.button?.window?.frame = visibleFrame
            let original = host.statusController?.statusItem
            host.recoverStatusItemAfterUpdate(previousVersion: previous)
            DispatchQueue.main.drain()
            suite.expect(host.statusController?.statusItem === original && host.statusController?.recreations == 0,
                         "a healthy item keeps its exact instance after an update from \(previous)")
            suite.expect(host.logs == ["post-update appeared"] && DispatchQueue.main.jobs.isEmpty,
                         "successful placement ends the check without future polling")
        }
        do {
            let host = reset()
            host.statusController?.statusItem.button?.window?.frame = CGRect(x: 0, y: 0, width: 36, height: 0)
            host.recoverStatusItemAfterUpdate(previousVersion: "3.3.5")
            for _ in 0..<8 { DispatchQueue.main.next() }
            suite.expect(host.statusController?.recreations == 0,
                         "a newborn item gets several seconds to settle without being replaced")
            host.statusController?.statusItem.button?.window?.frame = visibleFrame
            DispatchQueue.main.drain()
            suite.expect(host.statusController?.recreations == 0 && DispatchQueue.main.jobs.isEmpty,
                         "late placement cancels recovery without losing the arranged position")
        }
        for succeeds in [true, false] {
            let host = reset()
            host.statusController?.replacementFrame = succeeds ? visibleFrame : CGRect(x: -200, y: 926, width: 36, height: 30)
            host.recoverStatusItemAfterUpdate(previousVersion: "3.3.5")
            for _ in 0..<11 { DispatchQueue.main.next() }
            suite.expect(host.statusController?.recreations == 0, "the full initial placement grace is preserved")
            DispatchQueue.main.next()
            suite.expect(host.statusController?.recreations == 1, "a missing icon gets one recovery attempt")
            DispatchQueue.main.drain()
            suite.expect(host.statusController?.recreations == 1 && DispatchQueue.main.jobs.isEmpty,
                         "verification never escalates to another rebuild or identity reset")
            suite.expect(host.logs.last == (succeeds ? "post-update appeared" : "post-update still hidden"),
                         "the replacement's real placement result is recorded")
        }

        let cancellations: [(String, (Host) -> Void)] = [
            ("user hides the icon", { _ in UserDefaults.standard.hideIcon = true }),
            ("system hides the item", { $0.statusController?.statusItem.isVisible = false }),
            ("panel is open", { $0.popover.isShown = true }),
            ("context menu is open", { $0.statusController?.statusItem.menu = NSMenu() }),
            ("person is dragging an item", { _ in NSEvent.pressedMouseButtons = 1 }),
            ("app is quitting", { $0.isTerminating = true }),
            ("manual recovery owns the item", { $0.isReshowingStatusItem = true }),
            ("reopen replaced the item", { $0.statusController?.statusItem = NSStatusItem() }),
            ("controller went away", { $0.statusController = nil }),
            ("menu bar hides", { _ in NSMenu.visible = false }),
            ("auto-hidden bar", { _ in NSApp.currentSystemPresentationOptions = [.autoHideMenuBar] }),
            ("hidden presentation", { _ in NSApp.currentSystemPresentationOptions = [.hideMenuBar] }),
            ("fullscreen presentation", { _ in NSApp.currentSystemPresentationOptions = [.fullScreen] }),
            ("display layout changes", { _ in NSScreen.screens[0].frame.origin.x = -1470 }),
            ("all displays disconnect", { _ in NSScreen.screens = [] }),
            ("session state is unavailable", { _ in session = nil }),
            ("user switches away", { _ in session = [kCGSessionOnConsoleKey as String: false] }),
            ("screen locks", { _ in session?["CGSSessionScreenIsLocked"] = true }),
            ("menu bar organizer is running", { _ in Fixture.manager = "organizer" })
        ]
        for (name, cancel) in cancellations {
            // Cancellation must hold both before a rebuild and while verifying
            // its result, not just when the launch first schedules the check.
            for afterRebuild in [false, true] {
                let host = reset()
                let controller = host.statusController!
                host.recoverStatusItemAfterUpdate(previousVersion: "3.3.5")
                for _ in 0..<(afterRebuild ? 12 : 1) { DispatchQueue.main.next() }
                let count = controller.recreations
                cancel(host)
                DispatchQueue.main.drain()
                suite.expect(controller.recreations == count && DispatchQueue.main.jobs.isEmpty,
                             "recovery stops when \(name), after rebuild: \(afterRebuild)")
            }
        }
        do {
            let host = reset()
            host.verifyPostUpdateStatusItem(host.statusController!.statusItem,
                                            screenFrames: NSScreen.screens.map(\.frame),
                                            deadline: .distantPast)
            DispatchQueue.main.drain()
            suite.expect(host.statusController?.recreations == 0 && DispatchQueue.main.jobs.isEmpty,
                         "a callback delayed beyond the startup window cannot recover after sleep")
        }
        for developer in [false, true] {
            let host = reset()
            AppInfo.isDeveloperBuild = developer
            if !developer { NSScreen.screens = [] }
            host.recoverStatusItemAfterUpdate(previousVersion: "3.3.5")
            suite.expect(DispatchQueue.main.jobs.isEmpty,
                         "developer builds and launches without displays leave the menu bar alone")
        }
    }
}
