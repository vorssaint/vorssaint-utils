// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Production activation and bridge bodies run against transports that never
/// activate an app or post input. Native window ordering is validated separately.
enum SwitcherActivationTests {
    static var events: [String] = []
    static var records: [[UInt8]] = []
    static var frontOptions: [UInt32] = []
    static var canRaise = true

    final class App {
        static let current = App(processIdentifier: 1)!
        static var executablePaths: [pid_t: String] = [:]
        static var names: [pid_t: String] = [:]
        static var hiddenPIDs: Set<pid_t> = []
        let processIdentifier: pid_t
        var executableURL: URL? { Self.executablePaths[processIdentifier].map { URL(fileURLWithPath: $0) } }
        var localizedName: String? { Self.names[processIdentifier] }
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
        static var focusedID: CGWindowID? = 66
        static func focusedWindowID(for pid: pid_t) -> CGWindowID? { focusedID }
        @discardableResult static func prepareWindowForActivation(windowID: CGWindowID, pid: pid_t) -> Bool { true }
        @discardableResult static func focusWindow(windowID: CGWindowID, pid: pid_t, makeAppFrontmost: Bool = true) -> Bool {
            events.append("raise:\(windowID):\(pid):\(makeAppFrontmost)")
            return canRaise
        }
    }
    enum Bridge {
        typealias NSRunningApplication = App
        typealias WindowActivator = Activator
        typealias NSWorkspace = Workspace
        typealias DispatchQueue = Queue
        static var processForPID: ((pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus)?
        static var setFrontProcess: ((UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError)?
        static var postEventRecord: ((UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError)?
    }

    /// The production hidden-Space raise and source staging methods run with
    /// inert elements. Only the orchestration is tested; macOS travel is not.
    enum HiddenSpaceActivator {
        final class Element: NSObject {
            let pid: pid_t
            let windowID: CGWindowID?
            init(pid: pid_t, windowID: CGWindowID? = nil) {
                self.pid = pid
                self.windowID = windowID
            }
        }
        struct PermissionState { var accessibility = true }
        enum Permissions { static var shared = PermissionState() }
        enum SpaceWindowBridge {
            static var hiddenWindows: Set<CGWindowID> = []
            static func isParkedOnHiddenSpace(_ windowID: CGWindowID) -> Bool {
                hiddenWindows.contains(windowID)
            }
        }
        static var transportEvents: [String] = []
        static var missingWindows: Set<CGWindowID> = []
        static var minimizedWindows: Set<CGWindowID> = []
        static var raiseResult: AXError = .success

        static func reset() {
            Permissions.shared = PermissionState()
            SpaceWindowBridge.hiddenWindows = []
            transportEvents = []
            missingWindows = []
            minimizedWindows = []
            raiseResult = .success
        }
        static func AXUIElementCreateApplication(_ pid: pid_t) -> Element {
            transportEvents.append("app:\(pid)")
            return Element(pid: pid)
        }
        @discardableResult
        static func AXUIElementSetMessagingTimeout(_ element: Element, _ timeout: Float) -> AXError {
            transportEvents.append("timeout:\(element.pid)")
            return .success
        }
        static func axElement(windowID: CGWindowID, in app: Element, pid: pid_t? = nil) -> Element? {
            let mode = pid.map { "remote:\($0)" } ?? "published"
            transportEvents.append("resolve:\(windowID):\(app.pid):\(mode)")
            guard !missingWindows.contains(windowID) else { return nil }
            return Element(pid: app.pid, windowID: windowID)
        }
        static func AXUIElementCopyAttributeValue(_ element: Element, _ attribute: CFString,
                                                  _ value: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
            transportEvents.append("read:\(element.windowID ?? 0):\(attribute)")
            guard attribute as String == kAXMinimizedAttribute as String,
                  let windowID = element.windowID else { return .attributeUnsupported }
            value.pointee = NSNumber(value: minimizedWindows.contains(windowID))
            return .success
        }
        @discardableResult
        static func AXUIElementSetAttributeValue(_ element: Element, _ attribute: CFString,
                                                 _ value: CFTypeRef) -> AXError {
            transportEvents.append("set:\(element.windowID ?? 0):\(attribute)")
            return .success
        }
        @discardableResult
        static func AXUIElementPerformAction(_ element: Element, _ action: CFString) -> AXError {
            transportEvents.append("action:\(element.windowID ?? 0):\(action)")
            return raiseResult
        }
    }
    final class Workspace {
        static let shared = Workspace()
        var frontmostApplication = App(processIdentifier: 20)
    }
    final class Queue {
        static let main = Queue()
        var pending: [() -> Void] = []
        func asyncAfter(deadline: DispatchTime, execute work: @escaping () -> Void) {
            pending.append(work)
        }
        func finish() {
            let work = pending
            pending = []
            work.forEach { $0() }
        }
    }
    static func reset(raise: Bool = true, front: CGError = .success, down: CGError = .success, up: CGError = .success) {
        events = []; records = []; frontOptions = []; canRaise = raise
        Queue.main.pending = []; Activator.focusedID = 66
        Workspace.shared.frontmostApplication = App(processIdentifier: 20)
        App.executablePaths = [:]; App.names = [:]; App.hiddenPIDs = []
        Bridge.processForPID = { pid, _ in events.append("owner:\(pid)"); return noErr }
        Bridge.setFrontProcess = { _, id, options in
            events.append("front:\(id)"); frontOptions.append(options); return front
        }
        Bridge.postEventRecord = { _, bytes in
            events.append("event:\(bytes[8])")
            records.append(Array(UnsafeBufferPointer(start: bytes, count: 0x100)))
            return bytes[8] == 1 ? down : up
        }
    }
    static func run(_ suite: TestSuite) {
        let app = App(processIdentifier: 20)!
        let windowPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: true)
        func select(owner: pid_t = 20) { Activator.activateApp(app, plan: windowPlan, windowID: 77, windowOwnerPID: owner) }
        reset(); select()
        suite.expect(events == ["owner:20", "front:77", "event:1", "raise:77:20:false"],
                     "a delivered window selection raises the exact window without activating every sibling")
        suite.expect(frontOptions == [0x200], "intentional window activation keeps its user-generated front request")
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
        suite.expect(events.contains("activate:20:false"), "a window lost by Accessibility retains cooperative recovery")
        reset(front: .failure); select()
        suite.expect(!events.contains("event:1") && events.contains("activate:20:false"), "a refused front request uses the previous activation path")
        for down in [CGError.success, .failure] {
            reset(down: down); select()
            suite.expect(events.contains("activate:20:false") == (down != .success),
                         "a refused press triggers recovery")
            suite.expect(!events.contains("event:2"), "no release is ever posted")
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
            suite.expect(events == ["owner:20", "front:77", "raise:77:20:false"] && records.isEmpty,
                         "Wine receives exact-window activation without a mouse press: \(path)")
            select()
            suite.expect(records.isEmpty, "a repeated focus pass never injects a game mouse button")
        }
        reset(); App.names[20] = "wine-preloader"
        Bridge.postEventRecord = nil
        select()
        suite.expect(events.contains("front:77") && !events.contains("activate:20:false") && records.isEmpty,
                     "Wine can be focused without an event transport when only its process name is known")
        reset(raise: false); App.executablePaths[30] = "/usr/local/bin/wine64-preloader"
        select(owner: 30)
        suite.expect(events.contains("activate:20:false") && records.isEmpty,
                     "a Wine window owner retains cooperative recovery without clicking, even under a native host")
        reset(front: .failure); App.names[20] = "wine-preloader"
        select()
        suite.expect(events.contains("activate:20:false") && records.isEmpty,
                     "a failed Wine front request falls back to app activation without a mouse event")
        runHiddenSpaceContracts(suite)
        runFocusWithoutRaise(suite)
    }

    private static func runHiddenSpaceContracts(_ suite: TestSuite) {
        typealias AX = HiddenSpaceActivator
        func raise(pid: pid_t = 20) -> Bool {
            AX.raiseWindowOnHiddenSpace(windowID: 77, pid: pid)
        }
        AX.reset(); AX.Permissions.shared.accessibility = false
        suite.expect(!raise() && AX.transportEvents.isEmpty,
                     "a hidden-Space raise does not query Accessibility without permission")
        for pid in [pid_t(-1), 0, ProcessInfo.processInfo.processIdentifier] {
            AX.reset()
            suite.expect(!raise(pid: pid) && AX.transportEvents.isEmpty,
                         "a hidden-Space raise rejects invalid or own process \(pid) before any AX call")
        }
        AX.reset(); AX.missingWindows = [77]
        let unresolved = raise()
        suite.expect(!unresolved && AX.transportEvents == ["app:20", "timeout:20", "resolve:77:20:remote:20"],
                     "an unresolved hidden-Space target cannot mutate or raise another window")
        for result in [AXError.success, .cannotComplete] {
            AX.reset(); AX.raiseResult = result
            let raised = raise()
            suite.expect(raised == (result == .success),
                         "hidden-Space raise reports the AX action result rather than resolution alone")
            suite.expect(AX.transportEvents.last == "action:77:AXRaise"
                            && AX.transportEvents.filter { $0.hasPrefix("action:") }.count == 1,
                         "the hidden-Space action raises only the selected window")
            suite.expect(AX.transportEvents.contains("resolve:77:20:remote:20"),
                         "hidden-Space lookup opts into remote resolution for the actual window owner")
        }

        let windowPlan = SwitcherSupport.activationPlan(targetsSpecificWindow: true)
        func stage(plan: SwitcherActivationPlan? = nil) -> Bool {
            AX.stageSourceBehindTargetIfNeeded(targetWindowID: 77, targetPID: 20, targetWindowOwnerPID: 40,
                                              sourcePID: 10, sourceWindowID: 55, sourceWindowOwnerPID: 30,
                                              activationPlan: plan ?? windowPlan)
        }
        let hiddenCases: [Set<CGWindowID>] = [[55], [77], [55, 77]]
        for hidden in hiddenCases {
            AX.reset(); AX.SpaceWindowBridge.hiddenWindows = hidden
            suite.expect(!stage() && AX.transportEvents.isEmpty,
                         "source staging does not query or raise a window when either Space is hidden: \(hidden)")
        }
        AX.reset(); AX.Permissions.shared.accessibility = false
        suite.expect(!stage() && AX.transportEvents.isEmpty,
                     "source staging retains the Accessibility permission guard")
        AX.reset()
        suite.expect(!stage(plan: SwitcherSupport.activationPlan(targetsSpecificWindow: false))
                        && AX.transportEvents.isEmpty,
                     "app-only activation never stages a particular source window")
        AX.reset()
        let staged = stage()
        suite.expect(staged && AX.transportEvents.filter { $0.hasPrefix("action:") }
                        == ["action:55:AXRaise", "action:77:AXRaise"],
                     "visible source staging preserves the source-then-target raise order")
        suite.expect(AX.transportEvents.filter { $0.hasPrefix("resolve:") }
                        == ["resolve:55:30:published", "resolve:77:40:published"],
                     "source staging queries window owners and does not repeat remote scans")
        AX.reset(); AX.minimizedWindows = [55]
        suite.expect(!stage() && !AX.transportEvents.contains { $0.hasPrefix("action:") || $0.hasPrefix("set:") },
                     "source staging leaves a minimized source untouched")
        for missing in [CGWindowID(55), 77] {
            AX.reset(); AX.missingWindows = [missing]
            suite.expect(!stage() && !AX.transportEvents.contains { $0.hasPrefix("action:") || $0.hasPrefix("set:") },
                         "source staging does not raise a substitute when window \(missing) cannot be resolved")
        }
        AX.reset()
    }

    static func runFocusWithoutRaise(_ suite: TestSuite) {
        var current = true
        var results: [Bool] = []
        func focus(replacing oldWindow: CGWindowID? = nil) {
            Bridge.focusWithoutRaise(77, ownerPID: 20, replacing: oldWindow,
                                     while: { current }, completion: { results.append($0) })
        }
        func resetFocus() {
            reset(); current = true; results = []
        }
        func focusRecords() -> [(CGWindowID, UInt8)] {
            records.map { record in
                let id = record[0x3c..<0x40].enumerated().reduce(UInt32(0)) {
                    $0 | UInt32($1.element) << (8 * $1.offset)
                }
                return (id, record[0x8a])
            }
        }
        func hasFocusRecords(_ expected: [(CGWindowID, UInt8)]) -> Bool {
            let actual = focusRecords()
            return actual.count == expected.count && zip(actual, expected).allSatisfy {
                $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1
            } && records.allSatisfy { $0[0x04] == 0xf8 && $0[0x08] == 0x0d }
        }

        resetFocus(); Workspace.shared.frontmostApplication = App(processIdentifier: 30)
        focus()
        suite.expect(results == [true] && frontOptions == [0x400] && hasFocusRecords([(77, 1)]),
                     "hover activates another app without ordering windows or posting a mouse press")
        suite.expect(Queue.main.pending.isEmpty,
                     "cross-app focus has no same-app handoff to delay")

        resetFocus(); focus(replacing: 66)
        suite.expect(results.isEmpty && frontOptions.isEmpty && hasFocusRecords([(66, 2)])
                        && Queue.main.pending.count == 1,
                     "same-app hover releases the old window before scheduling the new focus")
        Queue.main.finish()
        suite.expect(results == [true] && frontOptions == [0x400]
                        && hasFocusRecords([(66, 2), (77, 1)]),
                     "same-app hover gives the target keyboard focus without ordering windows or clicking")

        for oldWindow: CGWindowID? in [nil, 66] {
            resetFocus(); current = false; focus(replacing: oldWindow)
            suite.expect(results == [false] && events.isEmpty && Queue.main.pending.isEmpty,
                         "an obsolete hover cannot activate or release any window")
            for missing in 0..<3 {
                resetFocus()
                if missing == 0 { Bridge.setFrontProcess = nil }
                if missing == 1 { Bridge.processForPID = nil }
                if missing == 2 { Bridge.postEventRecord = nil }
                focus(replacing: oldWindow)
                suite.expect(results == [false] && events.isEmpty && Queue.main.pending.isEmpty,
                             "unavailable focus transport leaves the old window alone without a raising fallback")
            }
            resetFocus(); Bridge.processForPID = { _, _ in -1 }; focus(replacing: oldWindow)
            suite.expect(results == [false] && frontOptions.isEmpty && records.isEmpty,
                         "an unknown process cannot receive hover focus")
        }

        for reported: CGWindowID? in [nil, 66, 88] {
            for frontPID: pid_t in [20, 30] {
                resetFocus(); focus(replacing: 66); current = false
                Activator.focusedID = reported
                Workspace.shared.frontmostApplication = App(processIdentifier: frontPID)
                Queue.main.finish()
                let restores = reported == 66 && frontPID == 20
                suite.expect(results == [false] && frontOptions.isEmpty
                                && hasFocusRecords(restores ? [(66, 2), (66, 1)] : [(66, 2)]),
                             "cancelled hover restores only the verified old focus without activating an app")
            }
        }

        resetFocus(); Bridge.postEventRecord = { _, _ in .failure }; focus(replacing: 66)
        suite.expect(results == [false] && frontOptions.isEmpty && Queue.main.pending.isEmpty,
                     "a failed focus release stops the handoff before activating its target")
        for oldWindow: CGWindowID? in [nil, 66] {
            resetFocus()
            Bridge.setFrontProcess = { _, _, options in frontOptions.append(options); return .failure }
            focus(replacing: oldWindow); Queue.main.finish()
            suite.expect(results == [false] && frontOptions == [0x400]
                            && hasFocusRecords(oldWindow == nil ? [] : [(66, 2), (66, 1)]),
                         "a refused no-raise activation reports failure and restores any released old focus")

            resetFocus()
            Bridge.postEventRecord = { _, bytes in
                records.append(Array(UnsafeBufferPointer(start: bytes, count: 0x100)))
                return bytes[0x3c] == 77 ? .failure : .success
            }
            focus(replacing: oldWindow); Queue.main.finish()
            suite.expect(results == [false] && frontOptions == [0x400]
                            && hasFocusRecords(oldWindow == nil ? [(77, 1)] : [(66, 2), (77, 1), (66, 1)]),
                         "an undelivered focus gain reports failure without falling back to a click or raise")

            resetFocus()
            var lookups = 0
            Bridge.processForPID = { _, _ in
                lookups += 1
                return lookups == (oldWindow == nil ? 2 : 3) ? -1 : noErr
            }
            focus(replacing: oldWindow); Queue.main.finish()
            suite.expect(results == [false] && frontOptions == [0x400]
                            && hasFocusRecords(oldWindow == nil ? [] : [(66, 2), (66, 1)]),
                         "losing the process after activation cannot claim that keyboard focus was delivered")
        }

        resetFocus(); focus(replacing: 66)
        Bridge.setFrontProcess = { _, _, _ in Activator.focusedID = 88; return .failure }
        Queue.main.finish()
        suite.expect(results == [false] && hasFocusRecords([(66, 2)]),
                     "a failed handoff never restores old focus over a newer focused window")
        resetFocus()
    }
}
