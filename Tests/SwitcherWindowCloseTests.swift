// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Runs the production close methods and pending-close state machine with a
/// deterministic clock and AX transport. No real application is closed.
enum SwitcherWindowCloseTests {
    typealias NSRunningApplication = App
    typealias NSWorkspace = Workspace
    typealias DispatchQueue = Queue
    typealias DispatchTime = Instant
    typealias WindowActivator = Activator
    typealias SpaceWindowBridge = Bridge

    static var events: [String] = []
    static var generation: UInt64 = 10
    static var foregroundPID: pid_t = 40
    static var focusedWindowID: CGWindowID? = 4
    static var hidden = false
    static var windowPublished = true
    static var remoteAvailable = true
    static var fullscreen = false
    static var buttonEnabled = true
    static var hasCloseButton = true
    static var pressResult = AXError.success
    static var rawWindows: [[String: Any]]? = []
    static var nextPress: (() -> Void)?
    static let appElement = Element("app")
    static let windowElement = Element("window")
    static let buttonElement = Element("button")

    final class Element {
        let name: String
        var timeout: Float = 0
        init(_ name: String) { self.name = name }
    }
    final class App {
        let processIdentifier: pid_t
        var isHidden: Bool { hidden }
        var isTerminated = false
        var isActive: Bool { foregroundPID == processIdentifier }
        init?(processIdentifier: pid_t) { self.processIdentifier = processIdentifier }
        func unhide() { hidden = false; events.append("unhide") }
        func hide() { hidden = true; events.append("hide") }
    }
    final class Workspace {
        static let shared = Workspace()
        static let didActivateApplicationNotification = Notification.Name("close-test-activation")
        static let applicationUserInfoKey = "app"
        let notificationCenter = Notifications()
        var frontmostApplication: App? { App(processIdentifier: foregroundPID) }
    }
    final class Notifications {
        final class Observer: NSObject {
            let callback: (Notification) -> Void
            init(_ callback: @escaping (Notification) -> Void) { self.callback = callback }
        }
        var observers: [Observer] = []
        func addObserver(forName: Notification.Name?, object: Any?, queue: OperationQueue?,
                         using callback: @escaping (Notification) -> Void) -> NSObjectProtocol {
            let observer = Observer(callback)
            observers.append(observer)
            return observer
        }
        func removeObserver(_ observer: NSObjectProtocol) {
            observers.removeAll { $0 === observer as AnyObject }
        }
        func activate(_ pid: pid_t) {
            foregroundPID = pid
            let note = Notification(name: Workspace.didActivateApplicationNotification,
                                    userInfo: [Workspace.applicationUserInfoKey: App(processIdentifier: pid)!])
            for observer in observers { observer.callback(note) }
        }
    }
    struct Instant: Comparable {
        let value: TimeInterval
        static func now() -> Instant { Instant(value: Clock.time) }
        static func +(lhs: Instant, rhs: TimeInterval) -> Instant { Instant(value: lhs.value + rhs) }
        static func <(lhs: Instant, rhs: Instant) -> Bool { lhs.value < rhs.value }
    }
    enum Clock {
        static var time: TimeInterval = 0
        static var jobs: [(Instant, () -> Void)] = []
        static func advance(to end: TimeInterval) {
            while let next = jobs.indices.min(by: { jobs[$0].0 < jobs[$1].0 }), jobs[next].0.value <= end {
                let job = jobs.remove(at: next)
                time = job.0.value
                job.1()
            }
            time = end
        }
    }
    enum Queue {
        static let main = Scheduler()
        final class Scheduler {
            func asyncAfter(deadline: Instant, execute: @escaping () -> Void) {
                Clock.jobs.append((deadline, execute))
            }
        }
    }
    enum Bridge {
        static var parked = true
        static func isParkedOnHiddenSpace(_ windowID: CGWindowID) -> Bool { parked }
    }
    enum Resolver {
        static func elementOnHiddenSpace(windowID: CGWindowID, pid: pid_t) -> Element? {
            events.append("remote:\(windowID):\(pid)")
            return remoteAvailable ? windowElement : nil
        }
    }
    enum Permissions {
        static let shared = State()
        final class State { var accessibility = true }
    }
    enum AutoQuitService {
        static let shared = AutoQuitServiceState()
        final class AutoQuitServiceState {
            func recordProgrammaticCloseRequest(pid: pid_t) { events.append("intent:\(pid)") }
        }
    }
    enum SpaceHop {
        static func cancelPending() { events.append("cancel-hop") }
    }
    enum OwnApp {
        static let windows: [OwnWindow] = []
        final class OwnWindow {
            let windowNumber = -1
            func close() { events.append("own-close") }
        }
    }
    enum Activator {
        typealias AXUIElement = Element
        typealias AXWindowResolver = Resolver
        typealias NSRunningApplication = App
        typealias NSWorkspace = Workspace
        typealias SpaceWindowBridge = Bridge
        typealias Permissions = SwitcherWindowCloseTests.Permissions
        typealias AutoQuitService = SwitcherWindowCloseTests.AutoQuitService
        typealias SpaceHop = SwitcherWindowCloseTests.SpaceHop
        typealias SwitcherPendingWindowClose = SwitcherWindowCloseTests.SwitcherPendingWindowClose
        static let NSApp = OwnApp.self
        static var pendingWindowClose: SwitcherPendingWindowClose?
        static var windowCloseGeneration: UInt64 = 0
        static func currentActivationGeneration() -> UInt64 { generation }
        static func activationGeneration(for pid: pid_t) -> UInt64 { generation }
        static func isCurrentActivation(_ candidate: UInt64) -> Bool { candidate == generation }
        static func focusedWindowID(for pid: pid_t) -> CGWindowID? { SwitcherWindowCloseTests.focusedWindowID }
        static func activate(_ item: SwitcherItem, retry: Bool) {
            generation += 1
            hidden = false
            Bridge.parked = false
            events.append("activate:\(item.windowID ?? 0)")
            Workspace.shared.notificationCenter.activate(item.pid)
        }
        static func AXUIElementCreateApplication(_ pid: pid_t) -> Element {
            events.append("app:\(pid)")
            return appElement
        }
        @discardableResult
        static func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) -> AXError {
            element.timeout = timeout
            events.append("timeout:\(element.name)")
            return .success
        }
        static func axElement(windowID: CGWindowID, in app: Element, pid: pid_t? = nil) -> Element? {
            if windowPublished { return windowElement }
            guard let pid else { return nil }
            return Resolver.elementOnHiddenSpace(windowID: windowID, pid: pid)
        }
        static func elementAttribute(_ element: Element, _ attribute: String) -> Element? {
            events.append("button-read")
            return hasCloseButton ? buttonElement : nil
        }
        static func boolAttribute(_ element: Element, _ attribute: String, default value: Bool) -> Bool {
            if attribute == "AXFullScreen" { return fullscreen }
            if attribute == kAXEnabledAttribute as String { return buttonEnabled }
            return value
        }
        static func AXUIElementPerformAction(_ element: Element, _ action: CFString) -> AXError {
            events.append("press")
            nextPress?()
            return pressResult
        }
        static func AXUIElementSetAttributeValue(_ element: Element, _ attribute: CFString,
                                                _ value: CFTypeRef) -> AXError {
            events.append("leave-fullscreen")
            fullscreen = false
            return .success
        }
        static func CGWindowListCopyWindowInfo(_ options: CGWindowListOption, _ windowID: CGWindowID) -> Any? {
            events.append("exists:\(windowID)")
            return rawWindows
        }
    }

    static func item(id: CGWindowID = 77, isHidden: Bool = false) -> SwitcherItem {
        .window(id: id, title: "Document", appName: "Editor", pid: 20, windowOwnerPID: 30,
                isOnScreen: false, isAppHidden: isHidden, frame: .zero)
    }
    static func windowInfo(id: CGWindowID = 77, owner: pid_t = 30) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: owner)]
    }
    static func reset() {
        Activator.pendingWindowClose?.cancel()
        Activator.pendingWindowClose = nil
        Activator.windowCloseGeneration = 0
        Workspace.shared.notificationCenter.observers = []
        Clock.time = 0
        Clock.jobs = []
        events = []
        generation = 10
        foregroundPID = 40
        focusedWindowID = 4
        hidden = false
        windowPublished = true
        remoteAvailable = true
        fullscreen = false
        buttonEnabled = true
        hasCloseButton = true
        pressResult = .success
        rawWindows = [windowInfo()]
        nextPress = nil
        Bridge.parked = true
        Permissions.shared.accessibility = true
        [appElement, windowElement, buttonElement].forEach { $0.timeout = 0 }
    }
    static func run(_ suite: TestSuite) {
        reset()
        windowPublished = false
        pressResult = .cannotComplete
        var results: [Bool] = []
        Activator.closeWindowIncludingHiddenState(item()) { results.append($0) }
        Clock.advance(to: 0.9)
        suite.expect(events.filter { $0 == "press" }.count == 1 && !events.contains("leave-fullscreen")
                     && results == [true] && events.contains("activate:77"),
                     "an ambiguous press waits for its result and exposes a remaining remote window without pressing again")
        suite.expect(events.contains("remote:77:30") && events.contains("app:30") && events.contains("intent:20"),
                     "the shared resolver addresses the actual window owner while close intent belongs to its host app")
        suite.expect(appElement.timeout == 0.35 && windowElement.timeout == 0.35 && buttonElement.timeout == 0.35
                     && (events.firstIndex(of: "timeout:window") ?? Int.max) < (events.firstIndex(of: "button-read") ?? -1)
                     && (events.firstIndex(of: "timeout:button") ?? Int.max) < (events.firstIndex(of: "press") ?? -1),
                     "close sets separate AX timeouts on app, window and close button before using each object")

        reset()
        results = []
        Activator.closeWindowIncludingHiddenState(item()) { results.append($0) }
        rawWindows = []
        Clock.advance(to: 0.9)
        suite.expect(results == [true] && !events.contains("activate:77") && !events.contains("unhide")
                     && events.filter { $0 == "press" }.count == 1,
                     "a remote window that disappears closes without travelling or pressing again")

        reset()
        rawWindows = [windowInfo(id: 77, owner: 31), windowInfo(id: 78, owner: 30)]
        suite.expect(Activator.windowExistsForClose(windowID: 77, ownerPID: 30) == false,
                     "close confirmation requires both the exact window id and its actual owner")
        rawWindows = nil
        suite.expect(Activator.windowExistsForClose(windowID: 77, ownerPID: 30) == nil,
                     "an unavailable window-server snapshot is unknown, not a confirmed close")

        for supersession in ["generation", "foreground", "round-trip", "sibling-window", "unknown-window"] {
            reset()
            results = []
            Activator.closeWindowIncludingHiddenState(item()) { results.append($0) }
            if supersession == "generation" {
                generation += 1
            } else if supersession == "foreground" {
                foregroundPID = 50
            } else if supersession == "sibling-window" {
                focusedWindowID = 5
            } else if supersession == "unknown-window" {
                focusedWindowID = nil
            } else {
                Workspace.shared.notificationCenter.activate(50)
                Workspace.shared.notificationCenter.activate(40)
            }
            Clock.advance(to: 0.9)
            suite.expect(results == [true] && !events.contains("activate:77")
                         && events.filter { $0 == "press" }.count == 1,
                         "a later \(supersession) prevents the close result from taking focus back")
        }

        reset()
        var oldResults: [Bool] = []
        var newResults: [Bool] = []
        Activator.closeWindowIncludingHiddenState(item()) { oldResults.append($0) }
        Activator.closeWindowIncludingHiddenState(item(id: 88)) { newResults.append($0) }
        rawWindows = []
        Clock.advance(to: 1)
        suite.expect(oldResults == [false] && newResults == [true]
                     && !events.contains("activate:77") && !events.contains("activate:88")
                     && Workspace.shared.notificationCenter.observers.isEmpty,
                     "a new close cancels the old observation and its queued timer without leaking an observer")

        reset()
        results = []
        Activator.closeWindowIncludingHiddenState(item()) { result in
            results.append(result)
            generation += 1
        }
        Clock.advance(to: 0.9)
        suite.expect(results == [true] && !events.contains("activate:77"),
                     "completion may supersede focus before the remaining window is revealed")

        reset()
        results = []
        newResults = []
        rawWindows = [windowInfo(), windowInfo(id: 88)]
        Activator.closeWindowIncludingHiddenState(item()) { result in
            results.append(result)
            Activator.closeWindowIncludingHiddenState(item(id: 88)) { newResults.append($0) }
        }
        Clock.advance(to: 0.8)
        suite.expect(results == [true] && !events.contains("activate:77")
                     && newResults.isEmpty && Activator.pendingWindowClose != nil,
                     "a close started reentrantly by completion prevents the previous request from revealing its window")
        rawWindows = [windowInfo()]
        Clock.advance(to: 0.9)
        suite.expect(newResults == [true] && Activator.pendingWindowClose == nil
                     && !events.contains("activate:77") && !events.contains("activate:88")
                     && events.filter { $0 == "press" }.count == 2,
                     "the reentrant close completes once its own window disappears without repeating either close or reveal")

        reset()
        Activator.closeWindowIncludingHiddenState(item()) { _ in
            Bridge.parked = false
            Activator.closeWindowIncludingHiddenState(item(id: 88)) { _ in }
        }
        Clock.advance(to: 0.9)
        suite.expect(Activator.pendingWindowClose == nil && !events.contains("activate:77")
                     && events.filter { $0 == "press" }.count == 2,
                     "even a newer close that finishes synchronously supersedes the old reveal")

        reset()
        oldResults = []
        newResults = []
        var reentrantResults: [Bool] = []
        Activator.closeWindowIncludingHiddenState(item()) { result in
            oldResults.append(result)
            if !result {
                Activator.closeWindowIncludingHiddenState(item(id: 99)) { reentrantResults.append($0) }
            }
        }
        Activator.closeWindowIncludingHiddenState(item(id: 88)) { newResults.append($0) }
        rawWindows = []
        Clock.advance(to: 1)
        suite.expect(oldResults == [false] && newResults == [false] && reentrantResults == [true]
                     && events.filter { $0 == "press" }.count == 2,
                     "cancellation cannot overwrite a newer close started by its completion")

        reset()
        hidden = true
        fullscreen = true
        buttonEnabled = false
        results = []
        Activator.closeWindowIncludingHiddenState(item(isHidden: true)) { results.append($0) }
        suite.expect(events.contains("leave-fullscreen") && !events.contains("press")
                     && !events.contains("unhide"),
                     "a hidden fullscreen window exits fullscreen before its disabled close button is retried")
        buttonEnabled = true
        pressResult = .cannotComplete
        Clock.advance(to: 0.2)
        rawWindows = []
        Clock.advance(to: 1)
        suite.expect(results == [true] && events.filter { $0 == "press" }.count == 1
                     && !events.contains("activate:77") && hidden,
                     "a fullscreen close that completes preserves hiding and never replays an ambiguous press")

        reset()
        hidden = true
        Bridge.parked = false
        windowPublished = false
        remoteAvailable = false
        results = []
        Activator.closeWindowIncludingHiddenState(item(isHidden: true)) { results.append($0) }
        suite.expect(events.contains("unhide"), "a hidden app with no reachable close button is revealed for the existing retry")
        windowPublished = true
        Clock.advance(to: 1)
        suite.expect(results == [true] && events.contains("activate:77") && !events.contains("hide"),
                     "a revealed hidden app with an outstanding close confirmation is never hidden again")

        reset()
        hidden = true
        Bridge.parked = false
        windowPublished = false
        remoteAvailable = false
        results = []
        Activator.closeWindowIncludingHiddenState(item(isHidden: true)) { results.append($0) }
        windowPublished = true
        Clock.advance(to: 0.15)
        rawWindows = []
        Clock.advance(to: 1)
        suite.expect(results == [true] && events.contains("hide") && !events.contains("activate:77"),
                     "a temporarily revealed app is hidden again only after its window is confirmed gone")

        reset()
        buttonEnabled = false
        fullscreen = true
        results = []
        Activator.closeWindowIncludingHiddenState(item()) { results.append($0) }
        Clock.advance(to: 5)
        suite.expect(results == [false] && !events.contains("press")
                     && Activator.pendingWindowClose == nil,
                     "a fullscreen window whose close button never becomes enabled stops retrying")
        reset()
    }
}
