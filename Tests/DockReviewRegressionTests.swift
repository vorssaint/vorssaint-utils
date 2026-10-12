// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Production declarations are compiled against inert doubles by generate_sources.py.
/// No application is terminated, captured, or shown by these checks.
enum DockReviewRegressionTests {
    final class NSRunningApplication {
        let processIdentifier: pid_t
        let bundleURL: URL?
        let localizedName: String?
        var bundleIdentifier: String? { nil }
        var isTerminated = false
        init(_ pid: pid_t, _ path: String, _ name: String) {
            processIdentifier = pid; bundleURL = URL(fileURLWithPath: path); localizedName = name
        }
        convenience init?(processIdentifier: pid_t) {
            guard let app = Self.inventory.first(where: { $0.processIdentifier == processIdentifier }) else { return nil }
            self.init(app.processIdentifier, app.bundleURL!.path, app.localizedName!)
            isTerminated = app.isTerminated
        }
        static func runningApplications(withBundleIdentifier: String) -> [NSRunningApplication] { [dock] }
        static let dock = NSRunningApplication(900, "/Dock.app", "Dock")
        static var inventory: [NSRunningApplication] = []
    }
    enum DockAccessibility {
        typealias NSRunningApplication = DockReviewRegressionTests.NSRunningApplication

        struct Item { let url: URL?; let title: String; let frame: CGRect }
        static var current: [Item] = []
        static func items() -> [Item] { current }
        static func quartz(_ point: CGPoint) -> CGPoint { point }
        static func application(for item: Item) -> NSRunningApplication? { application(for: item, apps: NSRunningApplication.inventory) }
        static func processArguments(_ pid: pid_t) -> String { "" }
    }
    enum DefaultsKey { static let dockPreviewEnabled = "tests.dockReview.enabled" }
    enum AppFeature {
        struct Feature { var isAvailable = true }
        static var dockPreview = Feature()
    }
    final class SessionActivity { static let shared = SessionActivity(); var isActive = true }
    final class DockPreviewService {
        static let shared = DockPreviewService()
        var inputExclusionFrames: [CGRect] = []
        var hides = 0
        func hideAllPreviews() { hides += 1 }
    }
    final class DockWidgetService {
        static let shared = DockWidgetService()
        var covered = false
        func panelCovers(_ point: CGPoint) -> Bool { covered }
        func isMediaApp(_ pid: pid_t) -> Bool { false }
    }
    enum WindowServerSupport {
        static var windows: [MouseAppExceptionSupport.Window] = []
        static func onScreenWindows() -> [MouseAppExceptionSupport.Window] { windows }
    }
    final class InputGuard {
        typealias NSRunningApplication = DockReviewRegressionTests.NSRunningApplication
        typealias SessionActivity = DockReviewRegressionTests.SessionActivity
        typealias AppFeature = DockReviewRegressionTests.AppFeature
        typealias DefaultsKey = DockReviewRegressionTests.DefaultsKey
        typealias DockPreviewService = DockReviewRegressionTests.DockPreviewService
        typealias DockWidgetService = DockReviewRegressionTests.DockWidgetService
        typealias WindowServerSupport = DockReviewRegressionTests.WindowServerSupport
        typealias DockAccessibility = DockReviewRegressionTests.DockAccessibility

