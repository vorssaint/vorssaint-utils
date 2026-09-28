// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DockAutohideHoldTests {
    // Session methods are extracted from production on every test build. Only
    // event-tap installation and workspace notifications are replaced here.
    enum Workspace {
        static let shared = WorkspaceCenter()
        static let activeSpaceDidChangeNotification = Notification.Name("hold.space")
        static let willSleepNotification = Notification.Name("hold.sleep")
        static let sessionDidResignActiveNotification = Notification.Name("hold.session")
    }
    final class WorkspaceCenter {
        let notificationCenter = NotificationCenter()
        var frontmostApplication: App? = App()
    }
    struct App { var processIdentifier: Int32 = 20 }
    static var activationEvents: [String] = []
    struct FrameRestoration {
        func restoration(for item: Int, isCurrent: @escaping () -> Bool) -> (() -> Void)? {
            activationEvents.append("capture")
            return { if isCurrent() { activationEvents.append("restore") } }
        }
    }
    enum WindowEnumerator {
        static var mayActivate = true
        static func dockPreviewMayActivate(_ item: Int) -> Bool { mayActivate }
    }
    enum WindowActivator {
        static func activate(_ item: Int, handoffSourcePID: Int32? = nil) {
            activationEvents.append("activate")
        }
    }
    final class Service {
        typealias SwitcherItem = Int
        typealias NSWorkspace = Workspace
        typealias DockPreviewFrameRestoration = FrameRestoration
        typealias WindowEnumerator = DockAutohideHoldTests.WindowEnumerator
        typealias WindowActivator = DockAutohideHoldTests.WindowActivator
        let dockAutohideHold: DockAutohideHold
        var dockFrameRestoration: FrameRestoration?
        var dockFrameRestorationGeneration = 0
        var windows = [1]
        var isRunning = true
        var dockHoldObservers: [NSObjectProtocol] = []
        var acceptsInputTap = true
        var inputTapActive = false
        var stoppedWhileHolding = false
        var pendingMove = false
        var pointerEventGeneration = 0
        var tap: CFMachPort?
        var deliveredMoves = 0
        func discardFarMouseMove(axPoint: CGPoint) -> Bool { false }
        func admitMouseMove(axPoint: CGPoint) -> Bool { true }
        func handleOnMain(type: CGEventType, axPoint: CGPoint) { deliveredMoves += 1 }
        var sessionEnds = 0
        init(_ hold: DockAutohideHold) { dockAutohideHold = hold }
        func startDockHoldInputTap() -> Bool {
            inputTapActive = acceptsInputTap
            return acceptsInputTap
        }
        func stopDockHoldInputTap() {
            stoppedWhileHolding = stoppedWhileHolding || dockAutohideHold.isHolding
            inputTapActive = false
        }
        func cancelPendingMove() { pendingMove = false }
        func endSession() {
            activationEvents.append("end")
            sessionEnds += 1
            releaseDockAutohideHold()
        }
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.dock-hold.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let marker = DefaultsKey.dockPreviewRestoreAutohide
        var autohide: Bool? = true
        var writes: [Bool] = []
        var acceptsWrites = true
        let makeHold = {
            DockAutohideHold(defaults: defaults, readAutohide: { autohide }, writeAutohide: {
                writes.append($0)
                guard acceptsWrites else { return false }
                autohide = $0
                return true
            })
        }
        let hold = makeHold()
        suite.expect(writes.isEmpty, "starting without a recovery marker never changes the Dock")
        suite.expect(hold.begin() && autohide == false && hold.isHolding,
                     "an auto-hidden Dock stays visible for the preview session")
        suite.expect(defaults.bool(forKey: marker), "the original auto-hide is recoverable while held")
        suite.expect(hold.begin() && writes == [false], "switching preview apps reuses the hold")
        hold.end()
        hold.end()
        suite.expect(autohide == true && !hold.isHolding && writes == [false, true],
                     "ending or disabling a session restores auto-hide exactly once")
        suite.expect(defaults.object(forKey: marker) == nil, "successful restoration clears recovery")

        writes = []
        autohide = false
        suite.expect(!hold.begin(), "a Dock already permanently visible is never changed")
        autohide = nil
        suite.expect(!hold.begin() && writes.isEmpty, "a missing private API leaves normal preview available")

        autohide = true
        acceptsWrites = false
        suite.expect(!hold.begin() && !hold.isHolding, "a rejected hold cannot masquerade as active")
        suite.expect(defaults.bool(forKey: marker), "failed restoration remains recoverable")
        acceptsWrites = true
        let recovered = makeHold()
        suite.expect(autohide == true && !recovered.isHolding && !defaults.bool(forKey: marker),
                     "the next startup retries an interrupted restoration even with the toggle off")

        autohide = true
        _ = hold.begin()
        acceptsWrites = false
        hold.end()
        suite.expect(!hold.isHolding && autohide == false && defaults.bool(forKey: marker),
                     "a failed release retains recovery instead of forgetting the system change")
        suite.expect(!hold.begin(), "a pending restoration cannot be overwritten by another session")
        acceptsWrites = true
        hold.end()
        suite.expect(autohide == true && !defaults.bool(forKey: marker),
                     "a subsequent release can finish restoring auto-hide")

        autohide = true
        _ = hold.begin()
        autohide = true // User re-enables auto-hide while the preview is open.
        hold.end()
        suite.expect(autohide == true && !hold.isHolding, "restoration preserves re-enabled auto-hide")

        autohide = true
        _ = hold.begin()
        let restarted = makeHold() // Simulate interruption without calling end().
        suite.expect(autohide == true && !restarted.isHolding && !defaults.bool(forKey: marker),
                     "a new process restores the pending preference after an interrupted preview")
        let service = Service(makeHold())
        autohide = true
        service.acceptsInputTap = false
        let beforeRejectedTap = writes.count
        service.beginDockAutohideHold()
        suite.expect(autohide == true && writes.count == beforeRejectedTap
                     && service.dockHoldObservers.isEmpty,
                     "without input protection the normal preview never changes auto-hide")
        service.acceptsInputTap = true
        autohide = false
        service.beginDockAutohideHold()
        suite.expect(!service.inputTapActive && service.dockHoldObservers.isEmpty,
                     "a Dock already visible leaves no input tap or observers")
        autohide = true
        service.beginDockAutohideHold()
        let generation = service.dockFrameRestorationGeneration
        service.beginDockAutohideHold()
        service.pendingMove = true
        suite.expect(service.inputTapActive && service.dockHoldObservers.count == 3,
                     "switching apps keeps exactly one set of hold observers")
        suite.expect(service.dockFrameRestoration != nil && service.dockFrameRestorationGeneration == generation,
                     "switching Dock icons retains the window geometry from before the hold")
        service.handleDockHoldInput(type: .mouseMoved)
        suite.expect(autohide == false && service.sessionEnds == 0,
                     "moving through previews keeps the Dock held")
        // Model the system receiving the unmodified key after the synchronous
        // production handler returns. No event is posted to this Mac.
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: .zero, mouseButton: .left)!
        _ = service.handle(type: .mouseMoved, event: move)
        service.handleDockHoldInput(type: .keyDown)
        _ = service.handle(type: .mouseMoved, event: move)
        var queueDrained = false
        DispatchQueue.main.async { queueDrained = true }
        let deadline = Date().addingTimeInterval(3)
        while !queueDrained && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        suite.expect(queueDrained && service.deliveredMoves == 1,
                     "only fresh pointer input survives keyboard dismissal, not an already queued move")
        suite.expect(!service.stoppedWhileHolding,
                     "auto-hide is restored before the input tap can release its pending key")
        suite.expect(autohide == true && !service.pendingMove
                     && !service.inputTapActive && service.dockHoldObservers.isEmpty,
                     "keyboard input restores before delivery and cancels a queued hover move")
        suite.expect(service.dockFrameRestoration == nil, "ending a hold discards its saved window geometry")
        autohide?.toggle() // Native shortcut chooses a permanently visible Dock.
        service.releaseDockAutohideHold() // A later close or preference sync.
        suite.expect(autohide == false && !defaults.bool(forKey: marker),
                     "later session cleanup cannot undo the user's shortcut choice")
        autohide?.toggle()
        autohide?.toggle()
        service.releaseDockAutohideHold()
        suite.expect(autohide == false,
                     "further Dock changes after keyboard dismissal remain untouched")
        let ended = service.sessionEnds
        service.handleDockHoldInput(type: .keyDown)
        suite.expect(service.sessionEnds == ended,
                     "input outside a hold does not dismiss the normal preview")
        for event in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            autohide = true
            service.beginDockAutohideHold()
            service.handleDockHoldInput(type: event)
            suite.expect(autohide == true && !service.inputTapActive,
                         "losing input protection immediately releases the hold")
        }
        for event in [Workspace.activeSpaceDidChangeNotification, Workspace.willSleepNotification,
                      Workspace.sessionDidResignActiveNotification] {
            autohide = true
            service.beginDockAutohideHold()
            Workspace.shared.notificationCenter.post(name: event, object: nil)
            suite.expect(autohide == true && !service.inputTapActive && service.dockHoldObservers.isEmpty,
                         "leaving the workspace releases both the Dock and input protection")
        }
        autohide = true
        acceptsWrites = false
        service.beginDockAutohideHold()
        suite.expect(!service.inputTapActive && service.dockHoldObservers.isEmpty,
                     "a rejected system write removes input protection immediately")
        acceptsWrites = true
        service.releaseDockAutohideHold()

        autohide = true
        service.beginDockAutohideHold()
        activationEvents = []
        service.commit(1)
        suite.expect(activationEvents == ["capture", "end", "activate", "restore"],
                     "selection captures geometry before release and repairs only after activating the window")
        service.beginDockAutohideHold()
        activationEvents = []
        WindowEnumerator.mayActivate = false
        service.commit(1)
        suite.expect(activationEvents == ["capture", "end"],
                     "a selection rejected by the Space policy never restores a window")
        WindowEnumerator.mayActivate = true
        activationEvents = []
        service.commit(1)
        suite.expect(activationEvents == ["end", "activate"],
                     "normal previews never schedule a frame restoration")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.dockPreviewKeepDockVisible] as? Bool == false,
                     "the experiment is disabled by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.dockPreviewKeepDockVisible)
                     && !SettingsBackupSupport.exportKeys().contains(marker),
                     "backups carry the toggle but never another session's recovery state")
    }
}
