// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

enum SwitcherRememberedSelectionTests {
    typealias Enumerator = SwitcherFullscreenScopeTests.Enumerator
    typealias Preferences = SwitcherFullscreenScopeTests.Preferences
    typealias Tracker = SwitcherFullscreenScopeTests.Tracker

    enum Selection {
        typealias WindowEnumerator = Enumerator
        typealias UserDefaults = Preferences
        typealias WindowUseTracker = Tracker
    }

    enum WindowEvents {}

    final class OwnWindow: NSObject {
        static let didChangeScreenNotification = NSWindow.didChangeScreenNotification
        var windowNumber = 42
        var styleMask: NSWindow.StyleMask = .titled
        var level: NSWindow.Level = .normal
        var canBecomeKey = true
        var isVisible = true
        var isMiniaturized = false
    }

    final class Inventory {
        typealias NSWindow = OwnWindow
        enum WindowEnumerator { typealias NSWindow = OwnWindow }
        var onInvalidate: (pid_t?) -> Void = { _ in }
        func invalidate(pid: pid_t? = nil) { onInvalidate(pid) }
    }

    /// Run the inventory with a private desktop and manually deliver each worker reply.
    enum SessionOpening {
        typealias DeferredQueue = SwitcherActivationTests.DeferredQueue
        typealias SwitcherWindowSelection = Selection
        typealias SwitcherWindowEvents = Events
        typealias NSRunningApplication = Enumerator.RunningApplication
        typealias NSWindow = OwnWindow
        typealias Permissions = SwitcherHoverSelectionTests.Permissions

        final class Desktop {
            let notificationCenter = NotificationCenter()
            let windows: [NSWindow] = []
            var frontmostApplication: NSRunningApplication?
        }
        static let desktop = Desktop()

