// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum AppWindowMoveBridgeTests {
    enum Bridge {
        static var operationClass: AnyClass?
        static func NSClassFromString(_ name: String) -> AnyClass? { operationClass }
    }

    class InitializableOperation: NSObject {
        static var windows: [NSNumber] = []
        static var space: UInt64 = 0
        static var releases = 0

        @objc(initWithWindows:spaceID:)
        init(windows: [NSNumber], spaceID: UInt64) {
            Self.windows = windows
            Self.space = spaceID
            super.init()
        }

        deinit { InitializableOperation.releases += 1 }
    }

    final class MoveOperation: InitializableOperation {
        static var performances = 0
        @objc func performWithWMBridgeDelegate() { Self.performances += 1 }
    }

    static func run(_ suite: TestSuite) {
        defer { Bridge.operationClass = nil }
        for cls: AnyClass? in [nil, NSObject.self, InitializableOperation.self] {
            Bridge.operationClass = cls
            suite.expect(!Bridge.canRequestMoves && !Bridge.requestMove(42, toSpace: 9),
                         "a missing move class, initializer or perform method is unavailable")
        }
        Bridge.operationClass = MoveOperation.self
        MoveOperation.performances = 0
        InitializableOperation.releases = 0
        let windowID = CGWindowID.max
        let spaceID = UInt64.max - 1
        suite.expect(Bridge.canRequestMoves && Bridge.requestMove(windowID, toSpace: spaceID),
                     "a complete Objective-C move operation can be dispatched")
        suite.expect(InitializableOperation.windows == [NSNumber(value: windowID)]
                        && InitializableOperation.space == spaceID && MoveOperation.performances == 1,
                     "the bridge preserves window and Space IDs and invokes the void perform selector once")
        suite.expect(InitializableOperation.releases == 1,
                     "the allocated move operation is released after dispatch")
    }
}

enum AppWindowTravelLifecycleTests {
    enum Activator {
        static let activationLock = NSLock()
        static var activationGeneration: UInt64 = 0
        static var activationGenerationsByPID: [pid_t: UInt64] = [:]
        static var focused: [CGWindowID] = []
        static var appOnlyActivations = 0
        enum SpaceHop { static func cancelPending() {} }
        static func cancelPendingMinimizeRestore() {}
        static func activate(pid: pid_t, windowID: CGWindowID?, appName: String,
                             handoffSourcePID: pid_t?) {
            _ = supersedePendingActivations(for: pid)
            if let windowID { focused.append(windowID) }
            else { appOnlyActivations += 1 }
        }
    }