        struct Tile { let rect: CGRect; let pid: pid_t; let bundleURL: URL? }
        final class Tap { var isRunning = true }
        let inputTap = Tap()
        struct OwnWindow { let frame: CGRect; let isVisible: Bool; let ignoresMouseEvents: Bool }
        struct OwnApp { var windows: [OwnWindow] = [] }
        var NSApp = OwnApp()
        var trusted = true
        var hitPID: pid_t? = 900
        func AXIsProcessTrusted() -> Bool { trusted }
        func AXUIElementCreateSystemWide() -> AXUIElement { ApplicationServices.AXUIElementCreateSystemWide() }
        func AXUIElementSetMessagingTimeout(_ element: AXUIElement, _ timeout: Float) -> AXError { .success }
        func AXUIElementCopyElementAtPosition(_ element: AXUIElement, _ x: Float, _ y: Float, _ hit: UnsafeMutablePointer<AXUIElement?>) -> AXError {
            hit.pointee = element; return hitPID == nil ? .failure : .success
        }
        func AXUIElementGetPid(_ element: AXUIElement, _ pid: UnsafeMutablePointer<pid_t>) -> AXError {
            pid.pointee = hitPID ?? 0; return .success
        }
    }
    enum Ordering {}
    struct MinimizePanel { let windows: [SwitcherItem]; let onToggleMinimized: (SwitcherItem) -> Void }
    final class Work {
        var active = true
        var stops = 0
        func stop() { active = false; stops += 1 }
        func end() { stop() }
        func cancel() { stop() }
        func cachedPreview(for id: CGWindowID) -> CGImage? { nil }
        func refreshPreviews(for items: [SwitcherItem], maxPixelSize: CGFloat, excludedAppsKey: String, update: (CGWindowID, CGImage) -> Void) { active = true }
        func start(_ items: [SwitcherItem], excludedAppsKey: String, update: (CGWindowID, CGImage) -> Void) { active = true }
    }
    final class WindowPreviewProvider { static let shared = Work() }
    enum CompactLayout { static func compact(_ count: Int) -> Bool { count >= 2 } }
    final class Surface {
        typealias NSRunningApplication = DockReviewRegressionTests.NSRunningApplication
        typealias DockPreviewPreferences = DockReviewRegressionTests.DockPreviewPreferences
        typealias DockWidgetService = DockReviewRegressionTests.DockWidgetService
        typealias DockHit = DockReviewRegressionTests.DockHit
        typealias DockPreviewLayout = DockReviewRegressionTests.CompactLayout
        typealias WindowPreviewProvider = DockReviewRegressionTests.WindowPreviewProvider
        typealias WindowEnumerator = DockReviewRegressionTests.WindowEnumerator

