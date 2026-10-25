// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics

/// Runs the production window walk against window-server and AX snapshots.
/// No real windows, preferences or desktop changes are needed.
enum SwitcherFullscreenScopeTests {
    enum Enumerator {
        typealias SpaceWindowBridge = SwitcherFullscreenScopeTests.Bridge
        typealias WindowUseTracker = SwitcherFullscreenScopeTests.Tracker
        typealias UserDefaults = SwitcherFullscreenScopeTests.Preferences
        typealias AXWindowResolver = SwitcherFullscreenScopeTests.Resolver
        typealias ProcessInfo = SwitcherFullscreenScopeTests.Clock
        static let minimumSize = CGSize(width: 80, height: 60)
        static let maximumCount = 48
        static var raw: [[String: Any]] = []
        static var answers: [pid_t: AccessibilityWindowSnapshotList] = [:]

        static func CGWindowListCopyWindowInfo(_ options: CGWindowListOption,
                                               _ relativeToWindow: CGWindowID) -> CFArray? {
            raw as CFArray
        }

        static func accessibilityWindows(for pids: Set<pid_t>, bundleIdentifiers: [pid_t: String],
                                         undescribedSubrolePids: Set<pid_t>, accessibilityGranted: Bool,
                                         normalLevelWindowIDs: Set<CGWindowID>, screenFrames: [CGRect],
                                         isCancelled: @escaping () -> Bool) -> [pid_t: AccessibilityWindowSnapshotList] {
            answers
        }

        static func orderByUse(_ windows: [SwitcherItem], frontToBack: [CGWindowID]) -> [SwitcherItem] {
            windows
        }

        /// Stand-in elements carry their window id as their pid.
        static func accessibilityTitle(for window: AXUIElement) -> String {
            var id: pid_t = 0
            AXUIElementGetPid(window, &id)
            Resolver.titleReads.append(CGWindowID(id))
            Clock.processInfo.systemUptime += Resolver.titleReadDuration
            return Resolver.titles[CGWindowID(id)] ?? ""
        }
    }

    final class Clock {
        static let processInfo = Clock()
        let processIdentifier = Foundation.ProcessInfo.processInfo.processIdentifier
        var systemUptime: TimeInterval = 0
    }

    /// Remote elements of windows on hidden Spaces, with each app's lookup
    /// recorded.
    enum Resolver {
        static let remoteLookupBudget: TimeInterval = 0.15
        static var titles: [CGWindowID: String] = [:]
        static var lookups: [pid_t] = []
        static var titleReads: [CGWindowID] = []
        static var titleReadDuration: TimeInterval = 0
        static var lookupDuration: TimeInterval = 0
        static func elementsOnHiddenSpace(windowIDs: Set<CGWindowID>, pid: pid_t,
                                          budget: TimeInterval, isCancelled: () -> Bool) -> [CGWindowID: AXUIElement] {
            guard budget > 0, !isCancelled() else { return [:] }
            lookups.append(pid)
            Clock.processInfo.systemUptime += lookupDuration
            return Dictionary(uniqueKeysWithValues: windowIDs.filter { titles[$0] != nil }
                .map { ($0, AXUIElementCreateApplication(pid_t($0))) })
        }
        static func prepareForRequest(_ element: AXUIElement, deadline: TimeInterval) -> Bool {
            Clock.processInfo.systemUptime < deadline
        }
    }

    final class Preferences {
        static let standard = Preferences()
        var values: [String: Any] = [:]
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func string(forKey key: String) -> String? { values[key] as? String }
        func object(forKey key: String) -> Any? { values[key] }
        func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    }