    final class Queue {
        var pending: [() -> Void] = []
        func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) { pending.append(work) }
        func drain() {
            let work = pending
            pending.removeAll()
            work.forEach { $0() }
        }
    }

    enum Bridge {
        static var membership: [UInt64] = []
        static var arrivesImmediately = false
        static var accepts = true
        static var requests = 0
        static func spaces(of windowID: CGWindowID) -> [UInt64] { membership }
        static func requestMove(_ windowID: CGWindowID, toSpace space: UInt64) -> Bool {
            requests += 1
            if arrivesImmediately { membership = [space] }
            return accepts
        }
    }

    enum Travel {
        typealias WindowActivator = Activator
        typealias SpaceWindowBridge = Bridge
        struct NSRunningApplication {
            init?(processIdentifier: pid_t) {}
        }
        enum DispatchQueue { static let main = Queue() }
        static var moveTimeout: TimeInterval = 0.3
        static let movePollInterval: TimeInterval = 0.01
        static var placements = 0
        static var destinationSpace: UInt64? = 5
        static var appTarget: CGWindowID? = 42
        static func travelTarget(for app: NSRunningApplication) -> CGWindowID? { appTarget }
        static func destination(for windowID: CGWindowID, screen: NSScreen?) -> UInt64? { destinationSpace }
        static func placeOnScreen(_ windowID: CGWindowID, pid: pid_t, screen: NSScreen?) { placements += 1 }
    }

    static func run(_ suite: TestSuite) {
        func reset() {
            Travel.DispatchQueue.main.pending.removeAll()
            Travel.moveTimeout = 0.3
            Travel.placements = 0
            Travel.destinationSpace = 5
            Travel.appTarget = 42
            Bridge.membership = []
            Bridge.arrivesImmediately = false
            Bridge.accepts = true
            Bridge.requests = 0
            Activator.focused = []
            Activator.appOnlyActivations = 0
        }
        func bring(_ generation: UInt64) {
            Travel.bringHere(pid: 10, windowID: 42, appName: "A", screen: nil,
                             handoffSourcePID: 1, activationGeneration: generation)
        }
        defer { reset() }

        for arrival in [true, false] {
            reset()
            let generation = Activator.supersedePendingActivations(for: 10)
            bring(generation)
            suite.expect(Travel.DispatchQueue.main.pending.count == 1,
                         "a pending move schedules an arrival poll")
            _ = Activator.supersedePendingActivations()
            Bridge.membership = arrival ? [5] : []
            Travel.moveTimeout = -1
            Travel.DispatchQueue.main.drain()
            suite.expect(Activator.focused.isEmpty && Travel.placements == 0
                            && Travel.DispatchQueue.main.pending.isEmpty,
                         "a newer plain launch cancels stale arrival and timeout focus")
        }

        reset()
        let old = Activator.supersedePendingActivations(for: 10)
        Activator.activate(pid: 20, windowID: 99, appName: "B", handoffSourcePID: 1)
        bring(old)
        suite.expect(Bridge.requests == 0 && Activator.focused == [99],
                     "superseded initial delays neither submit a move nor reclaim focus")

        reset()
        Bridge.arrivesImmediately = true
        bring(Activator.supersedePendingActivations())
        suite.expect(Bridge.requests == 1 && Travel.placements == 1 && Activator.focused == [42],
                     "a current move still places and focuses its window on verified arrival")

        for accepted in [true, false] {
            reset()
            Bridge.accepts = accepted
            Travel.moveTimeout = -1
            bring(Activator.supersedePendingActivations())
            suite.expect(Activator.focused == [42] && Travel.placements == 0,
                         "a current timed-out or unavailable move retains normal activation")
        }

        reset()
        Travel.destinationSpace = nil
        bring(Activator.supersedePendingActivations())
        suite.expect(Bridge.requests == 0 && Activator.focused == [42],
                     "a window that became ineligible during the initial delay is activated without moving")
        reset()
        Travel.appTarget = nil
        Travel.bringHere(pid: 10, windowID: 42, appName: "A", screen: nil, handoffSourcePID: 1,
                         activationGeneration: Activator.supersedePendingActivations(), requiresAllWindowsHidden: true)
        suite.expect(Bridge.requests == 0 && Activator.focused.isEmpty && Activator.appOnlyActivations == 1,
                     "an app with a newly visible window uses app activation without targeting the old remote window")
    }
}

enum AppWindowTravelEligibilityTests {
    final class Permissions {
        static let shared = Permissions()
        var accessibility = true
    }
    struct App {
        static var exists = true
        static var hidden = false
        init?(processIdentifier: pid_t) { if !Self.exists { return nil } }
        var isHidden: Bool { Self.hidden }
    }
    enum Bridge {
        struct Topology {
            var visibleSpaces: Set<UInt64> = [1, 5]
            var fullscreenSpaces: Set<UInt64> = [9]
        }
        static var canRequestMoves = true
        static var current: Topology? = Topology()
        static var membership: [UInt64] = [2]
        static var minimized: Bool? = false
        static var orderedIn: Bool? = true
        static var hiddenWithApp: Set<CGWindowID>? = [42]
        static var destination: UInt64? = 1
        static func topology() -> Topology? { current }
        static func spaces(of windowID: CGWindowID) -> [UInt64] { membership }
        static func isMinimized(_ windowID: CGWindowID) -> Bool? { minimized }
        static func isWindowOrderedIn(_ windowID: CGWindowID) -> Bool? { orderedIn }
        static func windowsHiddenWithApp(among windows: [CGWindowID]) -> Set<CGWindowID>? { hiddenWithApp }
        static func isExcludedFromWindowCycle(_ windowID: CGWindowID) -> Bool { false }
        static func parentWindowID(of windowID: CGWindowID) -> CGWindowID? { nil }
        static func visibleSpace(on screen: NSScreen?, in topology: Topology) -> UInt64? { destination }
    }
    enum Travel {
        typealias SpaceWindowBridge = Bridge
        typealias NSRunningApplication = App
        typealias Permissions = AppWindowTravelEligibilityTests.Permissions
        static var hasWindow = true
        static func CGWindowListCopyWindowInfo(_ options: CGWindowListOption, _ windowID: CGWindowID) -> CFArray? {
            guard hasWindow else { return nil }
            return [[kCGWindowOwnerPID as String: NSNumber(value: 10),
                     kCGWindowBounds as String: CGRect(x: 0, y: 0, width: 800, height: 600).dictionaryRepresentation,
                     kCGWindowAlpha as String: NSNumber(value: 1)]] as CFArray
        }
    }
    static func run(_ suite: TestSuite) {
        func reset() {
            App.exists = true
            Permissions.shared.accessibility = true
            App.hidden = false
            Travel.hasWindow = true
            Bridge.current = Bridge.Topology()
            Bridge.membership = [2]
            Bridge.minimized = false
            Bridge.orderedIn = true
            Bridge.hiddenWithApp = [42]
            Bridge.destination = 1
            Bridge.canRequestMoves = true
        }
        func check(_ title: String, allowed: Bool = false, configure: () -> Void) {
            reset()
            configure()
            suite.expect(Travel.canBringHere(42, to: nil) == allowed, title)
        }
        defer { reset() }
        check("a live restored window on a hidden ordinary desktop can move", allowed: true) {}
        check("a window visible on another display stays there") { Bridge.membership = [5] }
        check("a minimized window stays on its desktop") { Bridge.minimized = true }
        check("an unreadable minimized state uses normal activation") { Bridge.minimized = nil }
        check("a window on every desktop stays put") { Bridge.membership = [1, 2, 5] }
        check("a fullscreen window stays in its Space") { Bridge.membership = [9] }
        check("a fullscreen destination cannot receive a window") { Bridge.destination = 9 }
        check("an ordered-out closed window cannot move") { Bridge.orderedIn = false }
        check("a real window of a hidden app can move", allowed: true) {
            App.hidden = true
            Bridge.orderedIn = false
        }
        check("a closed window of a hidden app cannot move") {
            App.hidden = true
            Bridge.hiddenWithApp = []
        }
        check("a closed window missing from the window server cannot move") { Travel.hasWindow = false }
        check("a terminated app cannot supply a move target") { App.exists = false }
        check("an unavailable bridge offers no move action") { Bridge.canRequestMoves = false }
        check("unreadable topology offers no move action") { Bridge.current = nil }
        check("missing Accessibility offers no move action") { Permissions.shared.accessibility = false }
    }
}

