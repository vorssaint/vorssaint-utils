// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// Production controller, model and quit methods with hidden AppKit windows.
/// Workspace and event delivery are doubles: no user's app receives a quit.
enum QuitAppsRuntimeTests {
    final class NSRunningApplication {
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        var activationPolicy = NSApplication.ActivationPolicy.regular
        var isTerminated = false
        var localizedName: String? { bundleIdentifier }
        var icon: NSImage? { nil }
        var quitRequests = 0
        var acceptsQuit = true
        init(_ pid: pid_t, _ bundle: String) { processIdentifier = pid; bundleIdentifier = bundle }
        convenience init?(processIdentifier: pid_t) {
            guard let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.processIdentifier == processIdentifier
            }) else { return nil }
            self.init(app.processIdentifier, app.bundleIdentifier ?? "")
        }
        func terminate() -> Bool {
            let app = NSWorkspace.shared.runningApplications.first { $0.processIdentifier == processIdentifier }!
            app.quitRequests += 1
            return app.acceptsQuit
        }
    }
    final class NSWorkspace {
        static let shared = NSWorkspace()
        static let didLaunchApplicationNotification = Notification.Name("quit-test-launch")
        static let didTerminateApplicationNotification = Notification.Name("quit-test-terminate")
        let notificationCenter = NotificationCenter()
        var runningApplications: [NSRunningApplication] = []
        var frontmostApplication: NSRunningApplication?
        func icon(for type: UTType) -> NSImage { NSImage(size: CGSize(width: 32, height: 32)) }
    }
    class ServiceState {
        enum Action { case quitAllApps }
        var quitAppsAvailable = true
        var quitAllExceptions = Defaults.mandatoryAutoQuitExceptionBundleIDs
        func beginRun(_ action: Action) -> Bool { true }
        func finishRun(_ action: Action, state: Bool?) {}
    }
    final class Application { var delegate: AnyObject? }
    static let NSApp = Application()
    enum NSScreen { static let pointerVisibleFrame = CGRect(x: -5000, y: -5000, width: 1200, height: 900) }
    final class QuitAppsPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func orderFrontRegardless() {}
        override func makeKey() {}
    }
    struct HUDBackdrop: View {
        enum Contrast { case high }
        let cornerRadius: CGFloat
        let contrast: Contrast
        var body: some View { Color.clear }
    }
    enum AssistiveKeyboard {
        static var ownsPoint = false
        static func ownsCocoaPoint(_ point: CGPoint) -> Bool { ownsPoint }
    }
    struct NSEvent {
        typealias ModifierFlags = AppKit.NSEvent.ModifierFlags
        typealias EventTypeMask = AppKit.NSEvent.EventTypeMask
        let keyCode: UInt16
        var modifierFlags: ModifierFlags = []
        var isARepeat = false
        var characters: String?
        var window: NSWindow?
        static var mouseLocation = CGPoint.zero
        static var locals: [UUID: (EventTypeMask, (NSEvent) -> NSEvent?)] = [:]
        static var globals: [UUID: (NSEvent) -> Void] = [:]
        static func addLocalMonitorForEvents(matching mask: EventTypeMask,
                                              handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
            let id = UUID(); locals[id] = (mask, handler); return id
        }
        static func addGlobalMonitorForEvents(matching mask: EventTypeMask,
                                               handler: @escaping (NSEvent) -> Void) -> Any? {
            let id = UUID(); globals[id] = handler; return id
        }
        static func removeMonitor(_ monitor: Any) {
            guard let id = monitor as? UUID else { return }
            locals[id] = nil; globals[id] = nil
        }
    }
    enum ReviewDefaults { static var current = UserDefaults.standard }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let policy = AppKit.NSApp.activationPolicy()
        AppKit.NSApp.setActivationPolicy(.prohibited)
        let service = QuickTogglesService.shared
        let controller = QuitAppsPanelController.shared
        let workspace = NSWorkspace.shared
        defer {
            controller.close()
            workspace.runningApplications = []
            workspace.frontmostApplication = nil
            NSApp.delegate = nil
            AssistiveKeyboard.ownsPoint = false
            service.quitAppsAvailable = true
            service.quitAllExceptions = Defaults.mandatoryAutoQuitExceptionBundleIDs
            AppKit.NSApp.setActivationPolicy(policy)
        }
        let own = NSRunningApplication(ProcessInfo.processInfo.processIdentifier, "com.vorssaint.utils.dev")
        let first = NSRunningApplication(10, "test.first")
        let second = NSRunningApplication(11, "test.second")
        let kept = NSRunningApplication(12, "test.kept")
        workspace.runningApplications = [own, first, second, kept]
        service.quitAllExceptions.append("test.kept")
        let delegate = AppDelegate()
        NSApp.delegate = delegate
        delegate.panelActivationSource = first
        workspace.frontmostApplication = own
        suite.expect(service.frontmostAppPID() == 10,
                     "the actual panel source is kept without needing an ordinary onscreen window")
        workspace.frontmostApplication = second
        suite.expect(service.frontmostAppPID() == 11, "a currently active app takes precedence over the remembered source")
        workspace.frontmostApplication = own
        first.isTerminated = true
        suite.expect(service.frontmostAppPID() == nil, "a terminated origin is never replaced by an unrelated visible app")
        first.isTerminated = false
        delegate.panelActivationSource = nil
        suite.expect(service.frontmostAppPID() == nil, "an unknown origin stays unknown")
        delegate.panelActivationSource = first
        service.showQuitApps(scope: .allExceptFront)
        suite.expect(controller.model?.frontmostPID == 10 && controller.model?.focus == .button(.allExceptFront),
                     "the service carries the captured origin into the confirmation")
        suite.expect(controller.panel!.level.rawValue > NSWindow.Level.statusBar.rawValue + 1,
                     "the confirmation stays above a pinned island")

        for code in [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Delete] {
            for flags in [NSEvent.ModifierFlags(), .command, [.command, .option]] {
                controller.model!.focus = .row(10)
                controller.handleKey(NSEvent(keyCode: UInt16(code), modifierFlags: flags, isARepeat: true))
                drain()
                suite.expect(controller.model != nil && first.quitRequests == 0 && second.quitRequests == 0,
                             "a held confirmation key never sends a quit or dismisses the list")
            }
        }
        controller.model!.focus = .row(10)
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_DownArrow), isARepeat: true))
        suite.expect(controller.model!.focus == .row(12), "arrow repetition still moves the highlight")
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_Delete), modifierFlags: .command))
        suite.expect(kept.quitRequests == 1 && controller.model!.quitting.contains(12),
                     "a fresh explicit row action can request a graceful quit of a kept app")
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_Return)))
        suite.expect(kept.quitRequests == 1, "an app awaiting a reply receives no duplicate request")
        controller.model!.focus = .row(10)
        first.acceptsQuit = false
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_ANSI_KeypadEnter)))
        suite.expect(first.quitRequests == 1 && !controller.model!.quitting.contains(10),
                     "a refused request restores the row immediately")
        first.acceptsQuit = true
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_Return)))
        let pendingModel = controller.model!
        suite.expect(first.quitRequests == 2 && pendingModel.quitting.contains(10),
                     "a new press requests a graceful quit without assuming the app has exited")
        drain(until: Date(timeIntervalSinceNow: 4.2))
        suite.expect(!pendingModel.quitting.contains(10) && !pendingModel.quitting.contains(12),
                     "a still-running app gets its button back after the settle delay")
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_Escape)))
        suite.expect(controller.model == nil && NSEvent.locals.isEmpty && NSEvent.globals.isEmpty,
                     "Escape closes the window and tears down every input monitor")

        first.quitRequests = 0; second.quitRequests = 0; kept.quitRequests = 0
        service.showQuitApps(scope: .allExceptFront)
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_Return)))
        drain()
        suite.expect(first.quitRequests == 0 && second.quitRequests == 1 && kept.quitRequests == 0
                     && own.quitRequests == 0 && controller.model == nil,
                     "confirming all-except-front dispatches only the eligible app, then closes")
        service.showQuitApps(scope: .all)
        controller.handleKey(NSEvent(keyCode: UInt16(kVK_Return), modifierFlags: .command))
        drain()
        suite.expect(first.quitRequests == 1 && second.quitRequests == 2 && kept.quitRequests == 0,
                     "a fresh all-apps confirmation preserves every exception")

        service.showQuitApps()
        AssistiveKeyboard.ownsPoint = true
        Array(NSEvent.globals.values).forEach { $0(NSEvent(keyCode: 0)) }
        suite.expect(controller.model != nil, "clicking the accessibility keyboard leaves the confirmation open")
        AssistiveKeyboard.ownsPoint = false
        Array(NSEvent.globals.values).forEach { $0(NSEvent(keyCode: 0)) }
        suite.expect(controller.model == nil && NSEvent.locals.isEmpty && NSEvent.globals.isEmpty,
                     "an ordinary outside click still dismisses and removes monitors")
        service.quitAppsAvailable = false
        suite.expect(!service.quitApp(pid: 10), "a disabled feature cannot quit a row through a stale callback")
        service.showQuitApps()
        service.quitAllApps(keepingPID: nil)
        suite.expect(controller.model == nil && first.quitRequests == 1 && second.quitRequests == 2,
                     "the disabled feature neither opens a window nor sends a batch request")
        radialAvailability(suite)
    }

    private static func radialAvailability(_ suite: TestSuite) {
        let name = "QuitAppsRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.register(defaults: Defaults.registeredDefaults)
        ReviewDefaults.current = defaults
        defer {
            ReviewDefaults.current = .standard
            defaults.removePersistentDomain(forName: name)
        }
        for toggles in [false, true] {
            for quit in [false, true] {
                defaults.set(toggles, forKey: AppFeature.quickToggles.availabilityKey)
                defaults.set(quit, forKey: AppFeature.quitApps.availabilityKey)
                let choices = Editor().availableQuickToggles
                suite.expect(choices.contains(.quitAllApps) == quit && choices.contains(.darkMode) == toggles,
                             "radial choices follow each feature independently")
            }
        }
    }

    private static func drain(until deadline: Date = Date(timeIntervalSinceNow: 0.04)) {
        while Date() < deadline { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
    }
}