        struct DispatchQueue {
            struct Main {
                let deliveries = DeferredQueue()
                let debounce = DeferredQueue()
                func async(execute work: @escaping () -> Void) { deliveries.async(execute: work) }
                func asyncAfter(deadline: DispatchTime, execute work: DispatchWorkItem) {
                    debounce.async { work.perform() }
                }
            }
            static let main = Main()
            static let discoveries = DeferredQueue()
            static let scans = DeferredQueue()
            let worker: DeferredQueue
            init(label: String, qos: DispatchQoS) { worker = qos == .utility ? Self.discoveries : Self.scans }
            func async(execute work: @escaping () -> Void) { worker.async(execute: work) }
        }
        final class Events {
            static let shared = Events()
            var deliver: ((Event) -> Void)?
            func start(handler: @escaping (Event) -> Void) -> Bool {
                deliver = handler
                return true
            }
            func watch(_ ids: Set<CGWindowID>) -> Bool { true }
            func stop() { deliver = nil }
            static func matchesWindowNumber(_ number: Int, windowID: CGWindowID) -> Bool {
                WindowEvents.matchesWindowNumber(number, windowID: windowID)
            }
        }
        enum SpaceWindowBridge {
            static var visibleSpaces: Set<UInt64> = [1]
            static func topology() -> SwitcherFullscreenScopeTests.Bridge.Topology? {
                .init(visibleSpaces: visibleSpaces, fullscreenSpaces: [])
            }
        }
        final class SwitcherWindowTitles {
            var onChange: ((pid_t) -> Void)?
            func update(_ elements: [CGWindowID: AXUIElement]) {}
            func refreshUnobserved(in items: [SwitcherItem], accessibilityGranted: Bool) {}
            func stop() {}
        }
        struct WindowUseTracker {
            static let shared = WindowUseTracker()
            static var seedPID: pid_t?
            private static var trackedPID: pid_t { seedPID ?? WindowEnumerator.items.first?.pid ?? 10 }
            static let history = SwitcherQuickCommitTests.HistoryFixture()
            static var confirmedFocus: CGWindowID? {
                get { shared.frontAppFocus(for: trackedPID).windowID }
                set {
                    guard let newValue else { history.focusHistory = WindowFocusHistory(); return }
                    if history.focusHistory.current?.pid != trackedPID { _ = history.focusHistory.activate(trackedPID) }
                    if let request = history.focusHistory.current {
                        history.focusHistory.focus(newValue, for: request)
                    }
                }
            }
            static var physicalOrder: [CGWindowID]?
            var windows: [CGWindowID] { Tracker.shared.history }
            func frontAppFocus(for pid: pid_t, appPID: pid_t? = nil) -> WindowFocusHistory.FrontAppFocus {
                Self.history.focusHistory.frontAppFocus(for: pid, appPID: appPID, now: SwitcherHoverSelectionTests.Queue.time)
            }
            func recordSwitch(to windowID: CGWindowID?, pid: pid_t, from previous: CGWindowID?, focusPID: pid_t? = nil,
                              sourceRequest: WindowFocusHistory.Request? = nil) {
                Self.history.windowHistory = windows
                Self.history.recordSwitch(to: windowID, pid: pid, from: previous, focusPID: focusPID, sourceRequest: sourceRequest)
                Tracker.shared.history = Self.history.windowHistory
            }
            func confirmSwitchSource(_ window: CGWindowID, replacing previous: CGWindowID, for request: WindowFocusHistory.Request) {
                Self.history.windowHistory = windows
                Self.history.confirmSwitchSource(window, replacing: previous, for: request)
                Tracker.shared.history = Self.history.windowHistory
            }
            func recordObservedFocus(windowID: CGWindowID, pid: pid_t) {
                Self.history.windowHistory = windows
                Self.history.recordObservedFocus(windowID: windowID, pid: pid)
                Tracker.shared.history = Self.history.windowHistory
            }
            func recordDestroyedWindow(_ windowID: CGWindowID) {
                Self.history.windowHistory = windows
                Self.history.recordDestroyedWindow(windowID)
                Tracker.shared.history = Self.history.windowHistory
            }
        }
        enum WindowActivator {
            static var focusedWindow: CGWindowID?
            static var responderPID: pid_t?
            static var focusReads: [pid_t] = []
            static func focusedWindowID(for pid: pid_t) -> CGWindowID? {
                focusReads.append(pid)
                return pid == (responderPID ?? WindowEnumerator.items.first?.pid) ? focusedWindow : nil
            }
        }
        enum WindowEnumerator {
            typealias WindowUseTracker = SessionOpening.WindowUseTracker
            typealias WindowActivator = SessionOpening.WindowActivator
            typealias SpaceWindowBridge = SwitcherFullscreenScopeTests.Bridge
            typealias UserDefaults = Preferences
            typealias SwitcherWindowSelection = Selection
            typealias WindowList = Enumerator.WindowList
            typealias AppSnapshot = Enumerator.AppSnapshot
            typealias Snapshot = Enumerator.Snapshot
            typealias DisplayScope = Enumerator.DisplayScope
            static var items: [SwitcherItem] = []
            static var firstFrontAppItems: [SwitcherItem]?
            static var focusByRead: [CGWindowID?] = []
            static var stackRows: [[String: Any]]?
            static var capturedRows: [[String: Any]]?
            static var inventoryCaptureSequence: [() -> [[String: Any]]] = []
            static var rejectedIDs: Set<CGWindowID> = []
            static var apps: [AppSnapshot] = []
            static var reads: [pid_t?] = []
            static func stackRow(_ item: SwitcherItem, owner: pid_t? = nil, layer: Int = 0) -> [String: Any] {
                let frame = item.frame.isEmpty ? CGRect(x: 0, y: 0, width: 400, height: 300) : item.frame
                return [kCGWindowNumber as String: NSNumber(value: item.windowID ?? 0),
                        kCGWindowOwnerPID as String: NSNumber(value: owner ?? item.windowOwnerPID),
                        kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1,
                        kCGWindowBounds as String: frame.dictionaryRepresentation]
            }
            static func CGWindowListCopyWindowInfo(_ options: CGWindowListOption, _ id: CGWindowID) -> CFArray? {
                let order = WindowUseTracker.physicalOrder ?? items.compactMap(\.windowID)
                let rows = order.compactMap { id in items.first { $0.windowID == id } }.map { stackRow($0) }
                return (stackRows ?? rows) as CFArray
            }
            static func frameIsSwitchable(_ frame: CGRect) -> Bool { Enumerator.frameIsSwitchable(frame) }
            static func ownWindowID(for window: NSWindow) -> CGWindowID? {
                Inventory.WindowEnumerator.ownWindowID(for: window)
            }
            static func runningApplications() -> [AppSnapshot] { apps }
            static func appPID(forWindowOwner owner: pid_t, runningApps: @autoclosure () -> [AppSnapshot]) -> pid_t? {
                Enumerator.appPID(forWindowOwner: owner, runningApps: runningApps())
            }
            static func snapshot(includingRunningApps: Bool = true) -> Snapshot {
                .init(accessibilityGranted: Permissions.shared.accessibility, runningApps: [], ownWindowTitles: [:], screenFrames: [], displayIDsByUUID: [:])
            }
            static func rememberSwitcherWindows(snapshot: Snapshot, filterPID: pid_t? = nil, forFrontAppSession: Bool = false,
                                                isCancelled: () -> Bool) -> WindowList {
                reads.append(filterPID)
                let captured = forFrontAppSession ? (firstFrontAppItems ?? items) : items
                var result = WindowList(items: captured.filter { filterPID == nil || $0.pid == filterPID }, sourceItems: [])
                if forFrontAppSession {
                    firstFrontAppItems = nil
                    if !focusByRead.isEmpty { WindowActivator.focusedWindow = focusByRead.removeFirst() }
                    result.capturedVisibleSpaces = SessionOpening.SpaceWindowBridge.topology()?.visibleSpaces
                    result.rejectedWindowIDs = rejectedIDs
                }
                if snapshot.accessibilityGranted, let owner = WindowActivator.responderPID ?? captured.first?.windowOwnerPID,
                   let focus = WindowActivator.focusedWindow,
                   result.items.contains(where: { $0.windowOwnerPID == owner && $0.windowID == focus }) {
                    result.focusedWindowIDsByOwner[owner] = focus
                }
                let suppliedRows = !forFrontAppSession && filterPID != nil && !inventoryCaptureSequence.isEmpty
                    ? inventoryCaptureSequence.removeFirst()() : capturedRows
                if forFrontAppSession || suppliedRows != nil {
                    let rows = suppliedRows ?? captured.filter { $0.windowID != nil }.map { stackRow($0) }
                    result.activationSnapshot = .init(windowInfo: rows, capturesActivationBaseline: true)
                }
                return result
            }
        }
        static func windowInfo(_ options: CGWindowListOption, _ id: CGWindowID) -> CFArray? {
            guard let owner = WindowEnumerator.items.first(where: { $0.windowID == id })?.pid else { return nil }
            return [[kCGWindowOwnerPID as String: NSNumber(value: owner), kCGWindowLayer as String: 0]] as CFArray
        }
    }