enum CommandBarWindowHistoryTests {
    enum Feature {
        case switcher, windowLayout, commandBar
        static var available: Set<Feature> = []
        var isAvailable: Bool { Self.available.contains(self) }
    }
    final class Permissions {
        static let shared = Permissions()
        var accessibility = true
    }
    enum Defaults {
        static var standard: UserDefaults!
    }
    final class Tracker {
        typealias AppFeature = Feature
        typealias Permissions = CommandBarWindowHistoryTests.Permissions
        typealias UserDefaults = Defaults
        var isRunning = false
        var starts = 0
        func start() {
            if !isRunning { starts += 1 }
            isRunning = true
        }
        func stop() { isRunning = false }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.command-bar-window-history"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        Defaults.standard = defaults
        defer {
            defaults.removePersistentDomain(forName: domain)
            Defaults.standard = nil
            Feature.available = []
            Permissions.shared.accessibility = true
        }
        let tracker = Tracker()
        Feature.available = [.commandBar]
        tracker.syncWithFeatures()
        suite.expect(!tracker.isRunning, "Command Bar out of the box observes nothing")
        defaults.set(true, forKey: DefaultsKey.commandBarBringWindowHere)
        tracker.syncWithFeatures()
        tracker.syncWithFeatures()
        suite.expect(tracker.isRunning && tracker.starts == 1,
                     "Command Bar alone tracks window use between invocations without restarting history")
        defaults.set(false, forKey: DefaultsKey.commandBarBringWindowHere)
        defaults.set(true, forKey: DefaultsKey.commandBarNewInstanceEnabled)
        tracker.syncWithFeatures()
        suite.expect(!tracker.isRunning, "new-instance support alone does not need window history")
        defaults.set(true, forKey: DefaultsKey.commandBarBringWindowHere)
        tracker.syncWithFeatures()
        suite.expect(tracker.isRunning, "turning bring-here back on tracks window use again")
        Permissions.shared.accessibility = false
        tracker.syncWithFeatures()
        suite.expect(!tracker.isRunning, "revoking Accessibility stops Command Bar's window watcher")
        Permissions.shared.accessibility = true
        tracker.syncWithFeatures()
        suite.expect(tracker.isRunning, "granting Accessibility restarts Command Bar's window watcher")
        Feature.available = []
        tracker.syncWithFeatures()
        suite.expect(!tracker.isRunning, "uninstalling the last history consumer stops observation")
        for feature in [Feature.switcher, .windowLayout] {
            Feature.available = [feature]
            Permissions.shared.accessibility = false
            tracker.syncWithFeatures()
            suite.expect(tracker.isRunning, "existing Switcher and Window Layout history lifecycles are preserved")
        }
    }
}