        let livePreviews = Work(), hoverPreview = Work()
        struct Prefetch { let app: DockReviewRegressionTests.NSRunningApplication; let windows: [SwitcherItem]? }
        var pendingHover: Prefetch?
        var isVisible = true, isPinned = false, hasEnteredPanel = false
        var isRunning = true, externalSession = false
        var cachedPreferences: DockPreviewPreferences?
        var hit: DockHit?
        var resizes = 0
        var currentSessionPID: pid_t?
        var currentAppName: String?
        var windows: [SwitcherItem] = []
        var previews: [CGWindowID: CGImage] = [:]
        var selectedWindowID: CGWindowID?
        static var candidates: [SwitcherItem] = []
        static func previewableWindows(for pid: pid_t) -> [SwitcherItem] { candidates }
        func cancelPendingHover() { pendingHover = nil }
        func cancelPendingHide() {}
        func tearDownVisuals() { windows = []; previews = [:] }
        func endSession() { stopSessionWork(); isVisible = false; externalSession = false; windows = []; currentSessionPID = nil }
        func beginDockAutohideHold() {}
        func showPanel(for hit: DockHit, itemCount: Int) { self.hit = hit; isVisible = true }
        func resizePanelForCurrentWindows() { resizes += 1 }
    }
    enum WindowEnumerator {
        static var candidates: [pid_t: [SwitcherItem]] = [:]
        static func listWindows(for pid: pid_t, maximumCount: Int) -> [SwitcherItem] { candidates[pid] ?? [] }
    }
    enum LockMusicService { static var shared = NotchMusicCommandContract.Service() }
    final class SourceWork {
        var stops = 0
        func stop() { stops += 1 }
        func pause() { stops += 1 }
        func syncWithPreferences() {}
    }
    enum DownloadService { static let shared = SourceWork() }
    enum CalendarService { static let shared = SourceWork() }
    enum AgentService { static let shared = SourceWork() }
    enum LockSupport { static var enabled = true; static func isEnabled() -> Bool { enabled } }
    enum CalendarSupport { static func chosenCountdowns() -> [String] { [] } }
    final class LockSurface {
        typealias NotchMusicService = DockReviewRegressionTests.LockMusicService
        typealias NotchDownloadService = DockReviewRegressionTests.DownloadService
        typealias NotchCalendarService = DockReviewRegressionTests.CalendarService
        typealias AgentUsageService = DockReviewRegressionTests.AgentService
        typealias NotchLockScreenSupport = DockReviewRegressionTests.LockSupport
        typealias NotchCalendarSupport = DockReviewRegressionTests.CalendarSupport
        final class NotchLockScreenModel {
            struct Gates { var music = false, downloads = false, countdown = false, timeLeft = false, agents = false }
            var playedWhileLocked = false, padlockOpen = false
        }
        final class Panel { func orderOut(_ sender: Any?) {} }
        final class Space { var closed = false; func close() { closed = true } }
        var model = NotchLockScreenModel(), wasLocked = false
        var scene: [Panel] = [], island: Panel?, space: Space?
        var playbackSubscription: NSObject?, screenObserver: NSObjectProtocol?, padlockWork: DispatchWorkItem?
        func show(closingPadlock: Bool) {
            guard space == nil else { return }
            scene = [Panel()]; space = Space(); startSources(.init(music: true))
        }
        static func fadeOut(_ panel: Panel, after delay: TimeInterval, completion: @escaping () -> Void) { completion() }
    }
    final class IndicatorService { static let shared = Work() }
    final class LockService { static let shared = Work() }
    final class WidgetService { static let shared = Work() }
    final class InputService { static let shared = Work() }
    final class CmdTabService { static let shared = Work() }
    final class TrackpadService { static let shared = Work() }
    final class Runtime {
        typealias DockIndicatorService = DockReviewRegressionTests.IndicatorService
        typealias DockLockService = DockReviewRegressionTests.LockService
        typealias DockWidgetService = DockReviewRegressionTests.WidgetService
        typealias DockInputService = DockReviewRegressionTests.InputService
        typealias CmdTabPreviewService = DockReviewRegressionTests.CmdTabService
        typealias TrackpadWindowSwitcher = DockReviewRegressionTests.TrackpadService
        typealias DockPreviewService = DockReviewRegressionTests.DockPreviewService
        var pending: DispatchWorkItem?
        var captureSettings: [String]?
        var loaded = Set<String>()
    }
    final class Permissions { static let shared = Permissions(); var accessibility = true }
    final class MusicService {
        enum Consumer { case dock }
        static let shared = MusicService()
        var owners = 0
        func start(consumer: Consumer) { owners = 1 }
        func stop(consumer: Consumer) { owners = 0 }
    }
    final class WidgetSync {
        typealias AppFeature = DockReviewRegressionTests.AppFeature
        typealias DefaultsKey = DockReviewRegressionTests.DefaultsKey
        typealias Permissions = DockReviewRegressionTests.Permissions
        typealias SessionActivity = DockReviewRegressionTests.SessionActivity
        typealias NotchMusicService = DockReviewRegressionTests.MusicService
        var musicWanted = false
        var timer: Timer?
        var panel: NSPanel?
        var candidate: String?
        var kind: String?
        func allows(_ kind: String) -> Bool { true }
        func dismiss() { kind = nil }
        func sample() {}
    }
    struct DockPreviewPreferences {
        let orientation: DockPreviewOrientation
        let autohide: Bool
        let tileSize: Double
        let magnification: Bool
        let magnifiedTileSize: Double
    }
    struct DockHit { let app: NSRunningApplication; let iconFrame: CGRect; let preferences: DockPreviewPreferences }
    static func item(_ id: CGWindowID, _ title: String, minimized: Bool = false, pid: pid_t = 1) -> SwitcherItem {
        SwitcherItem(id: String(id), title: title, appName: title, pid: pid, windowOwnerPID: pid,
            windowID: id, isOnScreen: true, isAppHidden: false, isMinimized: minimized,
            isFullscreen: false, isOnHiddenSpace: false, frame: .zero)
    }
    static func run(_ suite: TestSuite) {
        let saved = [DockOption.sortOrder.key, DockOption.windowTitleFilters.key, DefaultsKey.dockPreviewEnabled, DockOption.folders.key, DockOption.mediaWidget.key, DockOption.calendarWidget.key].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in saved { if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
            NSRunningApplication.inventory = []; DockAccessibility.current = []; WindowServerSupport.windows = []
            WindowEnumerator.candidates = [:]; LockMusicService.shared.stop(consumer: .lockScreen)
            LockMusicService.shared.stop(consumer: .island); LockMusicService.shared.stop(consumer: .dock)
            DockPreviewService.shared.inputExclusionFrames = []; DockWidgetService.shared.covered = false
            SessionActivity.shared.isActive = true; AppFeature.dockPreview.isAvailable = true
        }
        let appA = NSRunningApplication(101, "/closed-A/Editor.app", "Editor")
        let appB = NSRunningApplication(202, "/running-B/Editor.app", "Editor")
        let rect = CGRect(x: 0, y: 0, width: 40, height: 40)
        let tileA = DockAccessibility.Item(url: appA.bundleURL, title: "Editor", frame: rect)
        suite.expect(DockAccessibility.application(for: tileA, apps: [appB]) == nil, "a closed pinned app never resolves to a same-name running app at a different path")
        suite.expect(DockAccessibility.application(for: tileA, apps: [appA, appB]) === appA, "an exact launcher path wins over a duplicate display name")
        let unnamedURL = DockAccessibility.Item(url: nil, title: "Editor", frame: rect)
        suite.expect(DockAccessibility.application(for: unnamedURL, apps: [appB]) === appB, "unique title fallback still works when the Dock has no URL")
        suite.expect(DockAccessibility.application(for: unnamedURL, apps: [appA, appB]) == nil, "ambiguous no-URL labels refuse arbitrary process selection")
        let duplicate = NSRunningApplication(303, "/closed-A/Editor.app", "Editor")
        suite.expect(DockAccessibility.application(for: tileA, apps: [appA, duplicate]) == nil, "identical launcher processes remain ambiguous")

        let current = item(9, "Zulu"), other = item(1, "Alpha")
        for sort in ["title", "app", "creation", "recent"] {
            UserDefaults.standard.set(sort, forKey: DockOption.sortOrder.key)
            UserDefaults.standard.set("", forKey: DockOption.windowTitleFilters.key)
            let prepared = Ordering.sessionItems([current, other], currentID: current.id)
            let index = SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: prepared.count, hasForegroundItem: true, reversed: false)
            suite.expect(prepared.first == current && prepared[index] == other, "\(sort) sorting retains foreground and selects a different window on first invocation")
        }
        UserDefaults.standard.set("Zulu", forKey: DockOption.windowTitleFilters.key)
        let filtered = Ordering.sessionItems([current, other], currentID: current.id)
        suite.expect(filtered == [other] && !filtered.contains(current), "filtered source membership is recomputed from the displayed entries")
        UserDefaults.standard.set("Zulu\nAlpha", forKey: DockOption.windowTitleFilters.key)
        suite.expect(Ordering.sessionItems([current, other], currentID: current.id).isEmpty, "filters can remove every entry before starting a session")

