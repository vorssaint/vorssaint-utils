// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// The production source prefetch runs beside window-server metadata. These
/// checks exercise the unchanged candidate rules, reusable capture and history
/// reconciliation while generations and window sets can change.
///
/// These checks look at what the walk produced: the windows it listed, the
/// app it named as the source, and what it did when the session was gone.
enum SwitcherQuickCommitTests {
    typealias Enumerator = SwitcherFullscreenScopeTests.Enumerator
    typealias Bridge = SwitcherFullscreenScopeTests.Bridge

    final class HistoryFixture {
        struct FrontToBack {
            let windows: [CGWindowID]
            let apps: [pid_t]
        }
        let stateLock = NSLock()
        var recording = true
        var windowHistory: [CGWindowID] = [1, 2]
        var appHistory: [pid_t] = [1]
        var focusHistory = WindowFocusHistory()
        var readAXFocus: (pid_t) -> CGWindowID? = { _ in nil }
        var windows: [CGWindowID] { windowHistory }
        var apps: [pid_t] { appHistory }
    }

    private static let frame = CGRect(x: 0, y: 0, width: 900, height: 600)

    private static func surface(id: CGWindowID, owner: pid_t) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id),
         kCGWindowOwnerPID as String: NSNumber(value: owner),
         kCGWindowLayer as String: NSNumber(value: 0),
         kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 900, "Height": 600],
         kCGWindowIsOnscreen as String: NSNumber(value: true),
         kCGWindowAlpha as String: NSNumber(value: 1),
         kCGWindowName as String: "Window \(id)"]
    }

    private static func described(_ ids: [CGWindowID]) -> Enumerator.AccessibilityWindowSnapshotList {
        var ordered: [(id: CGWindowID, snapshot: Enumerator.AccessibilityWindowSnapshot)] = []
        var byID: [CGWindowID: Enumerator.AccessibilityWindowSnapshot] = [:]
        for id in ids {
            let window = Enumerator.AccessibilityWindowSnapshot(
                title: "Window \(id)", frame: frame, isMinimized: false,
                isFullscreen: false, isNativeFullscreen: false)
            ordered.append((id, window))
            byID[id] = window
        }
        return .init(ordered: ordered, byID: byID)
    }

    static func run(_ suite: TestSuite) {
        defer {
            Enumerator.raw = []
            Enumerator.answers = [:]
            Enumerator.RunningApplication.apps = [:]
            Bridge.idListAvailable = true
            Bridge.memberships = [:]
            Bridge.windowServerTags = [:]
            Bridge.hiddenWithApp = nil
            Bridge.orderedOut = []
            SwitcherFullscreenScopeTests.Preferences.standard.values = [:]
        }
        // App 1 owns two windows, so the session's source has to be measured
        // against its focused window rather than against the first window the
        // list happens to hold. App 2 owns one, and app 12 is a process the
        // window server names that the running-apps snapshot cannot see.
        let apps = (1...2).map { id in
            Enumerator.AppSnapshot(pid: pid_t(id), bundleIdentifier: "test.app.\(id)",
                                   localizedName: "App \(id)", isRegular: true, isHidden: false,
                                   bundlePath: nil, executablePath: nil)
        }
        let snapshot = Enumerator.Snapshot(accessibilityGranted: true, runningApps: apps,
                                            ownWindowTitles: [:], screenFrames: [frame],
                                            displayIDsByUUID: [:])
        SwitcherFullscreenScopeTests.Preferences.standard.values = [
            DefaultsKey.switcherCurrentSpaceOnly: false,
            DefaultsKey.switcherShowFullscreenWindows: true,
            DefaultsKey.switcherWindowlessApps: "off"
        ]
        Bridge.memberships = [1: [1], 2: [1], 3: [1], 12: [1]]
        Enumerator.raw = [surface(id: 1, owner: 1), surface(id: 2, owner: 2),
                          surface(id: 3, owner: 1)]
        Enumerator.answers[1] = described([1, 3])
        Enumerator.answers[2] = described([2])

        // The window server can name a process that owns a window without
        // being a registered application. The running-apps snapshot cannot see
        // it, so the walk has to learn about it from the window server's own
        // list and still ask that app about its windows.
        Enumerator.RunningApplication.apps[12] = .init()
        Enumerator.raw.append(surface(id: 12, owner: 12))
        Enumerator.answers[12] = described([12])
        let withHosted = Enumerator.enumerateSwitcherWindows(groupByApp: false,
                                                             preservingGroupedWindows: false,
                                                             snapshot: snapshot)
        suite.expect(Set(withHosted.items.compactMap(\.windowID)) == [1, 2, 3, 12],
                     "an app the window server names is asked about its windows and listed")
        suite.expect(withHosted.items.contains { $0.windowID == 12 && $0.pid == 12 },
                     "the hosted window keeps the process the window server named")

        // A failed AX query does not erase a valid CG surface or its siblings.
        Enumerator.answers.removeValue(forKey: 2)
        let slowApp = Enumerator.enumerateSwitcherWindows(groupByApp: false,
                                                         preservingGroupedWindows: false,
                                                         snapshot: snapshot)
        suite.expect(Set(slowApp.items.compactMap(\.windowID)) == [1, 2, 3, 12],
                     "an unanswered app retains its CG window without erasing other apps")

        // The source of a session is the window the user is looking at. An
        // app with more than one window is measured against its focused
        // window, not against the first window the list happens to hold.
        var sourceItem: SwitcherItem?
        let sourceSnapshot = Enumerator.Snapshot(
            accessibilityGranted: false, runningApps: apps, ownWindowTitles: [:],
            screenFrames: [frame], displayIDsByUUID: [:])
        _ = Enumerator.enumerateSwitcherWindows(
            groupByApp: false,
            preservingGroupedWindows: false,
            snapshot: sourceSnapshot,
            sourcePID: 1,
            resolveSource: { items in
                let focused = SwitcherSupport.sessionSourceItem(frontmostPID: 1,
                                                                 focusedWindowID: 3,
                                                                 items: items)
                sourceItem = focused
                return focused
            })
        suite.expect(sourceItem?.windowID == 3,
                     "the focused window of a source with several windows is the session's source")

        // A session that is gone must not produce a list and must not ask
        // for a source.
        var askedForSource = false
        let cancelled = Enumerator.enumerateSwitcherWindows(
            groupByApp: false,
            preservingGroupedWindows: false,
            snapshot: snapshot,
            sourcePID: 1,
            resolveSource: { _ in
                askedForSource = true
                return nil
            },
            isCancelled: { true })
        suite.expect(cancelled.items.isEmpty && cancelled.sourceItems.isEmpty && !askedForSource,
                     "a session that was cancelled lists nothing and asks for no source")

        // The window server's own list is captured once and read by every
        // walk that shares it.
        let capture = Enumerator.WindowServerWindowList.begin()
        let first = Enumerator.enumerateSwitcherWindows(groupByApp: false,
                                                        preservingGroupedWindows: false,
                                                        snapshot: snapshot,
                                                        windowServerCapture: capture)
        let second = Enumerator.enumerateSwitcherWindows(groupByApp: false,
                                                         preservingGroupedWindows: false,
                                                         snapshot: snapshot,
                                                         windowServerCapture: capture)
        let expected: Set<CGWindowID> = [1, 2, 3, 12]
        suite.expect(Set(first.items.compactMap(\.windowID)) == expected
                        && Set(second.items.compactMap(\.windowID)) == expected,
                     "multiple consumers retain the complete captured fixture without hanging")

        Bridge.idListAvailable = false
        let legacy = Enumerator.enumerateSwitcherWindows(
            groupByApp: false, preservingGroupedWindows: false, snapshot: snapshot)
        suite.expect(Set(legacy.items.compactMap(\.windowID)) == expected,
                     "an unavailable ID-only query preserves the original full-window fallback")
        Bridge.idListAvailable = true

        let history = HistoryFixture()
        let beforeCapture = history.focusHistory.revision
        history.focusHistory.switched(to: 3, pid: 11, previous: 1)
        history.windowHistory = [3, 1, 2]
        history.appHistory = [11, 1]
        history.reconcile(existingWindows: [1, 2],
                          frontToBack: .init(windows: [2, 1], apps: [1]),
                          running: [1], revision: beforeCapture)
        suite.expect(history.windows == [3, 1, 2] && history.apps == [11, 1],
                     "a stale capture cannot forget a window or app focused after capture began")

        history.reconcile(existingWindows: [3, 4],
                          frontToBack: .init(windows: [4, 3], apps: [11]),
                          running: [11], revision: history.focusHistory.revision)
        suite.expect(history.windows == [3, 4] && history.apps == [11],
                     "a current capture still removes closed windows and terminated apps")

        let handoff = HistoryFixture()
        let source = WindowFocusHistory.Request(pid: 10)
        handoff.recordSwitch(to: 4, pid: 11, from: 2, sourceRequest: source)
        _ = handoff.focusHistory.activate(10)
        handoff.recordObservedFocus(windowID: 1, pid: 10)
        handoff.confirmSwitchSource(3, replacing: 2, for: source)
        suite.expect(handoff.windows == [1, 4, 2] && handoff.focusHistory.frontAppFocus(for: 10).observedWindows == [1, 4, 2],
                     "reactivating the source app before its inventory reply protects the newer focus in both histories")

        newEmbeddedOwner(suite)
        frontAppSources(suite, snapshot: snapshot)
    }

    private static func frontAppSources(_ suite: TestSuite, snapshot: Enumerator.Snapshot) {
        typealias Opening = SwitcherRememberedSelectionTests.SessionOpening
        typealias Reader = Opening.WindowEnumerator
        let tracker = SwitcherFullscreenScopeTests.Tracker.shared
        let items = Reader.items, reads = Reader.reads, focus = Opening.WindowActivator.focusedWindow
        let history = tracker.history
        let physicalOrder = Opening.WindowUseTracker.physicalOrder, hint = Opening.WindowUseTracker.confirmedFocus
        defer {
            Reader.items = items
            Reader.reads = reads
            Opening.WindowActivator.focusedWindow = focus
            Opening.WindowUseTracker.physicalOrder = physicalOrder
            Opening.WindowUseTracker.confirmedFocus = hint
            tracker.history = history
        }
        let host: pid_t = 1
        let minimized = SwitcherItem.window(id: 41, title: "Minimized", appName: "Editor", pid: host,
                                            isOnScreen: false, isMinimized: true, frame: frame)
        let parked = SwitcherItem.window(id: 42, title: "Other Space", appName: "Editor", pid: host,
                                         isOnScreen: false, frame: frame).withHiddenSpaceState(true)
        Reader.items = [minimized, parked]
        tracker.history = [41, 42]
        Opening.WindowUseTracker.physicalOrder = []
        Opening.WindowUseTracker.confirmedFocus = nil
        Opening.WindowActivator.focusedWindow = nil
        let parkedResult = Reader.readFrontAppSelection(snapshot: snapshot, frontmostPID: host, displayScope: nil,
                                                        knownWindowIDs: [41, 42], isCancelled: { false })
        suite.expect(parkedResult.focusedWindowID == nil && parkedResult.list.sourceItems.isEmpty
                     && parkedResult.list.items.map(\.id) == [minimized.id, parked.id] && parkedResult.focusStillCurrent(),
                     "minimized and parked windows remain destinations when the front app has no visible source")

        let source = SwitcherItem.window(id: 43, title: "Renderer", appName: "Editor", pid: host,
                                         windowOwnerPID: 21, isOnScreen: true, frame: frame)
        let destination = SwitcherItem.window(id: 44, title: "Document", appName: "Editor", pid: host,
                                              isOnScreen: true, frame: frame.offsetBy(dx: 900, dy: 0))
        Reader.items = [source, destination]
        tracker.history = [43, 44]
        Opening.WindowUseTracker.confirmedFocus = 43
        let display = Reader.DisplayScope(bounds: [frame, destination.frame], targetIndex: 1)
        let scoped = Reader.readFrontAppSelection(snapshot: snapshot, frontmostPID: host, displayScope: display,
                                                  knownWindowIDs: [44], isCancelled: { false })
        suite.expect(scoped.list.items.map(\.id) == [destination.id] && scoped.focusedWindowID == 43
                     && scoped.list.sourceItems.first(where: { $0.windowID == 43 })?.windowOwnerPID == 21,
                     "a confirmed renderer focus remains the source without AX or z-order and outside the destination display")
        Opening.WindowUseTracker.confirmedFocus = nil
        let unconfirmed = Reader.readFrontAppSelection(snapshot: snapshot, frontmostPID: host, displayScope: nil,
                                                       knownWindowIDs: [43, 44], isCancelled: { false })
        suite.expect(unconfirmed.list.items.isEmpty && !unconfirmed.focusStillCurrent(),
                     "an MRU entry alone cannot confirm the source when neither AX nor z-order answers")
        Opening.WindowUseTracker.physicalOrder = [43, 44]
        Opening.WindowUseTracker.confirmedFocus = 44
        let inventories: [Set<CGWindowID>] = [[43, 44], [44]]
        for known in inventories {
            let ambiguous = Reader.readFrontAppSelection(snapshot: snapshot, frontmostPID: host, displayScope: nil,
                                                         knownWindowIDs: known, isCancelled: { false })
            suite.expect(ambiguous.list.items.isEmpty && !ambiguous.focusStillCurrent(),
                         "an ordered-front window cannot displace confirmed focus without an AX answer")
        }
        let raised = SwitcherItem.window(id: 45, title: "Raised without focus", appName: "Editor", pid: host,
                                         isOnScreen: true, frame: frame)
        Reader.items = [source, raised, destination]
        tracker.history = [44]
        Opening.WindowUseTracker.physicalOrder = nil
        Opening.WindowUseTracker.confirmedFocus = 44
        Opening.WindowActivator.focusedWindow = 43
        let reordered = Reader.readFrontAppSelection(snapshot: snapshot, frontmostPID: host, displayScope: nil,
                                                     knownWindowIDs: [44, 45], isCancelled: { false })
        suite.expect(reordered.list.items.map(\.id) == [source.id, destination.id, raised.id],
                     "raising an already known window without focusing it preserves the observed previous window")
    }

    private static func newEmbeddedOwner(_ suite: TestSuite) {
        let host = Enumerator.AppSnapshot(pid: 20, bundleIdentifier: "test.editor", localizedName: "Editor",
                                          isRegular: true, isHidden: false, bundlePath: "/Applications/Editor.app",
                                          executablePath: nil)
        let helper: pid_t = 21
        let agent: pid_t = 22
        Enumerator.RunningApplication.apps[helper] = .init(isRegular: false,
            bundlePath: "/Applications/Editor.app/Contents/Helpers/Renderer.app")
        Enumerator.RunningApplication.apps[agent] = .init(isRegular: false, bundlePath: "/Applications/Editor.app2/Agent.app")
        let hostPID = Enumerator.appPID(forWindowOwner: helper, runningApps: [host])
        suite.expect(hostPID == host.pid && Enumerator.appPID(forWindowOwner: agent, runningApps: [host]) == nil,
                     "a new embedded owner maps to its running host while an unrelated agent has no host")
        guard let hostPID else { return }

        let snapshot = Enumerator.Snapshot(accessibilityGranted: true, runningApps: [host],
                                           ownWindowTitles: [:], screenFrames: [frame], displayIDsByUUID: [:])
        Enumerator.raw = [surface(id: 31, owner: host.pid), surface(id: 32, owner: helper), surface(id: 34, owner: agent)]
        Enumerator.answers = [host.pid: described([31]), helper: described([32, 33]), agent: described([34])]
        let warm = Enumerator.rememberSwitcherWindows(snapshot: snapshot, filterPID: hostPID, isCancelled: { false })
        suite.expect(warm.items.compactMap(\.windowID) == [31],
                     "an ordinary host refresh keeps the existing policy for owners missing from the workspace")
        let windows = Enumerator.rememberSwitcherWindows(snapshot: snapshot, filterPID: hostPID,
                                                        forFrontAppSession: true, isCancelled: { false }).items
        suite.expect(Set(windows.compactMap(\.windowID)) == [31, 32, 33]
                     && windows.allSatisfy { $0.pid == hostPID }
                     && Set(windows.filter { $0.windowOwnerPID == helper }.compactMap(\.windowID)) == [32, 33],
                     "a host refresh includes both CG and AX-only windows of a helper missing from the workspace snapshot")
    }
}