    /// The production cycle-flag reader runs against this window query. The
    /// hidden-with-app reader stays a stand-in, because its macOS 26 gate
    /// would make the result depend on the Mac running the tests.
    enum Bridge {
        struct Topology {
            let visibleSpaces: Set<UInt64>
            let fullscreenSpaces: Set<UInt64>
        }
        final class Answer {
            let windows: [(id: CGWindowID, tags: UInt64)]
            var index = -1
            init(_ windows: [(id: CGWindowID, tags: UInt64)]) { self.windows = windows }
        }
        struct WindowQuery {
            let query: (UInt32, CFArray, UInt64) -> Unmanaged<CFTypeRef>?
            let windows: (CFTypeRef) -> Unmanaged<CFTypeRef>?
            let advance: (CFTypeRef) -> Bool
            let windowID: (CFTypeRef) -> UInt32
            let tags: (CFTypeRef) -> UInt64
        }
        /// Like macOS 27.2, the query answers for every app's windows and
        /// skips windows that no longer exist.
        static let windowServer = WindowQuery(
            query: { _, ids, _ in
                let asked = (ids as? [NSNumber] ?? []).map(\.uint32Value)
                return Unmanaged.passRetained(Answer(asked.compactMap { id in
                    windowServerTags[id].map { (id, $0) }
                }) as AnyObject)
            },
            windows: { Unmanaged.passRetained($0) },
            advance: { answer in
                let answer = answer as! Answer
                answer.index += 1
                return answer.index < answer.windows.count
            },
            windowID: { answer in
                let answer = answer as! Answer
                return answer.windows[answer.index].id
            },
            tags: { answer in
                let answer = answer as! Answer
                return answer.windows[answer.index].tags
            })
        static let connection: UInt32 = 1
        static var windowQuery: WindowQuery? = windowServer
        /// The per-window read, which answers for every app before macOS 27.
        static var getWindowTags: ((UInt32, CGWindowID, UnsafeMutablePointer<UInt32>, Int) -> CGError)?
        static var windowServerTags: [CGWindowID: UInt64] = [:]
        static var memberships: [CGWindowID: [UInt64]] = [:]
        static var orderedOut: Set<CGWindowID> = []
        static var hiddenWithApp: Set<CGWindowID>?
        static let canResolveSpaces = true
        static func topology(displayIDsByUUID: [String: CGDirectDisplayID]) -> Topology? {
            Topology(visibleSpaces: [1], fullscreenSpaces: [3])
        }
        static func spaces(of id: CGWindowID) -> [UInt64] { memberships[id] ?? [] }
        static func isWindowOrderedIn(_ id: CGWindowID) -> Bool? { !orderedOut.contains(id) }
        static func windowsHiddenWithApp(among windowIDs: [CGWindowID]) -> Set<CGWindowID>? {
            hiddenWithApp.map { $0.intersection(windowIDs) }
        }
    }

    final class Tracker {
        static let shared = Tracker()
        let historyRevision: UInt64 = 0
        static func frontToBack() -> [CGWindowID] { [] }
        func reconcile(existingWindows: Set<CGWindowID>, frontToBack: [CGWindowID],
                       running: Set<pid_t>, revision: UInt64) {}
        func rank(of pid: pid_t) -> Int { Int(pid) }
    }