        UserDefaults.standard.set(true, forKey: DefaultsKey.dockPreviewEnabled)
        NSRunningApplication.inventory = [appA, appB]
        DockAccessibility.current = [tileA]
        let guarder = InputGuard(), point = CGPoint(x: 20, y: 20)
        let cached = InputGuard.Tile(rect: rect, pid: 101, bundleURL: appA.bundleURL)
        WindowServerSupport.windows = [.init(frame: rect, layer: Int(CGWindowLevelForKey(.dockWindow)), processID: 900)]
        func accepted(age: Double = 0) -> Bool { guarder.valid(cached, at: point, sampledAt: ProcessInfo.processInfo.systemUptime - age) }
        suite.expect(accepted(), "fresh visible Dock click still permits its exact intended app")
        DockAccessibility.current = [.init(url: appB.bundleURL, title: "Editor", frame: rect)]
        suite.expect(!accepted(), "magnification moving a neighboring tile under the click cancels the cached quit")
        DockAccessibility.current = [tileA]
        DockPreviewService.shared.inputExclusionFrames = [rect]
        suite.expect(!accepted(), "preview and pinned panel clicks never target an underlying Dock app")
        DockPreviewService.shared.inputExclusionFrames = []; DockWidgetService.shared.covered = true
        suite.expect(!accepted(), "widget overlays own their clicks")
        DockWidgetService.shared.covered = false
        guarder.NSApp.windows = [.init(frame: rect, isVisible: true, ignoresMouseEvents: false)]
        suite.expect(!accepted(), "an interactive window owned by Vorssaint blocks input aimed beneath it")
        guarder.NSApp.windows = [.init(frame: rect, isVisible: true, ignoresMouseEvents: true)]
        suite.expect(accepted(), "mouse-transparent indicator overlays do not block legitimate Dock clicks")
        guarder.NSApp.windows = []
        WindowServerSupport.windows = []
        suite.expect(!accepted(), "hidden or other-display Dock geometry cannot authorize termination")
        WindowServerSupport.windows = [.init(frame: rect, layer: 100, processID: 505), .init(frame: rect, layer: Int(CGWindowLevelForKey(.dockWindow)), processID: 900)]
        guarder.hitPID = 505
        suite.expect(!accepted(), "a covering app whose AX hit owns the point blocks a Dock action")
        guarder.hitPID = 900
        suite.expect(accepted(), "a click-through overlay with a confirmed Dock AX hit permits the intended action")
        guarder.trusted = false
        suite.expect(!accepted(), "revoked Accessibility blocks queued input actions")
        guarder.trusted = true
        suite.expect(!accepted(age: 1), "a delayed queued click cannot terminate an app after its input intent expires")
        guarder.inputTap.isRunning = false
        suite.expect(!accepted(), "disabling input cancels actions already queued on main")

