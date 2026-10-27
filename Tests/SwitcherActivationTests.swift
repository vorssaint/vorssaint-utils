// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Production activation and bridge bodies run against transports that never
/// activate an app or post input. Native window ordering is validated separately.
enum SwitcherActivationTests {
    final class DeferredQueue {
        var pending: [() -> Void] = []
        func async(execute work: @escaping () -> Void) { pending.append(work) }
        func drain() {
            while !pending.isEmpty {
                let work = pending.removeFirst()
                work()
            }
        }
        func reset() { pending.removeAll() }
    }

    static var events: [String] = []
    static var records: [[UInt8]] = []
    static var canRaise = true
    static var generationAfterFocus: UInt64?

    final class App {
        static let current = App(processIdentifier: 1)!
        static var executablePaths: [pid_t: String] = [:]
        static var names: [pid_t: String] = [:]
        static var bundleIdentifiers: [pid_t: String] = [:]
        static var hiddenPIDs: Set<pid_t> = []
        let processIdentifier: pid_t
        var executableURL: URL? { Self.executablePaths[processIdentifier].map { URL(fileURLWithPath: $0) } }
        var localizedName: String? { Self.names[processIdentifier] }
        var bundleIdentifier: String? { Self.bundleIdentifiers[processIdentifier] }
        var isHidden: Bool { Self.hiddenPIDs.contains(processIdentifier) }
        var isTerminated = false
        init?(processIdentifier: pid_t) {
            guard processIdentifier > 0 else { return nil }
            self.processIdentifier = processIdentifier
        }
        func unhide() { events.append("unhide") }
        @discardableResult func activate(from: App, options: NSApplication.ActivationOptions) -> Bool {
            events.append("activate:\(processIdentifier):\(options.contains(.activateAllWindows))")
            return true
        }
        @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool { false }
    }
    enum Handoff {
        static func yield(to app: App) { events.append("yield:\(app.processIdentifier)") }
    }
    enum Activator {
        typealias NSRunningApplication = App
        typealias ActivationHandoff = Handoff
        typealias SpaceWindowBridge = Bridge
        static let activationAXQueue = DeferredQueue()
        static let activationMainQueue = DeferredQueue()
        /// Whether the app cannot describe the target window at all.
        static var targetResolutionFails = false
        static var currentGeneration: UInt64 = 1
        static var frontmostPID: pid_t? = 20
        /// The app's Accessibility permission, as the activation sees it.
        enum Permissions {
            static let shared = Session()
            final class Session {
                var accessibility = true
            }
        }
        static func isCurrentActivation(_ generation: UInt64) -> Bool {
            currentGeneration == generation
        }
        /// The per-window attribute read the compiled activation ends up
        /// calling. The test build compiles the real caller, so this stand-in
        /// performs the same read the production wrapper does.
        static func minimizedState(of axWindow: AXUIElement) -> Bool? {
            SwitcherActivationTargetWindow.minimizedState(of: axWindow)
        }
        /// The target window of one activation, resolved once and shared.
        static func makeTarget(windowID: CGWindowID) -> SwitcherActivationTargetWindow {
            SwitcherActivationTargetWindow(windowID: windowID) {
                guard !targetResolutionFails else { return nil }
                let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
                AXUIElementSetMessagingTimeout(element, Float(0.05))
                return element
            }
        }
        static func isActivationTargetFrontmost(_ app: App, windowOwnerPID: pid_t) -> Bool {
            guard let frontmostPID else { return false }
            if frontmostPID == app.processIdentifier || frontmostPID == windowOwnerPID { return true }
            guard let bundleIdentifier = app.bundleIdentifier,
                  let frontmostBundleIdentifier = App.bundleIdentifiers[frontmostPID] else { return false }
            return frontmostBundleIdentifier == bundleIdentifier
        }
        @discardableResult static func prepareWindowForActivation(windowID: CGWindowID,
                                                                   pid: pid_t,
                                                                   generation: UInt64? = nil) -> Bool { true }
        @discardableResult static func focusWindow(windowID: CGWindowID,
                                                   pid: pid_t,
                                                   makeAppFrontmost: Bool = true,
                                                   generation: UInt64? = nil) -> Bool {
            events.append("raise:\(windowID):\(pid):\(makeAppFrontmost)")
            if let nextGeneration = SwitcherActivationTests.generationAfterFocus {
                currentGeneration = nextGeneration
                SwitcherActivationTests.generationAfterFocus = nil
            }
            return canRaise
        }
    }
    enum Bridge {
        typealias NSRunningApplication = App
        static var processForPID: ((pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus)?
        static var setFrontProcess: ((UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError)?
        static var postEventRecord: ((UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError)?
        /// The window server's answer for a window, when it has one.
        static var windowServerMinimizedState: ((CGWindowID) -> Bool?)?
        /// The windows the window server was asked about.
        static var windowServerMinimizedReads: [CGWindowID] = []
        static func minimizedState(of windowID: CGWindowID) -> Bool? {
            windowServerMinimizedReads.append(windowID)
            return windowServerMinimizedState?(windowID)
        }
    }
    static func reset(raise: Bool = true, front: CGError = .success, down: CGError = .success, up: CGError = .success) {
        events = []; records = []; canRaise = raise
        generationAfterFocus = nil
        Activator.currentGeneration = 1
        Activator.frontmostPID = 20
        Activator.activationAXQueue.reset()
        Activator.activationMainQueue.reset()
        Activator.targetResolutionFails = false
        Activator.Permissions.shared.accessibility = true
        Bridge.windowServerMinimizedState = nil
        Bridge.windowServerMinimizedReads = []
        App.executablePaths = [:]; App.names = [:]; App.bundleIdentifiers = [:]; App.hiddenPIDs = []
        Bridge.processForPID = { pid, _ in events.append("owner:\(pid)"); return noErr }
        Bridge.setFrontProcess = { _, id, _ in events.append("front:\(id)"); return front }
        Bridge.postEventRecord = { _, bytes in
            events.append("event:\(bytes[8])")
            records.append(Array(UnsafeBufferPointer(start: bytes, count: 0x100)))
            return bytes[8] == 1 ? down : up
        }
    }
    static func run(_ suite: TestSuite) {
        let app = App(processIdentifier: 20)!
        let windowPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: true)
        func select(owner: pid_t = 20, generation: UInt64 = 1) {
            Activator.activateApp(app,
                                  plan: windowPlan,
                                  windowID: 77,
                                  windowOwnerPID: owner,
                                  generation: generation)
        }
        func selectWithoutGeneration(owner: pid_t = 20) {
            Activator.activateApp(app,
                                  plan: windowPlan,
                                  windowID: 77,
                                  windowOwnerPID: owner)
        }
        reset(); select()
        suite.expect(events == ["owner:20", "front:77", "event:1"]
                && Activator.activationAXQueue.pending.count == 1,
                     "exact-window routing returns before remote Accessibility focus")
        Activator.activationAXQueue.drain()
        suite.expect(events == ["owner:20", "front:77", "event:1", "raise:77:20:false"],
                     "a delivered window selection raises the exact window without activating every sibling")
        reset(); selectWithoutGeneration()
        suite.expect(events == ["owner:20", "front:77", "event:1", "raise:77:20:false"]
                && Activator.activationAXQueue.pending.isEmpty,
                     "an unguarded legacy exact-window call preserves synchronous focus")
        reset(raise: false); selectWithoutGeneration()
        suite.expect(events.filter { $0 == "raise:77:20:false" }.count == 2
                && events.contains("activate:20:false")
                && Activator.activationAXQueue.pending.isEmpty,
                     "an unguarded legacy focus failure preserves synchronous cooperative recovery")
        // The press that makes the window key must name the window and aim far
        // past its bottom-right: a point near the frame's corner hits the resize
        // border, and some apps turn a NaN point into their top-left corner.
        // Compatibility layers must skip this input path altogether.
        let windowIDBytes = withUnsafeBytes(of: CGWindowID(77).littleEndian, Array.init)
        let farPointBytes = withUnsafeBytes(of: CGPoint(x: 300_000, y: 300_000), Array.init)
        suite.expect(records.count == 1 && records.allSatisfy { record in
            record[0x04] == 0xf8 && record[0x3a] == 0x10
                && Array(record[0x3c..<0x40]) == windowIDBytes
                && Array(record[0x20..<0x30]) == farPointBytes
        }, "the key-making press names the window and points far past its bottom-right")
        suite.expect(records.map { $0[0x08] } == [1], "the key-making event is a lone press with no release")
        reset(raise: false); select()
        suite.expect(!events.contains("activate:20:false")
                && Activator.activationAXQueue.pending.count == 1,
                     "a selected window defers Accessibility focus before considering recovery")
        Activator.activationAXQueue.drain()
        suite.expect(events.contains("raise:77:20:false")
                && Activator.activationMainQueue.pending.count == 1,
                     "failed exact-window focus queues cooperative recovery")
        Activator.activationMainQueue.drain()
        suite.expect(events.contains("activate:20:false"),
                     "a window lost by Accessibility retains cooperative recovery")

        reset(raise: false); select()
        generationAfterFocus = 2
        Activator.activationAXQueue.drain()
        suite.expect(Activator.activationMainQueue.pending.isEmpty
                && !events.contains("activate:20:false"),
                     "a newer switch during remote focus cancels stale cooperative recovery")
        reset(raise: false); select()
        Activator.activationAXQueue.drain()
        Activator.currentGeneration = 2
        Activator.activationMainQueue.drain()
        suite.expect(!events.contains("activate:20:false"),
                     "a newer switch before main-thread recovery prevents stale activation")
        reset(raise: false); select()
        Activator.activationAXQueue.drain()
        Activator.frontmostPID = 99
        Activator.activationMainQueue.drain()
        suite.expect(!events.contains("activate:20:false"),
                     "a manual foreground change suppresses delayed cooperative activation")
        reset(raise: false); App.bundleIdentifiers[20] = "com.example.host"
        App.bundleIdentifiers[21] = "com.example.host"
        select()
        Activator.activationAXQueue.drain()
        Activator.frontmostPID = 21
        Activator.activationMainQueue.drain()
        suite.expect(events.contains("activate:20:false"),
                     "a same-bundle frontmost process remains a valid activation target")
        reset(raise: false); select(owner: 30)
        Activator.activationAXQueue.drain()
        Activator.frontmostPID = 30
        Activator.activationMainQueue.drain()
        suite.expect(events.contains("activate:20:false"),
                     "an accessory owner remains a valid frontmost target for host recovery")
        reset(); select()
        Activator.currentGeneration = 2
        Activator.activationAXQueue.drain()
        suite.expect(!events.contains("raise:77:20:false"),
                     "deferred Accessibility focus checks the activation generation before starting")

        reset(front: .failure); select()
        suite.expect(!events.contains("event:1") && events.contains("activate:20:false"), "a refused front request uses the previous activation path")
        for down in [CGError.success, .failure] {
            reset(down: down); select()
            suite.expect(events.contains("activate:20:false") == (down != .success),
                         "a refused press triggers recovery")
            suite.expect(!events.contains("event:2"), "no release is ever posted")
            Activator.activationAXQueue.drain()
        }
        reset(); Bridge.postEventRecord = nil; select()
        suite.expect(!events.contains("front:77") && events.contains("activate:20:false"), "missing event transport cannot claim success")
        reset(); Bridge.setFrontProcess = nil; select()
        suite.expect(events.contains("activate:20:false"), "missing front transport recovers")
        reset(); Bridge.processForPID = { _, _ in -1 }; select()
        suite.expect(events.contains("activate:20:false"), "missing process identity recovers")
        reset(); select(owner: 30)
        suite.expect(events.prefix(3) == ["yield:20", "activate:20:false", "owner:30"],
                     "host menus are activated before fronting an accessory owner's window")
        Activator.activationAXQueue.drain()
        suite.expect(events.last == "raise:77:30:false", "helper window focusing does not replace host activation")
        // Unhiding an app that is not hidden raises every one of its windows.
        reset(); _ = Activator.activateSource(pid: 20, windowID: nil, windowOwnerPID: nil)
        suite.expect(events == ["yield:20", "activate:20:false"],
                     "returning to a visible source without a saved window raises none of its other windows")
        reset(); App.hiddenPIDs = [20]
        _ = Activator.activateSource(pid: 20, windowID: 77, windowOwnerPID: 20)
        suite.expect(events.first == "unhide" && events.contains("front:77"), "a hidden source is shown again before its window returns")
        reset(); _ = Activator.activateSource(pid: 20, windowID: 77, windowOwnerPID: 20)
        suite.expect(!events.contains("activate:20:true") && events.contains("front:77"), "returning to an identified source still selects its window")
        reset(); Activator.activateApp(app, plan: SwitcherSupport.activationPlan(targetsSpecificWindow: false))
        suite.expect(events == ["yield:20", "activate:20:true"], "explicit app selection still brings all its windows forward")
        reset(); let restored = Activator.activateSource(pid: -1, windowID: nil, windowOwnerPID: nil)
        suite.expect(!restored && events.isEmpty, "an exited source cannot receive restoration")

        for path in ["/usr/local/bin/wine64-preloader",
                     "/Applications/Game.app/Contents/MacOS/wine64-preloader",
                     "/Users/u/Library/Bottles/winetemp-8f3a21/Game"] {
            reset(); App.executablePaths[20] = path
            select()
            Activator.activationAXQueue.drain()
            suite.expect(events == ["owner:20", "front:77", "raise:77:20:false"] && records.isEmpty,
                         "Wine receives exact-window activation without a mouse press: \(path)")
            select()
            Activator.activationAXQueue.drain()
            suite.expect(records.isEmpty, "a repeated focus pass never injects a game mouse button")
        }
        reset(); App.names[20] = "wine-preloader"
        Bridge.postEventRecord = nil
        select()
        Activator.activationAXQueue.drain()
        suite.expect(events.contains("front:77") && !events.contains("activate:20:false") && records.isEmpty,
                     "Wine can be focused without an event transport when only its process name is known")
        reset(raise: false); App.executablePaths[30] = "/usr/local/bin/wine64-preloader"
        select(owner: 30)
        Activator.activationAXQueue.drain()
        Activator.activationMainQueue.drain()
        suite.expect(events.contains("activate:20:false") && records.isEmpty,
                     "a Wine window owner retains cooperative recovery without clicking, even under a native host")
        reset(front: .failure); App.names[20] = "wine-preloader"
        select()
        suite.expect(events.contains("activate:20:false") && records.isEmpty,
                     "a failed Wine front request falls back to app activation without a mouse event")

        func window(_ id: CGWindowID, owner: pid_t, layer: Int) -> [String: Any] {
            [kCGWindowNumber as String: NSNumber(value: id),
             kCGWindowOwnerPID as String: NSNumber(value: owner),
             kCGWindowLayer as String: NSNumber(value: layer)]
        }
        let windowInfo = [window(77, owner: 20, layer: 0),
                          window(101, owner: 20, layer: 3),
                          window(201, owner: 30, layer: 0)]
        let snapshot = SwitcherWindowServerSnapshot(windowInfo: windowInfo,
                                                     capturesActivationBaseline: true)
        let validated = snapshot.activationWindowIDs(ownerPID: 20, targetWindowID: 77,
                                                      currentWindowIDs: [77, 101, 201])
        suite.expect(validated == [77, 101],
                     "a validated owner baseline retains existing auxiliary windows outside the normal layer")
        suite.expect(snapshot.normalLevelWindowIDs == [77, 201]
                        && snapshot.normalLevelOwnerPIDs == [20, 30],
                     "collecting a complete owner baseline does not change normal-window enumeration metadata")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 20, targetWindowID: 77,
                                                  currentWindowIDs: [77, 201]) == [77],
                     "validation removes closed owner windows from the activation baseline")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 20, targetWindowID: 77,
                                                  currentWindowIDs: [77, 101, 201, 333]) == nil,
                     "any new global window forces a fresh owner snapshot instead of hiding a new dialog")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 20, targetWindowID: 77,
                                                  currentWindowIDs: [101, 201]) == nil,
                     "a missing target cannot validate a stale activation baseline")
        suite.expect(snapshot.activationWindowIDs(ownerPID: 30, targetWindowID: 77,
                                                  currentWindowIDs: [77, 101, 201]) == nil,
                     "an app identity cannot substitute for the selected window's actual owner")
        let uncaptured = SwitcherWindowServerSnapshot(windowInfo: windowInfo,
                                                       capturesActivationBaseline: false)
        suite.expect(uncaptured.activationWindowIDs(ownerPID: 20, targetWindowID: 77,
                                                    currentWindowIDs: [77, 101, 201]) == nil,
                     "a walk without a complete owner map requires a fresh activation snapshot")
        let incomplete = SwitcherWindowServerSnapshot(
            windowInfo: windowInfo + [[kCGWindowNumber as String: NSNumber(value: 333)]],
            capturesActivationBaseline: true)
        suite.expect(incomplete.activationWindowIDs(ownerPID: 20, targetWindowID: 77,
                                                     currentWindowIDs: [77, 101, 201, 333]) == nil,
                     "missing ownership metadata cannot turn a partial owner map into a validated baseline")
        let retryState = SwitcherWindowFocusRetryState(targetWindowID: 77,
                                                        targetStartedMinimized: false,
                                                        targetWasObservedRestored: true,
                                                        knownWindowIDs: validated ?? [])
        suite.expect(SwitcherSupport.shouldContinueFocusRetry(
            targetPID: 20, sourcePID: 30, frontmostPID: 20,
            targetIsMinimized: false, targetStartedMinimized: false,
            knownWindowIDs: retryState.knownWindowIDs,
            targetAppWindowIDs: [77, 101], targetAppFocusedWindowID: 101, ownPID: 99),
            "a pre-existing auxiliary window is not mistaken for a new window during retry")
        suite.expect(!SwitcherSupport.shouldContinueFocusRetry(
            targetPID: 20, sourcePID: 30, frontmostPID: 20,
            targetIsMinimized: false, targetStartedMinimized: false,
            knownWindowIDs: retryState.knownWindowIDs,
            targetAppWindowIDs: [77, 101, 333], targetAppFocusedWindowID: 333, ownPID: 99),
            "a new dialog after validation ends retry instead of reclaiming its focus")

        // A pass that stood down does not come back for the old target, not
        // even when the late answer of its own observation finds the target
        // app in front again.
        let stoodDownState = SwitcherWindowFocusRetryState(targetWindowID: 77,
                                                           targetStartedMinimized: false,
                                                           targetWasObservedRestored: true,
                                                           knownWindowIDs: [77, 101])
        suite.expect(!stoodDownState.shouldContinue(targetPID: 10,
                                                    sourcePID: 20,
                                                    frontmostPID: 30,
                                                    targetMinimizedState: false,
                                                    targetAppWindowIDs: [77, 101],
                                                    targetAppFocusedWindowID: 77,
                                                    ownPID: 99),
                     "a pass that saw another app in front stands the retry down")
        suite.expect(!stoodDownState.isActive,
                     "the retry state records that it stood down")
        suite.expect(!stoodDownState.shouldContinue(targetPID: 10,
                                                    sourcePID: 20,
                                                    frontmostPID: 10,
                                                    targetMinimizedState: false,
                                                    targetAppWindowIDs: [77, 101],
                                                    targetAppFocusedWindowID: 77,
                                                    ownPID: 99),
                     "a late answer cannot bring the old target back after the retry stood down")

        // The fresh state of an activation target. The window server answers
        // without the other app's help, so an ordinary target never waits on
        // the Accessibility of an app that is busy answering something else.
        reset()
        Bridge.windowServerMinimizedState = { _ in true }
        let minimizedTarget = Activator.activationMinimizedState(target: Activator.makeTarget(windowID: 77),
                                                                 pid: 20)
        suite.expect(minimizedTarget.state == true
                && minimizedTarget.source == .windowServer,
                     "a window the window server holds minimized is read from the window server")
        reset()
        Bridge.windowServerMinimizedState = { _ in false }
        let restoredTarget = Activator.activationMinimizedState(target: Activator.makeTarget(windowID: 77),
                                                                 pid: 20)
        suite.expect(restoredTarget.state == false
                && restoredTarget.source == .windowServer,
                     "a window the window server holds restored is read from the window server")
        reset()
        Bridge.windowServerMinimizedState = { _ in nil }
        let fallbackTarget = Activator.activationMinimizedState(target: Activator.makeTarget(windowID: 77),
                                                                 pid: 20)
        suite.expect(fallbackTarget.source == .accessibility
                && fallbackTarget.state == nil,
                     "a window the window server cannot answer falls back to the app's Accessibility")
        // A window the app cannot describe stays unknown; the step that
        // asked falls back to its own lookup.
        reset()
        Bridge.windowServerMinimizedState = { _ in nil }
        Activator.targetResolutionFails = true
        let unknownTarget = Activator.activationMinimizedState(target: Activator.makeTarget(windowID: 77),
                                                                pid: 20)
        suite.expect(unknownTarget.state == nil
                && unknownTarget.source == .accessibility,
                     "a state the app cannot resolve stays unknown")
        // Without Accessibility permission the app is not asked at all.
        reset()
        Bridge.windowServerMinimizedState = { _ in nil }
        Activator.Permissions.shared.accessibility = false
        let untrusted = Activator.activationMinimizedState(target: Activator.makeTarget(windowID: 77),
                                                           pid: 20)
        suite.expect(untrusted.state == nil
                && untrusted.source == .accessibility,
                     "without Accessibility permission the state stays unknown")
        // The state belongs to the target window: the source window's own
        // state is never read on the way to the target.
        reset()
        Bridge.windowServerMinimizedState = { windowID in windowID == 88 ? true : false }
        let targetOnly = Activator.activationMinimizedState(target: Activator.makeTarget(windowID: 77),
                                                            pid: 20)
        suite.expect(targetOnly.state == false
                && Bridge.windowServerMinimizedReads == [77],
                     "the fresh state is read for the target window, never for the source window")
    }
}