    static func run(_ suite: TestSuite) {
        defer {
            Enumerator.raw = []
            Enumerator.answers = [:]
            Bridge.memberships = [:]
            Bridge.windowServerTags = [:]
            Bridge.windowQuery = Bridge.windowServer
            Bridge.getWindowTags = nil
            Bridge.orderedOut = []
            Bridge.hiddenWithApp = nil
            Resolver.titles = [:]
            Resolver.lookups = []
            Resolver.titleReads = []
            Resolver.titleReadDuration = 0
            Resolver.lookupDuration = 0
            Clock.processInfo.systemUptime = 0
            Preferences.standard.values = [:]
        }
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let apps = (1...6).map { id in
            Enumerator.AppSnapshot(pid: pid_t(id), bundleIdentifier: "test.app.\(id)",
                                   localizedName: "App \(id)", isRegular: true, isHidden: false,
                                   bundlePath: nil, executablePath: nil)
        }
        let snapshot = Enumerator.Snapshot(accessibilityGranted: true, runningApps: apps,
                                            ownWindowTitles: [:], screenFrames: [frame], displayIDsByUUID: [:])
        // Current desktop, another ordinary desktop, and a native fullscreen
        // Space. The ordinary sibling deliberately fills the screen too.
        Bridge.memberships = [1: [1], 2: [2], 3: [3], 4: [3], 5: [2], 6: [2]]
        Enumerator.raw = (1...3).map { id -> [String: Any] in
            let bounds = ["X": 0, "Y": 0, "Width": id == 1 ? 600 : 900, "Height": id == 1 ? 400 : 600]
            return [kCGWindowNumber as String: NSNumber(value: id),
             kCGWindowOwnerPID as String: NSNumber(value: id),
             kCGWindowLayer as String: NSNumber(value: 0),
             kCGWindowBounds as String: bounds,
             kCGWindowIsOnscreen as String: NSNumber(value: id == 1),
             kCGWindowAlpha as String: NSNumber(value: 1),
             kCGWindowName as String: "Window \(id)"]
        }
        // AX-only fullscreen and ordinary siblings exercise the second pass.
        // App 6 has an AX fullscreen flag while topology still says desktop.
        for id: CGWindowID in [1, 2, 4, 5, 6] {
            let window = Enumerator.AccessibilityWindowSnapshot(
                title: "Window \(id)", frame: id == 1 ? CGRect(x: 0, y: 0, width: 600, height: 400) : frame,
                isMinimized: id == 5, isFullscreen: id != 1, isNativeFullscreen: id == 4 || id == 6)
            Enumerator.answers[pid_t(id)] = .init(ordered: [(id, window)], byID: [id: window])
        }
        // The browser's hidden fullscreen window can be missing from AX.
        Enumerator.answers[3] = .init(ordered: [], byID: [:])

        func enumerate(currentSpaceOnly: Bool, showFullscreen: Bool = true, groupByApp: Bool = false,
                       appRules: [String: SwitcherAppRule] = [:],
                       windowlessApps: String = "off") -> Enumerator.WindowList {
            Preferences.standard.values = [DefaultsKey.switcherCurrentSpaceOnly: currentSpaceOnly,
                                            DefaultsKey.switcherShowFullscreenWindows: showFullscreen,
                                            DefaultsKey.switcherWindowlessApps: windowlessApps,
                                            DefaultsKey.switcherAppRules: SwitcherAppRule.storedValue(appRules)]
            return Enumerator.enumerateSwitcherWindows(groupByApp: groupByApp,
                                                        preservingGroupedWindows: false, snapshot: snapshot)
        }
        let scoped = enumerate(currentSpaceOnly: true)
        suite.expect(Set(scoped.items.compactMap(\.windowID)) == [1, 3, 4, 6],
                     "current-desktop mode retains native fullscreen windows from both enumeration passes")
        let fullscreenTargets = scoped.items.filter { [3, 4, 6].contains($0.windowID) }
        suite.expect(fullscreenTargets.count == 3 && fullscreenTargets.allSatisfy(\.isOnHiddenSpace)
                        && scoped.items.contains { $0.windowID == 3 && $0.isFullscreen },
                     "fullscreen targets keep their desktop-travel metadata even when AX omits them")
        suite.expect(!scoped.items.contains { $0.windowID == 2 || $0.windowID == 5 },
                     "a screen-sized ordinary window on another desktop does not bypass desktop scope")
        suite.expect(enumerate(currentSpaceOnly: true, showFullscreen: false).items.compactMap(\.windowID) == [1],
                     "hiding fullscreen windows retains the current-desktop ordinary window")
        let hiddenApps = enumerate(currentSpaceOnly: true, appRules: ["test.app.3": .hidden, "test.app.4": .hidden])
        suite.expect(Set(hiddenApps.items.compactMap(\.windowID)) == [1, 6],
                     "fullscreen scope does not override app exclusions in either enumeration pass")
        suite.expect(Set(enumerate(currentSpaceOnly: false).items.compactMap(\.windowID)) == [1, 2, 3, 4, 5, 6],
                     "all-desktop enumeration retains ordinary and fullscreen windows")
        suite.expect(Set(enumerate(currentSpaceOnly: true, groupByApp: true).items.compactMap(\.windowID)) == [1, 3, 4, 6],
                     "one entry per app keeps a fullscreen window for an app with no window on this desktop")
        let dock = Enumerator.listWindows(filterPID: 3, maximumCount: 12, windowlessApps: .off,
                                          appRules: [:], groupByApp: false, minimizedPlacement: .normal,
                                          treatHiddenAppsLikeMinimized: false, showFullscreenWindows: true,
                                          preservingGroupedWindows: false, currentSpaceOnly: true,
                                          marksHiddenSpaces: false, snapshot: snapshot)
        suite.expect(dock.items.isEmpty,
                     "Dock Preview keeps its independent strict current-desktop scope")
        Preferences.standard.values[DefaultsKey.switcherCurrentSpaceOnly] = true
        suite.expect(Enumerator.listWindowsForCommandBar(snapshot: snapshot).compactMap(\.windowID) == [1],
                     "Command Bar keeps its existing current-desktop scope")
        // Without Screen Recording the window server titles no window, and
        // Accessibility leaves the browser's window on another desktop out of
        // its list, so the window showed only its app's name. Its remote
        // element supplies the title, looked up once for the app; a window
        // the app's list describes keeps that title without a lookup.
        let screenRecordingTitles = Enumerator.raw
        Enumerator.raw = Enumerator.raw.map { $0.filter { $0.key != kCGWindowName as String } }
        Resolver.titles = [3: "Pull requests"]
        let untitled = enumerate(currentSpaceOnly: false).items
        suite.expect(untitled.first { $0.windowID == 3 }?.title == "Pull requests" && Resolver.lookups == [3],
                     "a window on another desktop takes its title from its remote element, found \(Resolver.lookups)")
        suite.expect(untitled.first { $0.windowID == 2 }?.title == "Window 2",
                     "a window on another desktop that Accessibility describes keeps that title")
        let untitledRaw = Enumerator.raw
        var sibling = Enumerator.raw.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == 3 }!
        sibling[kCGWindowNumber as String] = NSNumber(value: 7)
        Enumerator.raw.append(sibling)
        Bridge.memberships[7] = [3]
        Resolver.titles[7] = "Second tab"
        Resolver.lookups = []
        suite.expect(enumerate(currentSpaceOnly: false).items.first { $0.windowID == 7 }?.title == "Second tab"
                     && Resolver.lookups == [3], "hidden siblings share one remote lookup per app")
        var otherAppWindow = sibling
        otherAppWindow[kCGWindowNumber as String] = NSNumber(value: 8)
        otherAppWindow[kCGWindowOwnerPID as String] = NSNumber(value: 2)
        Enumerator.raw.append(otherAppWindow)
        Bridge.memberships[8] = [3]
        Resolver.titles[8] = "Another app"
        Resolver.lookups = []
        Resolver.titleReads = []
        Resolver.lookupDuration = Resolver.remoteLookupBudget
        _ = enumerate(currentSpaceOnly: false)
        suite.expect(Resolver.titleReads.isEmpty && Resolver.lookups == [3],
                     "an exhausted remote budget skips title reads and the next app's lookup")
        Resolver.lookupDuration = 0
        Resolver.titleReadDuration = Resolver.remoteLookupBudget
        Resolver.titleReads = []
        Resolver.lookups = []
        _ = enumerate(currentSpaceOnly: false)
        suite.expect(Resolver.titleReads.count == 1 && Resolver.lookups == [3],
                     "a slow title read consumes the shared budget before the next title or app")
        Resolver.titleReadDuration = 0
        Enumerator.raw = untitledRaw
        Bridge.memberships.removeValue(forKey: 7)
        Bridge.memberships.removeValue(forKey: 8)
        Resolver.titles = [:]
        Resolver.lookups = []
        suite.expect(enumerate(currentSpaceOnly: false).items.first { $0.windowID == 3 }?.title == "",
                     "a window whose element cannot be found stays untitled, so it shows its app's name as before")
        Enumerator.raw = screenRecordingTitles
        Resolver.lookups = []
        _ = enumerate(currentSpaceOnly: false)
        suite.expect(Resolver.lookups.isEmpty, "with Screen Recording titles nothing is looked up")