        for orientation: DockPreviewOrientation in [.bottom, .left, .right] {
            var gesture = PreviewSwipeGesture()
            let parallel = orientation == .bottom ? CGPoint(x: 80, y: 3) : CGPoint(x: 3, y: 80)
            suite.expect(gesture.sample(x: parallel.x, y: parallel.y, orientation: orientation) == .passThrough, "\(orientation) parallel scrolling reaches offscreen cards")
            suite.expect(gesture.sample(x: 80, y: 80, orientation: orientation) == .passThrough, "a scroll stays locked to navigation despite later cross-axis noise")
            gesture.reset()
            let away: CGPoint = orientation == .bottom ? CGPoint(x: 1, y: 60) : CGPoint(x: orientation == .left ? -60 : 60, y: 1)
            suite.expect(gesture.sample(x: away.x, y: away.y, orientation: orientation) == .maximize, "\(orientation) deliberate perpendicular swipe still maximizes")
            suite.expect(gesture.sample(x: away.x, y: away.y, orientation: orientation) == .consume, "one gesture fires only once")
            gesture.reset()
            suite.expect(gesture.sample(x: -away.x, y: -away.y, orientation: orientation) == .minimize, "\(orientation) reverse perpendicular swipe still minimizes")
        }
        for entries in [[item(1, "A"), item(2, "B", minimized: true)], [item(1, "A", minimized: true)], [item(1, "A"), item(2, "B")]] {
            var toggled: [String] = []
            MinimizePanel(windows: entries, onToggleMinimized: { toggled.append($0.id) }).minimizeAllWindows()
            suite.expect(toggled == entries.filter { !$0.isMinimized }.map(\.id), "Minimize all skips already-minimized windows in mixed, all-minimized and normal lists")
        }
        let surface = Surface()
        surface.stopSessionWork()
        suite.expect(!surface.livePreviews.active && !surface.hoverPreview.active && !WindowPreviewProvider.shared.active, "session handover releases live, hover and snapshot work before compact replacement")
        let runtime = Runtime()
        var starts = 0, stops = 0
        for wanted in [true, true, false, false] { runtime.run("test", wanted: wanted, start: { starts += 1 }, stop: { stops += 1 }) }
        suite.expect(starts == 2 && stops == 1 && runtime.loaded.isEmpty, "repeated preference sync releases ownership once and forgets stopped services")
        runtime.run("test", wanted: true, start: { starts += 1 }, stop: { stops += 1 })
        suite.expect(runtime.loaded == ["test"] && starts == 3, "a stopped service can be enabled again")
        runtime.loaded = ["indicator", "lock", "widgets", "input", "cmdtab", "trackpad", "dockSurface"]
        runtime.captureSettings = ["old"]
        let pending = DispatchWorkItem {}
        runtime.pending = pending
        runtime.stop()
        suite.expect(runtime.loaded.isEmpty && runtime.captureSettings == nil && pending.isCancelled, "global stop clears service ownership and cancels pending preference work")
        let stopCounts = [IndicatorService.shared.stops, LockService.shared.stops, WidgetService.shared.stops, InputService.shared.stops, CmdTabService.shared.stops, TrackpadService.shared.stops, DockPreviewService.shared.hides]
        runtime.stop()
        suite.expect(stopCounts == [IndicatorService.shared.stops, LockService.shared.stops, WidgetService.shared.stops, InputService.shared.stops, CmdTabService.shared.stops, TrackpadService.shared.stops, DockPreviewService.shared.hides], "repeated global stop does not repeatedly instantiate or tear down stopped services")
        let widget = WidgetSync()
        for option in [DockOption.folders, .mediaWidget, .calendarWidget] { UserDefaults.standard.set(false, forKey: option.key) }
        widget.syncWithPreferences()
        suite.expect(widget.timer == nil && MusicService.shared.owners == 0, "all-disabled widgets allocate neither a polling timer nor the media adapter")
        for option in [DockOption.folders, .mediaWidget, .calendarWidget] {
            UserDefaults.standard.set(true, forKey: option.key)
            widget.syncWithPreferences()
            suite.expect(widget.timer != nil && MusicService.shared.owners == (option == .mediaWidget ? 1 : 0), "each enabled widget starts its timer and only media acquires the adapter")
            UserDefaults.standard.set(false, forKey: option.key)
            widget.syncWithPreferences()
            suite.expect(widget.timer == nil && MusicService.shared.owners == 0, "disabling the last widget stops polling and releases media")
        }
        let replacement = Surface()
        WindowPreviewProvider.shared.active = true
        Surface.candidates = [current, other]
        replacement.beginSession(DockHit(app: appB, iconFrame: rect, preferences: DockPreviewPreferences(orientation: .bottom, autohide: false, tileSize: 48, magnification: false, magnifiedTileSize: 64)))
        suite.expect(replacement.windows == [current, other] && !replacement.livePreviews.active && !replacement.hoverPreview.active && !WindowPreviewProvider.shared.active, "switching an existing thumbnail panel to a compact app stops old work without restarting captures")
        Surface.candidates = []
        replacement.beginSession(DockHit(app: appA, iconFrame: rect, preferences: DockPreviewPreferences(orientation: .bottom, autohide: false, tileSize: 48, magnification: false, magnifiedTileSize: 64)))
        suite.expect(!replacement.isVisible, "a handover to an app with no windows closes the old session")
        for orientation: DockPreviewOrientation in [.bottom, .left, .right] {
            Surface.candidates = [current, other]
            let placement = Surface()
            placement.cachedPreferences = DockPreviewPreferences(orientation: orientation, autohide: true, tileSize: 48, magnification: true, magnifiedTileSize: 64)
            placement.show(for: appA, anchor: rect, external: true)
            suite.expect(placement.hit?.preferences.orientation == orientation && placement.externalSession, "scripted Dock anchors retain \(orientation) placement and external session lifetime")
            placement.show(for: appA, anchor: rect, external: true, centeredPlacement: true)
            suite.expect(placement.hit?.preferences.orientation == .bottom && placement.hit?.preferences.autohide == false, "native Command-Tab and fallback anchors use bottom placement independently of session lifetime")
        }
        let external = Surface()
        external.isVisible = false
        external.cachedPreferences = DockPreviewPreferences(orientation: .bottom, autohide: false, tileSize: 48, magnification: false, magnifiedTileSize: 64)
        Surface.candidates = []
        external.show(for: appA, anchor: rect, external: true)
        suite.expect(!external.isVisible && !external.externalSession, "an external app with no previewable windows does not suppress subsequent Dock hovers")
        external.closePreviewPanel()
        Surface.candidates = [current]
        external.beginSession(DockHit(app: appB, iconFrame: rect, preferences: external.cachedPreferences!))
        suite.expect(external.isVisible && !external.externalSession, "ordinary Dock preview still opens after an empty or fully filtered external request")
        external.isPinned = true
        external.show(for: appA, anchor: rect, external: true)
        suite.expect(external.isPinned && !external.externalSession && external.currentSessionPID == appB.processIdentifier, "a rejected external request does not claim an existing pinned Dock session")
        external.isPinned = false
        external.show(for: appA, anchor: rect, external: true)
        suite.expect(external.externalSession, "a successfully opened external panel retains its external lifetime")
        external.closePreviewPanel()
        suite.expect(!external.isVisible && !external.externalSession, "closing an external panel restores normal Dock hover handling")