    private static func window(
        _ id: CGWindowID,
        pid: pid_t? = nil,
        hiddenSpace: Bool = false,
        fullscreen: Bool = false,
        minimized: Bool = false,
        hiddenApp: Bool = false,
        x: CGFloat = 0
    ) -> SwitcherItem {
        SwitcherItem.window(
            id: id,
            title: "Window \(id)",
            appName: "App \(pid ?? pid_t(id))",
            pid: pid ?? pid_t(id),
            isOnScreen: !hiddenSpace && !minimized && !hiddenApp,
            isAppHidden: hiddenApp,
            isMinimized: minimized,
            isFullscreen: fullscreen,
            frame: CGRect(x: x, y: 0, width: 800, height: 600)).withHiddenSpaceState(hiddenSpace)
    }

    static func run(_ suite: TestSuite) {
        ownWindowScreenChanges(suite)
        openingDuringDiscovery(suite)
        frontmostHelperRules(suite)
        let lifetime = SwitcherNotificationLifetime()
        lifetime.start()
        let queued = lifetime.current
        lifetime.stop()
        suite.expect(queued != nil && lifetime.current == nil, "a stopped switcher has no event lifetime to enqueue")
        lifetime.start()
        suite.expect(lifetime.current != queued, "work queued before disabling cannot deliver into a new session")
        var watch = SwitcherWindowWatch()
        var requests = 0
        let failed = watch.update(to: [4]) { _ in requests += 1; return false }
        let retried = watch.update(to: [4]) { _ in requests += 1; return true }
        let unchanged = watch.update(to: [4]) { _ in requests += 1; return false }
        suite.expect(!failed && retried && unchanged && requests == 2,
                     "a rejected notification subscription retries and an accepted subscription is reused")
        var spaces = SwitcherInventorySpaces()
        _ = spaces.changed(to: [1], notified: false)
        let inFlightRevision = spaces.revision
        suite.expect(spaces.changed(to: [2], notified: false) && spaces.revision != inFlightRevision,
                     "a shortcut detects a Space change before the notification and invalidates an in-flight scan")
        let newRevision = spaces.revision
        suite.expect(!spaces.changed(to: [2], notified: true) && spaces.revision == newRevision,
                     "a duplicate Space notification keeps the new Space's pending scan")
        suite.expect(spaces.changed(to: nil, notified: true) && spaces.changed(to: nil, notified: true)
                     && !spaces.changed(to: nil, notified: false),
                     "a system without Space IDs refreshes on notifications and can still open the switcher")
        let finder = SwitcherItem.appOnly(appName: "Finder", pid: 7)
        suite.expect(Selection.contains(finder, in: [window(42, pid: 7)]) &&
                     !Selection.contains(finder, in: [window(42, pid: 8)]) &&
                     !Selection.contains(window(41, pid: 7), in: [window(42, pid: 7)]),
                     "a windowless Finder selection follows its first window, while closed windows and apps stay gone")
        for number in [Int.min, -1, 0, Int.max, Int(UInt32.max) + 1] {
            suite.expect(!WindowEvents.matchesWindowNumber(number, windowID: 1),
                         "an unavailable AppKit window number \(number) safely remains unmatched")
        }
        suite.expect(WindowEvents.matchesWindowNumber(42, windowID: 42),
                     "an allocated AppKit window matches its WindowServer ID")
        suite.expect(!WindowEvents.matchesWindowNumber(42, windowID: 43),
                     "another allocated window remains distinct")
        defer {
            Preferences.standard.values = [:]
            Tracker.shared.history = []
        }
        Preferences.standard.values = [
            DefaultsKey.switcherWindowlessApps: "finder",
            DefaultsKey.switcherCurrentSpaceOnly: true,
            DefaultsKey.switcherShowFullscreenWindows: true,
            DefaultsKey.switcherMinimizedPlacement: "hidden",
            DefaultsKey.switcherTreatHiddenAppsLikeMinimized: true
        ]
        var remembered = Enumerator.WindowList(
            items: [window(1), window(2), window(3, hiddenSpace: true, fullscreen: true),
                    window(4, hiddenSpace: true, fullscreen: true), window(5, minimized: true),
                    window(6, hiddenApp: true), .appOnly(appName: "Finder", pid: 7),
                    .appOnly(appName: "Other", pid: 8)],
            sourceItems: [])
        remembered.nativeFullscreenWindowIDs = [3]
        remembered.bundleIdentifiers = [7: Defaults.finderBundleIdentifier, 8: "test.other"]
        func select(
            scope: SwitcherSessionScope = .allApps,
            frontmostPID: pid_t = 1,
            focused: CGWindowID? = 1,
            display: Enumerator.DisplayScope? = nil
        ) -> Enumerator.WindowList {
            Selection.select(
                remembered: remembered,
                scope: scope,
                frontmostPID: frontmostPID,
                focusedWindowID: focused,
                displayScope: display)
        }
        let original = select()
        suite.expect(original.items.map(\.id) == ["w:1", "w:2", "w:3", "a:7"],
                     "remembered windows retain desktop, native fullscreen, minimized, hidden-app and Finder rules")
        Preferences.standard.values[DefaultsKey.switcherAppRules] = ["test.other": "showWithoutWindows"]
        suite.expect(select().items.contains { $0.pid == 8 }, "a windowless per-app override applies at shortcut press")
        Preferences.standard.values[DefaultsKey.switcherAppRules] = [Defaults.finderBundleIdentifier: "hidden"]
        suite.expect(!select().items.contains { $0.pid == 7 }, "a newly hidden app is filtered from remembered results")
        Preferences.standard.values = [DefaultsKey.switcherWindowlessApps: "all"]
        remembered = Enumerator.WindowList(items: [window(1), window(2), window(3)], sourceItems: [])
        Tracker.shared.history = [3, 1, 2]
        suite.expect(select().items.compactMap(\.windowID) == [1, 3, 2],
                     "live recent-use history sorts the remembered list before selecting the next window")
        Tracker.shared.history = [2, 1, 3]
        suite.expect(select().items.compactMap(\.windowID) == [1, 2, 3],
                     "a later shortcut sees focus changes made since discovery")
        suite.expect(original.items.map(\.id) == ["w:1", "w:2", "w:3", "a:7"],
                     "background changes preserve the entries of a captured session")
        remembered = Enumerator.WindowList(items: [window(1), window(2, x: 1000)], sourceItems: [])
        let displays = Enumerator.DisplayScope(
            bounds: [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)],
            targetIndex: 1)
        let onDisplay = select(display: displays)
        suite.expect(onDisplay.items.map(\.id) == ["w:2"] && onDisplay.sourceItems.contains { $0.windowID == 1 },
                     "display filtering retains the foreground source for activation")
        remembered = Enumerator.WindowList(items: [window(1), window(2, pid: 1), window(3)], sourceItems: [])
        Preferences.standard.values[DefaultsKey.switcherMergeTabs] = true
        suite.expect(select().items.count == 2, "merged sessions show one representative per app")
        suite.expect(select(scope: .frontmostApp).items.compactMap(\.windowID) == [1, 2],
                     "the front-app shortcut retains its individual windows")
        Preferences.standard.values[DefaultsKey.switcherSimpleMode] = true
        suite.expect(Set(select().items.compactMap(\.windowID)) == [1, 2, 3],
                     "simple grouped mode retains backing windows for navigation")
        Preferences.standard.values = [:]
        remembered = Enumerator.WindowList(items: (1...80).map { window(CGWindowID($0), pid: 1) } + [window(300)], sourceItems: [])
        let capped = select()
        suite.expect(capped.items.count == 48 && capped.items.contains { $0.pid == 300 },
                     "the visible cap reserves an entry for another app on a crowded desktop")
    }

    private static func openingDuringDiscovery(_ suite: TestSuite) {
        typealias Opening = SessionOpening
        typealias Windows = Opening.WindowEnumerator
        typealias Queues = Opening.DispatchQueue
        let inventory = Opening.SwitcherWindowInventory()
        let other = window(1, pid: 9), new = window(2, pid: 10)
        let previousApps = Enumerator.RunningApplication.apps
        let previousPreferences = Preferences.standard.values
        defer {
            inventory.onReady = nil
            inventory.stop()
            Windows.items = []
            Windows.reads = []
            Queues.discoveries.reset()
            Queues.scans.reset()
            Queues.main.debounce.reset()
            Queues.main.deliveries.reset()
            Enumerator.RunningApplication.apps = previousApps
            Preferences.standard.values = previousPreferences
        }
        Preferences.standard.values = [DefaultsKey.switcherWindowlessApps: "off",
                                       DefaultsKey.switcherAppRules: ["test.excluded": "hidden"]]
        Enumerator.RunningApplication.apps[10] = .init()
        Windows.items = [other]
        func finishScan() {
            Queues.scans.drain()
            Queues.main.deliveries.drain()
        }
        inventory.start()
        suite.expect(inventory.excludesFrontmostApp(pid: new.pid, regularBundleIdentifier: "test.excluded")
                     && !inventory.isReady && Windows.reads.isEmpty && Queues.main.debounce.pending.isEmpty
                     && Queues.scans.pending.count == 1,
                     "Never show resolves a regular front app before the startup scan without requesting another read")
        finishScan()

        var pending: UInt64?
        var results: [UInt64: [CGWindowID]] = [:]
        func resume() {
            guard let generation = pending, inventory.readyForSession(currentSpaceOnly: true),
                  let selection = inventory.selection(for: generation, scope: .frontmostApp,
                                                      frontmostPID: new.pid, displayScope: nil) else { return }
            results[generation] = selection.list.items.compactMap(\.windowID)
            pending = nil
        }
        inventory.onReady = { _ in resume() }
        func press(_ generation: UInt64) {
            pending = generation
            resume()
        }

        // An earlier scan already saw the old desktop, but main has not yet adopted it.
        Opening.Events.shared.deliver?(.membershipChanged)
        Queues.main.debounce.drain()
        Queues.scans.drain()
        Windows.items.append(new)
        Opening.Events.shared.deliver?(.changed(2))
        press(1)
        suite.expect(pending == 1 && inventory.isReady && Queues.discoveries.pending.count == 1,
                     "the shortcut waits for the new front-app window while its owner is still being discovered")
        Queues.main.deliveries.drain()
        suite.expect(pending == 1 && results.isEmpty,
                     "a scan captured before the shortcut cannot confirm its empty list")
        Queues.discoveries.drain()
        Queues.main.deliveries.drain()
        Queues.main.debounce.drain()
        finishScan()
        suite.expect(results[1] == [2] && Windows.reads == [nil, nil, nil],
                     "one coalesced scan delivers the new window to the original shortcut")

        // A nonempty selection stays on the remembered path even during an invalidation.
        Opening.Events.shared.deliver?(.changed(2))
        press(2)
        suite.expect(results[2] == [2] && Windows.reads.count == 3 && Queues.scans.pending.isEmpty,
                     "a warm shortcut opens immediately during the event debounce")
        Queues.main.debounce.drain()
        finishScan()
        suite.expect(Windows.reads == [nil, nil, nil, new.pid],
                     "the successful warm shortcut leaves the scheduled refresh scoped to the changed app")

        Opening.Events.shared.deliver?(.destroyed(2))
        Windows.items = [other]
        Queues.main.debounce.drain()
        finishScan()
        // A shortcut can beat even the window-created notification. Its fresh scan may be
        // superseded by another shortcut after the worker captured an empty desktop.
        press(3)
        Queues.main.debounce.drain()
        Queues.scans.drain()
        press(4)
        Queues.main.deliveries.drain()
        suite.expect(pending == 4 && results[3] == nil && results[4] == nil,
                     "an older shortcut's empty result cannot consume its replacement")
        Windows.items.append(new)
        Queues.main.debounce.drain()
        finishScan()
        suite.expect(results[3] == nil && results[4] == [2],
                     "the replacement gets the new window even before its creation notification arrives")

        Opening.Events.shared.deliver?(.destroyed(2))
        Windows.items = [other]
        press(5)
        Queues.main.debounce.drain()
        finishScan()
        suite.expect(results[5] == [] && pending == nil && Queues.main.debounce.pending.isEmpty && Queues.scans.pending.isEmpty,
                     "a still-empty front-app scope finishes once without queuing another scan")

        press(6)
        Queues.main.debounce.drain()
        Queues.scans.drain()
        // This scan belongs to the shortcut, but a window appeared after it captured the desktop.
        Windows.items.append(new)
        Opening.Events.shared.deliver?(.changed(2))
        Queues.main.deliveries.drain()
        suite.expect(pending == 6 && results[6] == nil,
                     "a window discovered after the confirmation captured an empty list keeps the shortcut pending")
        Queues.discoveries.drain()
        Queues.main.deliveries.drain()
        Queues.main.debounce.drain()
        finishScan()
        suite.expect(pending == nil && results[6] == [2],
                     "the next scan includes the window that appeared during confirmation")

        Opening.Events.shared.deliver?(.destroyed(2))
        Windows.items = [other]
        let previousReads = Windows.reads.count
        press(7)
        Queues.main.debounce.drain()
        Queues.scans.drain()
        Opening.Events.shared.deliver?(.changed(99)) // Gone before its owner can be looked up.
        Queues.main.deliveries.drain()
        suite.expect(pending == 7, "a discovery already known at confirmation keeps the shortcut pending")
        Queues.discoveries.drain()
        Queues.main.deliveries.drain()
        Queues.main.debounce.drain()
        Queues.scans.drain()
        Opening.Events.shared.deliver?(.changed(1)) // Another app changes during the final scan.
        Queues.main.deliveries.drain()
        suite.expect(results[7] == [] && pending == nil && Windows.reads.count == previousReads + 2,
                     "an ignored discovery wakes the shortcut and later background traffic cannot extend its final read")
        Queues.main.debounce.drain()
        finishScan()
        suite.expect(Array(Windows.reads.dropFirst(previousReads)) == [nil, nil, other.pid] && Queues.main.debounce.pending.isEmpty,
                     "only the other app is refreshed after the shortcut has finished")
    }

    private static func frontmostHelperRules(_ suite: TestSuite) {
        let previous = Preferences.standard.values
        defer { Preferences.standard.values = previous }
        let hosted = SwitcherItem.window(id: 5, title: "Document", appName: "Editor",
                                        pid: 10, windowOwnerPID: 11, isOnScreen: true, frame: .zero)
        var remembered = Enumerator.WindowList(items: [hosted], sourceItems: [])
        remembered.bundleIdentifiers = [10: "test.editor", 11: "test.helper", 12: "test.helper"]
        func excluded(_ pid: pid_t, regularBundleIdentifier: String? = nil) -> Bool {
            Selection.excludesFrontmostApp(pid: pid, regularBundleIdentifier: regularBundleIdentifier,
                                          remembered: remembered)
        }

        Preferences.standard.values = [DefaultsKey.switcherAppRules: ["test.editor": "hidden"]]
        suite.expect(excluded(10) && excluded(11), "the host and its known helper both use the host's Never show rule")
        Preferences.standard.values = [DefaultsKey.switcherAppRules: ["test.helper": "hidden",
                                                                     "test.editor": "windowsOnly"]]
        suite.expect(!excluded(11) && !excluded(12),
                     "a helper's own rule cannot hide its allowed host or preempt discovery of an unknown host")
        suite.expect(!excluded(10, regularBundleIdentifier: "test.editor"),
                     "a Windows only app can still gain its first window")
        Preferences.standard.values = [DefaultsKey.switcherAppRules: ["test.editor": "showWithoutWindows"]]
        suite.expect(!excluded(10, regularBundleIdentifier: "test.editor"),
                     "Show without windows leaves the front-app shortcut available")
    }

    private static func ownWindowScreenChanges(_ suite: TestSuite) {
        let editor = OwnWindow()
        guard let id = Inventory.WindowEnumerator.ownWindowID(for: editor) else {
            suite.expect(false, "a visible titled capture editor is eligible for the inventory")
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let bounds = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                      CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        let snapshot = Enumerator.Snapshot(accessibilityGranted: false, runningApps: [],
                                           ownWindowTitles: [id: "Capture Editor"], screenFrames: bounds,
                                           displayIDsByUUID: [:])
        Enumerator.raw = [[kCGWindowNumber as String: NSNumber(value: id),
                           kCGWindowOwnerPID as String: NSNumber(value: pid),
                           kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: true,
                           kCGWindowBounds as String: ["X": 100, "Y": 0, "Width": 640, "Height": 480]]]
        SwitcherFullscreenScopeTests.Bridge.memberships = [id: [1]]
        defer {
            Enumerator.raw = []
            SwitcherFullscreenScopeTests.Bridge.memberships = [:]
        }
        var remembered = Enumerator.rememberSwitcherWindows(snapshot: snapshot, isCancelled: { false })
        func windows(on index: Int) -> [CGWindowID] {
            Selection.select(remembered: remembered, scope: .allWindows, frontmostPID: pid,
                             focusedWindowID: id, displayScope: .init(bounds: bounds, targetIndex: index))
                .items.compactMap(\.windowID)
        }
        suite.expect(remembered.items.first?.pid == pid && remembered.items.first?.title == "Capture Editor"
                     && windows(on: 0) == [id] && windows(on: 1).isEmpty,
                     "the capture editor is listed on the first display with its own process ID")
        let inventory = Inventory()
        var requests: [pid_t?] = []
        inventory.onInvalidate = { owner in
            requests.append(owner)
            remembered = Enumerator.rememberSwitcherWindows(snapshot: snapshot, filterPID: owner, isCancelled: { false })
        }
        let center = NotificationCenter()
        let observers = inventory.observeScreenChanges(in: center)
        defer { for observer in observers { center.removeObserver(observer) } }
        Enumerator.raw[0][kCGWindowBounds as String] = ["X": 1100, "Y": 0, "Width": 640, "Height": 480]
        center.post(name: NSWindow.didMoveNotification, object: editor)
        suite.expect(requests.isEmpty && windows(on: 0) == [id] && windows(on: 1).isEmpty,
                     "ordinary movement and shortcut selection leave the remembered frame intact")
        func changeScreen(_ window: OwnWindow) {
            center.post(name: NSWindow.didChangeScreenNotification, object: window)
        }
        changeScreen(editor)
        suite.expect(requests == [pid] && windows(on: 0).isEmpty && windows(on: 1) == [id],
                     "a screen change refreshes only the editor's process and moves its entry within the same Space")

        let helpers: [(String, (OwnWindow) -> Void)] = [
            ("the Switcher panel", {
                $0.styleMask = [.borderless, .nonactivatingPanel]
                $0.level = .statusBar
            }),
            ("a borderless window", { $0.styleMask = .borderless }),
            ("a floating titled window", { $0.level = .floating }),
            ("a window unable to become key", { $0.canBecomeKey = false }),
            ("a hidden window", { $0.isVisible = false }),
            ("an unallocated window", { $0.windowNumber = -1 })
        ]
        for (name, configure) in helpers {
            let helper = OwnWindow()
            helper.windowNumber = 43
            configure(helper)
            changeScreen(helper)
            suite.expect(requests == [pid], "a screen change for \(name) leaves the inventory idle")
        }
        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        suite.expect(requests == [pid, nil], "a display configuration change still refreshes the whole inventory")
    }
}