        Bridge.windowServerTags = [3: 1 << 18]
        suite.expect(!enumerate(currentSpaceOnly: true).items.contains { $0.windowID == 3 },
                     "an unmatched cycle-excluded fullscreen helper stays out")

        // App 1 also plays a fullscreen video on another desktop. With one
        // entry per app, its window here must stay the entry to pick.
        Bridge.windowServerTags = [:]
        Bridge.memberships = [7: [1], 8: [3]]
        func browser(_ order: [CGWindowID], minimized: Bool = false) {
            Enumerator.raw = order.map { id -> [String: Any] in
                let bounds = ["X": 0, "Y": 0, "Width": id == 7 ? 600 : 900, "Height": id == 7 ? 400 : 600]
                return [kCGWindowNumber as String: NSNumber(value: id),
                 kCGWindowOwnerPID as String: NSNumber(value: 1),
                 kCGWindowLayer as String: NSNumber(value: 0),
                 kCGWindowBounds as String: bounds,
                 kCGWindowIsOnscreen as String: NSNumber(value: id == 7 && !minimized),
                 kCGWindowAlpha as String: NSNumber(value: 1),
                 kCGWindowName as String: "Window \(id)"]
            }
            let local = Enumerator.AccessibilityWindowSnapshot(
                title: "Window 7", frame: CGRect(x: 0, y: 0, width: 600, height: 400),
                isMinimized: minimized, isFullscreen: false, isNativeFullscreen: false)
            let video = Enumerator.AccessibilityWindowSnapshot(
                title: "Window 8", frame: frame, isMinimized: false, isFullscreen: true, isNativeFullscreen: true)
            Enumerator.answers = [1: .init(ordered: [(id: CGWindowID(7), snapshot: local),
                                                    (id: CGWindowID(8), snapshot: video)],
                                           byID: [7: local, 8: video])]
        }
        func representative(currentSpaceOnly: Bool) -> [CGWindowID] {
            enumerate(currentSpaceOnly: currentSpaceOnly, groupByApp: true).items.compactMap(\.windowID)
        }
        browser([7, 8])
        suite.expect(representative(currentSpaceOnly: true) == [7],
                     "one entry per app keeps the window here over a later fullscreen window on another desktop")
        suite.expect(representative(currentSpaceOnly: false) == [8],
                     "all-desktop grouping still prefers the app's fullscreen window")
        browser([8, 7], minimized: true)
        suite.expect(representative(currentSpaceOnly: true) == [7],
                     "a minimized window here replaces a fullscreen window from another desktop as the app's entry")
        suite.expect(enumerate(currentSpaceOnly: true).items.compactMap(\.windowID) == [8, 7],
                     "without grouping both windows of the app stay listed")