        let grouped = Surface(), primary = item(50, "Primary", pid: 101), sibling = item(51, "Sibling", pid: 102)
        grouped.currentSessionPID = primary.pid
        grouped.windows = [primary, sibling]; grouped.selectedWindowID = sibling.windowID
        grouped.finishClosing(sibling, windowID: 51, attempt: 0)
        suite.expect(grouped.windows == [primary] && grouped.selectedWindowID == nil && grouped.resizes == 1,
                     "confirmed closing of a grouped sibling removes its dead card and resizes the main panel")
        grouped.finishClosing(primary, windowID: 50, attempt: 0)
        suite.expect(!grouped.isVisible && grouped.windows.isEmpty, "closing the last primary card still ends the panel session")
        grouped.isVisible = true; grouped.windows = [sibling]
        WindowEnumerator.candidates[sibling.pid] = [sibling]
        grouped.finishClosing(sibling, windowID: 51, attempt: 2)
        suite.expect(grouped.windows == [sibling], "an unconfirmed close never removes a live grouped window")
        WindowEnumerator.candidates = [:]
        grouped.windows = [item(51, "Replacement", pid: 103)]
        grouped.finishClosing(sibling, windowID: 51, attempt: 0)
        suite.expect(grouped.windows.count == 1 && grouped.windows[0].pid == 103, "a stale close callback cannot remove another process's replacement card")
        grouped.isVisible = false; grouped.windows = [sibling]
        grouped.finishClosing(sibling, windowID: 51, attempt: 0)
        suite.expect(grouped.windows == [sibling], "a dismissed panel ignores delayed close confirmations")

        LockMusicService.shared = NotchMusicCommandContract.Service()
        let music = LockMusicService.shared, lock = LockSurface()
        var session = NotchSessionState(); session.locked = true
        lock.sync(session)
        suite.expect(music.consumers.owners == [.lockScreen] && music.wantsPlayback, "the displayed lock scene acquires its playback consumer")
        let launches = music.launches
        session.locked = false
        lock.sync(session, keepsMusicForHandoff: true)
        suite.expect(lock.scene.isEmpty && music.consumers.owners == [.lockScreen] && music.wantsPlayback,
                     "the early unlock hides the scene while keeping playback alive for the island handoff")
        music.start(consumer: .island)
        lock.sync(session)
        suite.expect(music.consumers.owners == [.island] && music.wantsPlayback && music.launches == launches,
                     "the final unlock sync releases lock-screen ownership without restarting the island's adapter")
        music.stop(consumer: .island)
        suite.expect(music.consumers.owners.isEmpty && !music.wantsPlayback && music.process == nil,
                     "after unlocking, disabling the island stops the adapter instead of retaining a ghost lock-screen owner")
        session.locked = true; lock.sync(session)
        session.locked = false; lock.sync(session, keepsMusicForHandoff: true)
        lock.sync(session)
        suite.expect(music.consumers.owners.isEmpty && !music.wantsPlayback, "a handoff with no island demand releases the lock-screen adapter")
        music.start(consumer: .dock)
        session.locked = true; lock.sync(session)
        session.locked = false; lock.sync(session, keepsMusicForHandoff: true)
        lock.close()
        suite.expect(music.consumers.owners == [.dock] && music.wantsPlayback,
                     "close releases a hidden pending lock-screen consumer while preserving the Dock's independent demand")
        music.stop(consumer: .dock)
        suite.expect(!music.wantsPlayback, "closing the final Dock consumer stops playback after lock-screen teardown")
        session.locked = true; lock.sync(session)
        let rebuildLaunches = music.launches
        lock.hide(unlocking: false, stopsSources: false, keepsMusic: true)
        lock.sync(session)
        suite.expect(music.consumers.owners == [.lockScreen] && music.launches == rebuildLaunches,
                     "rebuilding a lock-screen scene retains one music owner without restarting playback")
        session.locked = false; session.displaysSleeping = true
        lock.sync(session, keepsMusicForHandoff: true)
        suite.expect(music.consumers.owners.isEmpty && !music.wantsPlayback,
                     "an unlock that cannot return the island releases playback instead of retaining a pending handoff")
    }
}