        // MARK: Windows a hidden app had closed (issues #512 and #2628)

        // A hidden app's windows here (30) and on another desktop (33), beside
        // a window it closed before hiding (31), an untitled helper it keeps
        // off screen (32) and a window it closed on the other desktop (34).
        // Each keeps its desktop and is ordered out. Accessibility lists only
        // the window here; the window server tags the two it hid.
        let hiddenApp = Enumerator.AppSnapshot(pid: 9, bundleIdentifier: "test.app.9",
                                               localizedName: "App 9", isRegular: true, isHidden: true,
                                               bundlePath: nil, executablePath: nil)
        let hiddenSnapshot = Enumerator.Snapshot(accessibilityGranted: true, runningApps: [hiddenApp],
                                                 ownWindowTitles: [:], screenFrames: [frame], displayIDsByUUID: [:])
        let windowFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
        Bridge.memberships = [30: [1], 31: [1], 32: [1], 33: [2], 34: [2]]
        Bridge.orderedOut = [30, 31, 32, 33, 34]
        Enumerator.raw = (30...34).map { id -> [String: Any] in
            var info: [String: Any] = [kCGWindowNumber as String: NSNumber(value: id),
                                       kCGWindowOwnerPID as String: NSNumber(value: 9),
                                       kCGWindowLayer as String: NSNumber(value: 0),
                                       kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 600, "Height": 400],
                                       kCGWindowIsOnscreen as String: NSNumber(value: false),
                                       kCGWindowAlpha as String: NSNumber(value: 1)]
            if id != 32 { info[kCGWindowName as String] = "Window \(id)" }
            return info
        }
        let hiddenHere = Enumerator.AccessibilityWindowSnapshot(
            title: "Window 30", frame: windowFrame, isMinimized: false, isFullscreen: false, isNativeFullscreen: false)
        Enumerator.answers = [9: .init(ordered: [(id: CGWindowID(30), snapshot: hiddenHere)], byID: [30: hiddenHere])]
        func hiddenAppItems() -> [SwitcherItem] {
            Preferences.standard.values = [DefaultsKey.switcherWindowlessApps: "off"]
            return Enumerator.enumerateSwitcherWindows(groupByApp: false, preservingGroupedWindows: false,
                                                       snapshot: hiddenSnapshot).items
        }
        Bridge.hiddenWithApp = [30, 33]
        let hiddenItems = hiddenAppItems()
        suite.expect(Set(hiddenItems.compactMap(\.windowID)) == [30, 33] && hiddenItems.allSatisfy(\.isAppHidden),
                     "a hidden app lists the windows it hid, here and on another desktop, but none it had closed")
        Bridge.hiddenWithApp = nil
        suite.expect(Set(hiddenAppItems().compactMap(\.windowID)) == [30, 31, 32, 33, 34],
                     "without the window server's answer a hidden app keeps every surface on a desktop, as before")

        // MARK: Another app's surface kept out of window cycling

        // A browser window here (40) and its untitled auxiliary surface (41),
        // parked on another desktop and still ordered in. Accessibility does
        // not describe the surface, and the window server tags it like
        // Safari's 517×132 surface on macOS 27.2.
        func windowTags(_ bits: [UInt64]) -> UInt64 { bits.reduce(0) { $0 | 1 << $1 } }
        let browserWindow = Enumerator.AccessibilityWindowSnapshot(
            title: "Window 40", frame: windowFrame, isMinimized: false, isFullscreen: false, isNativeFullscreen: false)
        func surfaceBeside(_ windowIDs: [CGWindowID], described: [CGWindowID], unanswered: Set<CGWindowID> = []) {
            Enumerator.raw = windowIDs.map { id -> [String: Any] in
                var info: [String: Any] = [kCGWindowNumber as String: NSNumber(value: id),
                                           kCGWindowOwnerPID as String: NSNumber(value: 1),
                                           kCGWindowLayer as String: NSNumber(value: 0),
                                           kCGWindowBounds as String: id == 40
                                               ? ["X": 0, "Y": 0, "Width": 600, "Height": 400]
                                               : ["X": 0, "Y": 0, "Width": 517, "Height": 132],
                                           kCGWindowIsOnscreen as String: NSNumber(value: id == 40),
                                           kCGWindowAlpha as String: NSNumber(value: 1)]
                if id == 40 { info[kCGWindowName as String] = "Window 40" }
                return info
            }
            let windows = described.map { (id: $0, snapshot: browserWindow) }
            Enumerator.answers = [1: .init(ordered: windows,
                                           byID: Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.snapshot) }),
                                           unansweredIDs: unanswered)]
        }
        func listed(windowlessApps: String = "off") -> [SwitcherItem] {
            enumerate(currentSpaceOnly: false, windowlessApps: windowlessApps).items
        }
        Bridge.memberships = [40: [1], 41: [2]]
        Bridge.windowServerTags = [40: windowTags([0, 9, 13, 19, 22, 32, 45]), 41: windowTags([0, 18, 19, 30, 32])]
        surfaceBeside([40, 41], described: [40])
        suite.expect(listed().compactMap(\.windowID) == [40],
                     "another app's surface kept out of window cycling stays out of the switcher")
        surfaceBeside([40, 41], described: [40], unanswered: [41])
        suite.expect(listed().compactMap(\.windowID) == [40],
                     "the surface stays out when its Accessibility read times out")
        surfaceBeside([41], described: [], unanswered: [41])
        let busy = listed(windowlessApps: "all")
        suite.expect(busy.count == 1 && busy[0].windowID == nil && busy[0].pid == 1,
                     "a busy app whose only timed-out window is that surface keeps its app entry")
        surfaceBeside([40, 41], described: [40])
        Bridge.windowServerTags[41] = windowTags([0, 19, 30, 32])
        suite.expect(listed().compactMap(\.windowID) == [40, 41],
                     "the same surface without the flag is listed as a window on another desktop")
        Bridge.windowServerTags[41] = windowTags([0, 18, 19, 30, 32])
        Bridge.windowQuery = nil
        suite.expect(listed().compactMap(\.windowID) == [40, 41],
                     "without the window query the surface is not hidden on a guess")
        // Where the batched query gives no answer, as it may before
        // macOS 27, the per-window read still keeps the surface out.
        Bridge.getWindowTags = { _, id, tags, _ in
            let value = Bridge.windowServerTags[id] ?? 0
            tags[0] = UInt32(truncatingIfNeeded: value)
            tags[1] = UInt32(truncatingIfNeeded: value >> 32)
            return .success
        }
        suite.expect(listed().compactMap(\.windowID) == [40],
                     "without the window query the per-window read keeps the surface out of the switcher")
        Bridge.windowQuery = Bridge.WindowQuery(
            query: { _, _, _ in Unmanaged.passRetained(Bridge.Answer([]) as AnyObject) },
            windows: Bridge.windowServer.windows, advance: Bridge.windowServer.advance,
            windowID: Bridge.windowServer.windowID, tags: Bridge.windowServer.tags)
        suite.expect(listed().compactMap(\.windowID) == [40],
                     "a window query that leaves the surface out of its answer falls back to the per-window read")
        Bridge.getWindowTags = { _, _, _, _ in .success }
        suite.expect(listed().compactMap(\.windowID) == [40, 41],
                     "a per-window read of zeros, as macOS 27 gives for other apps, hides nothing")
    }
}
