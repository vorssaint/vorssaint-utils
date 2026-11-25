// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Production hover, click callbacks, keyboard routing, commit, close and
/// teardown bodies run with synthetic entries and an explicit clock. Only OS
/// effects and layout are doubles. Private windows supply real WindowServer
/// IDs without posting input or changing desktop focus.
enum SwitcherHoverSelectionTests {
    typealias NSEvent = Pointer
    typealias NSWorkspace = Workspace
    typealias DispatchQueue = Queue
    typealias WindowActivator = Activator
    typealias WindowEnumerator = Enumerator
    typealias WindowUseTracker = SwitcherRememberedSelectionTests.SessionOpening.WindowUseTracker
    typealias SwitcherWindowInventory = SwitcherRememberedSelectionTests.SessionOpening.SwitcherWindowInventory
    typealias FrontAppEnumerator = SwitcherRememberedSelectionTests.SessionOpening.WindowEnumerator
    typealias SpaceWindowBridge = SwitcherRememberedSelectionTests.SessionOpening.SpaceWindowBridge
    typealias WindowPreviewProvider = WindowServerCaptureContract.Provider
    typealias SwitcherAppIconCache = IconCache
    typealias ScrollWheelHIDStage = HIDStage
    typealias MouseAppExceptions = Exceptions
    typealias CFMachPort = Tap

    final class Thread {
        var name: String?
        var qualityOfService: QualityOfService = .default
        private let work: () -> Void
        init(_ work: @escaping () -> Void) { self.work = work }
        func start() { work() }
    }

    enum Pointer { static var mouseLocation = NSPoint(x: 100, y: 100) }
    enum Permissions {
        static let shared = State()
        final class State { var accessibility = true }
    }
    final class Tap {
        var valid = true
        var enabled = false
        var acceptsEnable = true
        var enables = 0
        var onEnable: (() -> Void)?
        var onDisable: (() -> Void)?
        static func isValid(_ tap: Tap) -> Bool { tap.valid }
        static func isEnabled(tap: Tap) -> Bool { tap.enabled }
        static func enable(tap: Tap, enable: Bool) {
            tap.enabled = enable && tap.acceptsEnable
            if enable {
                tap.enables += 1
                tap.onEnable?()
            } else {
                tap.onDisable?()
            }
        }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        var isActive = true
    }
    enum Workspace {
        static let shared = State()
        final class State { var frontmostApplication: App? = App(processIdentifier: 10) }
        struct App {
            let processIdentifier: pid_t
            var bundleIdentifier: String? = nil
            var activationPolicy: NSApplication.ActivationPolicy = .regular
        }
    }
    enum AssistiveKeyboard { static func ownsPoint(_ point: CGPoint) -> Bool { false } }
    enum HIDStage {
        static let shared = State()
        struct State { func passed(_ event: CGEvent) -> Bool { false } }
    }
    enum Exceptions {
        enum Feature { case scrollDirection }
        static let shared = State()
        struct State {
            func excludesPointerTarget(_ feature: Feature, at point: CGPoint,
                                       sourceProcessID: Int64) -> Bool { false }
        }
    }
    enum IconCache {
        static func beginSession() {}
        static func endSession() {}
    }
    final class Panel {
        var isVisible = true
        let contentViewController: NSViewController? = nil
        let frame = CGRect(x: 0, y: 0, width: 600, height: 300)
        func orderOut(_ sender: Any?) { isVisible = false }
    }
    struct Instant {
        let time: TimeInterval
        static func now() -> Instant { Instant(time: Queue.time) }
        static func +(lhs: Instant, rhs: TimeInterval) -> Instant { Instant(time: lhs.time + rhs) }
    }
    enum Queue {
        static let main = Scheduler()
        static var time: TimeInterval = 0
        static var jobs: [(Instant, DispatchWorkItem)] = []
        static var mainIsBusy = false
        static var waitsWhileBusy = 0
        struct Scheduler {
            func async(execute body: @escaping () -> Void) {
                asyncAfter(deadline: .now(), execute: body)
            }
            func sync(execute body: () -> Void) {
                if Queue.mainIsBusy { Queue.waitsWhileBusy += 1 }
                else { body() }
            }
            func asyncAfter(deadline: Instant, execute work: DispatchWorkItem) {
                Queue.jobs.append((deadline, work))
            }
            func asyncAfter(deadline: Instant, execute body: @escaping () -> Void) {
                asyncAfter(deadline: deadline, execute: DispatchWorkItem(block: body))
            }
        }
        static func advance(to end: TimeInterval) {
            while let index = jobs.indices.min(by: { jobs[$0].0.time < jobs[$1].0.time }),
                  jobs[index].0.time <= end {
                let (deadline, work) = jobs.remove(at: index)
                time = deadline.time
                // Keep DispatchWorkItem's real cancellation behavior.
                work.perform()
            }
            time = end
        }
    }
    enum Activator {
        static var activated: [String] = []
        static var onActivation: ((SwitcherItem) -> Void)?
        static var lastHandoffSourcePID: pid_t?
        static var lastSourceWindowID: CGWindowID?
        static var closed: [(item: SwitcherItem, completion: (Bool) -> Void)] = []
        static func focusedWindowID(for pid: pid_t) -> CGWindowID? {
            FrontAppEnumerator.WindowActivator.focusedWindowID(for: pid)
        }
        static func activate(_ item: SwitcherItem, sourceWasFullscreen: Bool,
                             sourcePID: pid_t?, handoffSourcePID: pid_t?,
                             sourceWindowID: CGWindowID?, sourceWindowOwnerPID: pid_t?,
                             windowServerSnapshot: Any? = nil) {
            activated.append(item.id)
            lastHandoffSourcePID = handoffSourcePID
            lastSourceWindowID = sourceWindowID
            onActivation?(item)
        }
        static func closeWindowIncludingHiddenState(_ item: SwitcherItem,
                                                   completion: @escaping (Bool) -> Void) {
            closed.append((item, completion))
        }
    }
    enum Enumerator {
        typealias DisplayScope = SwitcherFullscreenScopeTests.Enumerator.DisplayScope
        static var listed: [SwitcherItem] = []
        static var reads = 0
        static func listWindows(for pid: pid_t, maximumCount: Int) -> [SwitcherItem] {
            reads += 1
            return listed.filter { $0.pid == pid }
        }
    }
    struct Grid {
        var columns = 3
        static let empty = Grid()
    }
    struct Row {
        var visibleIconCount = 3
        var columns = 3
        var isWrapped = false
        static let empty = Row()
    }
    final class Inventory {
        var observed: SwitcherRememberedSelectionTests.SessionOpening.SwitcherWindowInventory? {
            didSet { observed?.onRemoval = onRemoval }
        }
        var onRemoval: ((SwitcherWindowInventory.Removal) -> Void)? {
            didSet { observed?.onRemoval = onRemoval }
        }
        var currentSpaceRevision: Int { observed?.currentSpaceRevision ?? 0 }
        var knownWindowIDs: Set<CGWindowID> {
            observed?.knownWindowIDs ?? Set((items ?? []).compactMap(\.windowID))
        }
        static let sampleWindows: [SwitcherItem] = (0..<6).map { index in
            SwitcherItem.window(id: CGWindowID(index + 1), title: "Window \(index)", appName: "App \(index)",
                                pid: pid_t(index + 10), isOnScreen: true, frame: .zero)
        }
        var items: [SwitcherItem]? = Inventory.sampleWindows
        var onReady: (([SwitcherItem]) -> Void)?
        var removedIDs: Set<String> = []
        func readyForSession(currentSpaceOnly: Bool) -> Bool {
            observed?.readyForSession(currentSpaceOnly: currentSpaceOnly) ?? true
        }
        func afterAnnouncedWindows(frontmostPID: pid_t, isPending: @escaping () -> Bool, resume: @escaping (Bool) -> Void) -> Bool {
            observed?.afterAnnouncedWindows(frontmostPID: frontmostPID, isPending: isPending, resume: resume) ?? false
        }
        func excludesFrontmostApp(pid: pid_t, regularBundleIdentifier: String?) -> Bool {
            observed?.excludesFrontmostApp(pid: pid, regularBundleIdentifier: regularBundleIdentifier) ?? false
        }
        func groupedSource(frontmostPID: pid_t, representative: SwitcherItem) -> SwitcherWindowInventory.GroupedSource? {
            observed?.groupedSource(frontmostPID: frontmostPID, representative: representative)
        }
        func selection(for generation: UInt64, scope: SwitcherSessionScope, frontmostPID: pid_t,
                       displayScope: SwitcherFullscreenScopeTests.Enumerator.DisplayScope?, confirmedFocus: CGWindowID? = nil)
            -> (list: SwitcherFullscreenScopeTests.Enumerator.WindowList, focusedWindowID: CGWindowID?)? {
            if let observed {
                return observed.selection(for: generation, scope: scope, frontmostPID: frontmostPID,
                                          displayScope: displayScope, confirmedFocus: confirmedFocus)
            }
            return items.map { (.init(items: $0, sourceItems: $0), nil) }
        }
        func publish(_ items: [SwitcherItem]) {
            self.items = items
            onReady?(items)
        }
        func contains(_ item: SwitcherItem) -> Bool { observed?.contains(item) ?? !removedIDs.contains(item.id) }
        func start() {}
        func stop() {}
    }
    struct Watch {
        func start() {}
        func stop() {}
    }

    class Fixture {
        let windowInventory = Inventory()
        let frontAppReadQueue = SwitcherActivationTests.DeferredQueue()
        var sessionActive = false
        let routeLock = NSLock()
        let lifecycleLock = NSLock()
        var tap: Tap? {
            didSet {
                tap?.onDisable = { [weak self] in
                    self?.tapLifecycle.append("remove")
                    self?.onRemoveTap?()
                }
            }
        }
        var tapThread: Thread?
        var tapRunLoop: CFRunLoop?
        var runLoopSource: CFRunLoopSource?
        var shouldStopTapThread = false
        var pendingStartAfterStop = false
        var tapLifecycleGeneration: UInt = 0
        var startedTaps = 0
        var refusesPortCreation = false
        func createPort() -> Tap? { refusesPortCreation ? nil : Tap() }
        var routeTapRecoveryPending = false
        var switcherEnabled = true
        var tapIsWanted: Bool { switcherEnabled && Permissions.shared.accessibility && SessionActivity.shared.isActive }
        var startedGenerations: [UInt64] = []
        var currentDisplayScope: Enumerator.DisplayScope?
        func guardSecureInputActions(for shortcut: GlobalShortcut) -> Bool { true }
        func startObservingTermination(generation: UInt64) { startedGenerations.append(generation) }
        func scheduleShowPanel(afterShowing: @escaping () -> Void) { panel?.isVisible = true }
        var wantedAtPreferenceSync: Bool?
        let secureInputWatch = Watch()
        let exclusiveFullscreenWatch = Watch()
        var secureInputRegistrationFailed = false
        var secureInputEnabled = false
        struct SecureHotKey { let shortcut: GlobalShortcut }
        var secureInputHotKeys: [UInt32: SecureHotKey] = [:]
        let carbonReplay = SwitcherActivationTests.DeferredQueue()
        var replayModifiers: CGEventFlags = []
        func performCarbonBlock(_ loop: CFRunLoop, _ mode: CFString, _ body: @escaping () -> Void) { carbonReplay.async(execute: body) }
        func IsSecureEventInputEnabled() -> Bool { secureInputEnabled }
        func startObservingKeyboardLayout() {}
        func stopObservingKeyboardLayout() {}
        func startObservingWake() {}
        func stopObservingExclusiveFullscreen() {}
        func stopObservingWake() {}
        var routeSessionActive: Bool {
            get { sessionActive }
            set { sessionActive = newValue }
        }
        var routeCanStartSession = true
        var routeCapturing = false
        var yieldsToExclusiveFullscreen = false
        var routeYieldsToExclusiveFullscreen = false
        var routeQuickWindowCommit: UInt64?
        var routeHasInteractiveSession: Bool { routeSessionActive && routeQuickWindowCommit == nil }
        var routePendingStarts: [SwitcherPendingSessionStart] = []
        var routePendingSessionStart: SwitcherPendingSessionStart? { routePendingStarts.first }
        var secureInputReplays = SwitcherSecureInputReplayState()
        var tapLifecycle: [String] = []
        var onRemoveTap: (() -> Void)?
        var restoredHotkeys = 0
        var appliedHotkeys = 0
        func restoreNativeHotkeys() {
            restoredHotkeys += 1
            tapLifecycle.append("restore")
        }
        func updateSecureInputHotKeys() {}
        func applyNativeHotkeySuppression() { appliedHotkeys += 1 }
        var sessionStartGeneration: UInt64 = 0
        var routeShortcut = GlobalShortcut.switcherDefault
        var routeWindowShortcut = GlobalShortcut.switcherWindowDefault
        var routeAllWindowsShortcut: GlobalShortcut?
        var sessionShortcut: GlobalShortcut?
        var sessionScope: SwitcherSessionScope = .allApps
        var windows: [SwitcherItem] = []
        var sessionItems: [SwitcherItem] = []
        var previews: [CGWindowID: CGImage] = [:]
        var previewCaptureTask: Task<Void, Never>?
        var pendingPreviewUpdates: [CGWindowID: CGImage] = [:]
        var previewBatchWorkItem: DispatchWorkItem?
        var totalWindowCount = 0
        var sessionSourceContext: SwitcherSourceContext?
        // Main's activation snapshot and Secure Input cleanup are inert here.
        var sessionWindowServerSnapshot: SwitcherWindowServerSnapshot?
        var sessionStartWindowID: CGWindowID?
        var sessionPlacementVisibleFrame: CGRect?
        var panel: Panel? = Panel()
        func ensurePanel() -> Panel { panel! }
        var userNavigated = false
        var hoverAnchor: NSPoint?
        var hoveredWindowIndex: Int?
        var iconRowEdgeHoverWork: DispatchWorkItem?
        var iconRowEdgeHoverIndex: Int?
        var iconRowFirstVisibleIndex = 0
        var scrollNavigation = SwitcherScrollNavigation()
        var swallowingMiddleMouseUp = false
        var pendingShow: DispatchWorkItem?
        var closingItemIDs: Set<String> = []
        var quittingPIDs: Set<pid_t> = []
        var commitPendingForClose = false
        var searchQuery = ""
        var isSearchPinned = false
        var searchPinEnabled = true
        var currentSpaceOnly = false
        var usesIconRowLayout = false
        var iconRowModeEnabled: Bool { usesIconRowLayout && !simpleModeEnabled }
        var usesWindowRow = false
        var simpleModeEnabled = false
        var capturesPreviews: Bool { SwitcherSupport.capturesPreviews(simpleMode: simpleModeEnabled) }
        var grid = Grid()
        var iconRowLayout = Row()
        var shiftBackNavigationHeld = false
        var shiftBackChordDeadline: TimeInterval = 0
        func updateIconRowLayoutForCurrentSelection() {}
        func recomputeLayouts(for items: [SwitcherItem]) {}
        func resizePanel(animated: Bool = true) {}
        func cancelLetterConfirmation() {}
        func stopObservingTermination() {}
        func unregisterSecureInputActionHotKeys() {}
        var recordedIDs: [String] = []
        var useTracker: SwitcherRememberedSelectionTests.SessionOpening.WindowUseTracker?
        func recordUse(_ item: SwitcherItem, previous: CGWindowID?, focusPID: pid_t? = nil,
                       sourceRequest: WindowFocusHistory.Request? = nil) {
            recordedIDs.append(item.id)
            useTracker?.recordSwitch(to: item.windowID, pid: item.pid, from: previous, focusPID: focusPID, sourceRequest: sourceRequest)
        }
        var runProtectedLetterAction: (SwitcherLetterAction) -> Void = { _ in
            preconditionFailure("quit-protection commands are covered separately")
        }
    }

    static func run(_ suite: TestSuite) {
        checkSessionTitleSearch(suite)
        checkSessionPreviewCancellation(suite)
        checkTapRecovery(suite)
        checkPendingWindowSelection(suite)
        checkOpeningOriginAndHiddenApp(suite)
        checkFreshFrontAppWindows(suite)
        checkGlobalWindowOpening(suite)
        checkPendingEscape(suite)
        let defaults = UserDefaults.standard
        let key = DefaultsKey.switcherIgnoreHoverSelection
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
            Queue.jobs.removeAll()
            Activator.closed.removeAll()
        }
        func fresh(icons: Bool = false, windowRow: Bool = false) -> Service {
            Queue.jobs.removeAll()
            Queue.time = 0
            Activator.closed = []
            Activator.activated = []
            Enumerator.reads = 0
            Permissions.shared.accessibility = true
            let service = Service()
            service.open(icons: icons, windowRow: windowRow)
            return service
        }
        func keyEvent(_ code: Int64, flags: CGEventFlags = []) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
            event.flags = flags
            return event
        }
        func release(_ service: Service) {
            _ = service.handle(type: .flagsChanged, event: keyEvent(KeyCode.tab))
        }

        let disappeared = fresh()
        let heldIDs = disappeared.windows.map(\.id)
        disappeared.windowInventory.removedIDs.insert(disappeared.windows[1].id)
        suite.expect(disappeared.windows.map(\.id) == heldIDs && disappeared.selectedIndex == 1,
                     "a background closure preserves the displayed entries and selection while the shortcut is held")
        release(disappeared)
        suite.expect(Activator.activated == [heldIDs[2]] && Enumerator.reads == 0,
                     "modifier release skips a vanished selection using remembered state")

        for ignore in [false, true] {
            defaults.set(ignore, forKey: key)
            let service = fresh()
            service.hoverSelect(index: 2)
            suite.expect(service.selectedIndex == 1 && service.hoveredWindowIndex == 2,
                         "a stationary pointer records its close target without stealing selection")
            Pointer.mouseLocation.x += 4
            service.hoverSelect(index: 2)
            suite.expect(service.selectedIndex == 1 && service.hoverAnchor != nil,
                         "four points of movement still preserve the opening selection")
            Pointer.mouseLocation.x += 1
            service.hoverSelect(index: 2)
            suite.expect(service.selectedIndex == (ignore ? 1 : 2)
                         && service.userNavigated == !ignore && service.hoverAnchor == nil,
                         "production hover honors the preference after the movement threshold")
            service.hoverSelect(index: -1)
            service.hoverSelect(index: service.windows.count)
            service.hoverSelectEnded(index: 0)
            suite.expect(service.hoveredWindowIndex == 2,
                         "invalid entries and an older exit cannot replace the current hover target")
            let expected = service.windows[service.selectedIndex].id
            release(service)
            suite.expect(Activator.activated == [expected] && !service.sessionActive,
                         "releasing the modifier commits the retained highlight")
            service.hoverSelect(index: 0)
            suite.expect(service.hoveredWindowIndex == nil,
                         "hover after teardown cannot restore a close target")
        }

        defaults.set(true, forKey: key)
        let livePreference = fresh()
        Pointer.mouseLocation.x += 10
        livePreference.hoverSelect(index: 3)
        defaults.set(false, forKey: key)
        livePreference.hoverSelect(index: 3)
        suite.expect(livePreference.selectedIndex == 3,
                     "turning ignore-hover off restores selection in the current session")
        defaults.set(true, forKey: key)
        livePreference.hoverSelect(index: 4)
        suite.expect(livePreference.selectedIndex == 3 && livePreference.hoveredWindowIndex == 4,
                     "turning ignore-hover on preserves selection while continuing to track the pointer")
        livePreference.sessionActive = false
        livePreference.hoverSelect(index: 0)
        livePreference.select(index: 0)
        suite.expect(livePreference.selectedIndex == 3 && livePreference.hoveredWindowIndex == 4,
                     "an inactive session rejects selection even while entries are still present")
        for click in 0..<5 {
            let service = fresh()
            Pointer.mouseLocation.x += 10
            service.hoverSelect(index: 3)
            let expected = service.windows[4].id
            switch click {
            case 0: service.clickCard(index: 4)
            case 1: service.clickPreview(index: 4)
            case 2: service.clickTitle(index: 4)
            case 3: service.clickAppIcon(index: 4)
            default: service.clickWindowIcon(index: 4)
            }
            suite.expect(Activator.activated == [expected] && !service.sessionActive,
                         "production click callback \(click) opens the clicked item with hover ignored")
        }
        let keyboard = fresh()
        Pointer.mouseLocation.x += 10
        keyboard.hoverSelect(index: 4)
        _ = keyboard.handle(type: .keyDown, event: keyEvent(KeyCode.rightArrow))
        _ = keyboard.handle(type: .keyDown, event: keyEvent(keyboard.routeShortcut.keyCode,
                                                         flags: keyboard.routeShortcut.modifiers.cgFlags))
        suite.expect(keyboard.selectedIndex == 3 && keyboard.hoveredWindowIndex == 4,
                     "arrows and the session shortcut still navigate independently of the pointer")
        keyboard.pinSearch()
        release(keyboard)
        suite.expect(keyboard.sessionActive && Activator.activated.isEmpty,
                     "a pinned search does not commit on modifier release")
        let expectedKeyboard = keyboard.windows[3].id
        _ = keyboard.handle(type: .keyDown, event: keyEvent(KeyCode.enter))
        suite.expect(Activator.activated == [expectedKeyboard], "Enter still commits pinned selection")

        let routing = Service()
        var gameCoversDisplay = false
        let watch = SwitcherExclusiveFullscreenWatch(frontmostPID: { 400 },
            read: { _, complete in complete(gameCoversDisplay) },
            onObservation: routing.setYieldsToExclusiveFullscreen)
        watch.start()
        let match = (shortcut: GlobalShortcut.switcherDefault, scope: SwitcherSessionScope.allApps, reversed: false)
        let initial = routing.claimPendingKey(match: match, secureInputReplay: true)
        suite.expect(initial?.generation != nil && routing.routePendingSessionStart?.isSecureInputReplay == true,
                     "a Carbon press starts a pending replay before the game takes focus")
        if let last = routing.routePendingStarts.indices.last { routing.routePendingStarts[last].commitWhenReady = true }
        let replaced = routing.claimPendingKey(match: match, secureInputReplay: true)
        suite.expect(replaced?.generation != nil && replaced?.generation != initial?.generation
                     && routing.routePendingSessionStart?.isSecureInputReplay == true,
                     "a Carbon press replacing an already released chord retains its replay flag")
        _ = routing.secureInputReplays.enqueue(shortcut: match.shortcut)
        gameCoversDisplay = true
        watch.refresh()
        let staleMatch = routing.claimPendingKey(match: match, secureInputReplay: false)
        suite.expect(routing.restoredHotkeys == 1 && routing.routePendingSessionStart == nil
                     && !routing.secureInputReplays.hasPending && staleMatch == nil,
                     "a hand-back with a disabled tap restores the keys, discards pending work and rejects a stale shortcut match")
        suite.expect(routing.windows.isEmpty && routing.claimPendingKey(match: match, secureInputReplay: false) == nil,
                     "a second shortcut with no eligible windows still belongs to macOS")
        let queued = keyEvent(KeyCode.tab, flags: .maskCommand)
        suite.expect(routing.handle(type: .keyDown, event: queued)?.takeUnretainedValue() === queued,
                     "a key already queued on main passes unchanged after the hand-back")
        routing.tap = Tap()
        routing.tap?.enabled = true
        gameCoversDisplay = false
        watch.refresh()
        watch.stop()
        let resumed = routing.claimPendingKey(match: match, secureInputReplay: false)
        suite.expect(routing.appliedHotkeys == 1 && resumed?.generation != nil
                     && routing.routePendingSessionStart?.isSecureInputReplay == false,
                     "the live tap resumes ownership and accepts the next physical shortcut after full screen")
        let visibleSwitcher = fresh()
        visibleSwitcher.setYieldsToExclusiveFullscreen(true)
        suite.expect(!visibleSwitcher.sessionActive && visibleSwitcher.panel?.isVisible == false
                     && visibleSwitcher.restoredHotkeys == 1,
                     "a hand-back dismisses the visible switcher and releases its shortcuts")

        let middle = fresh()
        Pointer.mouseLocation.x += 10
        middle.hoverSelect(index: 3)
        let underPointer = middle.windows[3]
        let down = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                           mouseCursorPosition: Pointer.mouseLocation, mouseButton: .center)!
        let up = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                         mouseCursorPosition: Pointer.mouseLocation, mouseButton: .center)!
        suite.expect(middle.handle(type: .otherMouseDown, event: down) == nil
                     && Activator.closed.map(\.item.id) == [underPointer.id] && middle.selectedIndex == 1,
                     "middle click closes the hovered window without selecting it")
        suite.expect(middle.handle(type: .otherMouseUp, event: up) == nil,
                     "the matching middle release is swallowed")
        Activator.closed[0].completion(false)
        middle.hoverSelect(index: 2)
        middle.hoverSelectEnded(index: 2)
        suite.expect(middle.handle(type: .otherMouseDown, event: down) != nil && Activator.closed.count == 1,
                     "middle click on panel chrome cannot close the selected window")
        var card = Card(window: underPointer)
        var preview = Preview(window: underPointer)
        card.isHovering = true
        preview.isHovering = true
        suite.expect(card.showsCloseButton && preview.showsCloseButton,
                     "both production close-button predicates remain independent of selection")
        card.minimalPreviews = true
        preview.minimalPreviews = true
        suite.expect(!card.showsCloseButton && !preview.showsCloseButton,
                     "minimal previews keep their existing close-button behavior")

        for windowRow in [false, true] {
            let edge = fresh(icons: true, windowRow: windowRow)
            edge.hoverSelectIconRow(index: 2)
            suite.expect(Queue.jobs.isEmpty, "a stationary pointer cannot start edge scrolling")
            Pointer.mouseLocation.x += 10
            edge.hoverSelectIconRow(index: 2)
            Queue.advance(to: SwitcherSupport.iconRowEdgeHoverInterval - 0.001)
            suite.expect(edge.selectedIndex == 1, "ignoring hover keeps selection during the edge delay")
            Queue.advance(to: SwitcherSupport.iconRowEdgeHoverInterval)
            suite.expect(edge.selectedIndex == 3 && edge.iconRowFirstVisibleIndex == 1,
                         "the intentional edge exception reveals and selects the next icon")
            edge.hoverSelectIconRowEnded(index: 2)
            edge.hoverSelectIconRow(index: 3)
            suite.expect(edge.hoveredWindowIndex == 3,
                         "the newly revealed icon becomes the close target without resetting the edge delay")
            Queue.advance(to: 0.45)
            suite.expect(edge.selectedIndex == 4 && edge.iconRowFirstVisibleIndex == 2,
                         "the previous tile's exit does not cancel continued edge scrolling")
            edge.hoverSelectIconRowEnded(index: 3)
            edge.hoverSelectIconRow(index: 4)
            edge.hoverSelectIconRowEnded(index: 4)
            Queue.advance(to: 1)
            suite.expect(edge.selectedIndex == 4, "leaving the edge cancels its pending repeat")
            edge.hoverSelectIconRow(index: 2)
            Queue.advance(to: 1.25)
            suite.expect(edge.selectedIndex == 1 && edge.iconRowFirstVisibleIndex == 1,
                         "the left edge also reveals and selects one icon")
        }
        let cancelled = fresh(icons: true)
        Pointer.mouseLocation.x += 10
        cancelled.hoverSelectIconRow(index: 2)
        let oldWork = cancelled.iconRowEdgeHoverWork
        _ = cancelled.handle(type: .keyDown, event: keyEvent(KeyCode.escape))
        suite.expect(oldWork?.isCancelled == true && cancelled.hoveredWindowIndex == nil,
                     "Escape cancels edge work and clears the hover target")
        Queue.advance(to: 0.1)
        cancelled.open(icons: true)
        Pointer.mouseLocation.x += 10
        cancelled.hoverSelectIconRow(index: 2)
        Queue.advance(to: 0.25)
        suite.expect(cancelled.selectedIndex == 1 && cancelled.iconRowFirstVisibleIndex == 0,
                     "cancelled edge work from the old session cannot step a new session early")
        Queue.advance(to: 0.35)
        suite.expect(cancelled.selectedIndex == 3, "the new session keeps its own edge deadline")
        let navigation = fresh(icons: true)
        Pointer.mouseLocation.x += 10
        navigation.hoverSelectIconRow(index: 2)
        _ = navigation.handle(type: .keyDown, event: keyEvent(KeyCode.rightArrow))
        Queue.advance(to: 1)
        suite.expect(navigation.selectedIndex == 2 && navigation.iconRowEdgeHoverWork == nil,
                     "keyboard navigation cancels pending edge selection")
        let fits = fresh(icons: true)
        fits.iconRowLayout.visibleIconCount = fits.windows.count
        Pointer.mouseLocation.x += 10
        fits.hoverSelectIconRow(index: 5)
        suite.expect(Queue.jobs.isEmpty && fits.selectedIndex == 1,
                     "the last icon of a row without overflow is ordinary ignored hover")

        let normal = fresh()
        normal.selectedIndex = 4
        let selectedID = normal.windows[4].id
        let closing = normal.windows[1]
        normal.closeWindow(closing)
        Enumerator.listed.removeAll { $0.id == closing.id }
        Activator.closed[0].completion(true)
        Queue.advance(to: 0.2)
        suite.expect(normal.sessionActive && normal.selectedIndex == 3
                     && normal.windows[3].id == selectedID && normal.closingItemIDs.isEmpty,
                     "a normal close removes only its window and preserves the selected identity")
        normal.closeSelectedWindow()
        normal.commitSession()
        let nextID = normal.windows[4].id
        Enumerator.listed.removeAll { $0.id == selectedID }
        Activator.closed[1].completion(true)
        Queue.advance(to: 0.4)
        suite.expect(Activator.activated == [nextID] && !normal.sessionActive,
                     "closing the selection advances it and resumes a pending release in the same session")
        let retrying = fresh()
        let retryTarget = retrying.windows[2]
        retrying.closeWindow(retryTarget)
        Activator.closed[0].completion(true)
        Queue.advance(to: 0.2)
        suite.expect(retrying.closingItemIDs == [retryTarget.id] && Enumerator.reads == 1,
                     "a window still listed after close keeps its pending state for the retry")
        Enumerator.listed.removeAll { $0.id == retryTarget.id }
        Queue.advance(to: 0.6)
        suite.expect(retrying.sessionActive && retrying.windows.count == 5
                     && retrying.selectedIndex == 1 && retrying.closingItemIDs.isEmpty && Enumerator.reads == 2,
                     "a normal retry updates selection and close state within the same session")

        for result in [false, true] {
            let service = fresh()
            service.closeWindow(service.windows[2])
            service.cancelSession()
            service.open()
            let target = service.windows[2]
            service.closeWindow(target)
            service.commitSession()
            Activator.closed[0].completion(result)
            suite.expect(service.sessionActive && service.closingItemIDs == [target.id]
                         && service.commitPendingForClose && Queue.jobs.isEmpty && Activator.activated.isEmpty,
                         "an old close result \(result) cannot clear a new close or commit the new session")
            Activator.closed[1].completion(false)
            suite.expect(!service.sessionActive && Activator.activated.count == 1,
                         "the current session's failed close still resumes its pending commit")
        }
        for retry in [false, true] {
            let service = fresh()
            service.closeWindow(service.windows[2])
            Activator.closed[0].completion(true)
            if retry { Queue.advance(to: 0.2) }
            let reads = Enumerator.reads
            service.cancelSession()
            service.open()
            let target = service.windows[2]
            service.closeWindow(target)
            service.commitSession()
            Enumerator.listed = []
            Queue.advance(to: 1)
            suite.expect(Enumerator.reads == reads && service.sessionActive
                         && service.closingItemIDs == [target.id] && service.commitPendingForClose
                         && service.windows.count == 6 && Activator.activated.isEmpty,
                         "an old \(retry ? "retry" : "initial refresh") cannot inspect or mutate the next session")
        }
    }

    private static func checkSessionTitleSearch(_ suite: TestSuite) {
        func document(_ id: CGWindowID, _ title: String, pid: pid_t = 10, owner: pid_t = 11,
                      frame: CGRect = .zero) -> SwitcherItem {
            .window(id: id, title: title, appName: "Editor", pid: pid, windowOwnerPID: owner,
                    isOnScreen: true, frame: frame)
        }
        let service = Service()
        let cover = document(1, "Cover"), report = document(2, "Report"), notes = document(3, "Notes")
        let closed = document(4, "Appendix"), app = SwitcherItem.appOnly(appName: "Finder", pid: 20)
        service.sessionActive = true
        service.sessionItems = [cover, report, notes, closed, app]
        service.windows = service.sessionItems
        service.applyClosedWindowRemoval(itemID: closed.id, windowID: 4)
        service.appendSearchText("Budget")
        suite.expect(service.windows.isEmpty, "the typed query initially has no matching document")
        let budget = document(2, "Budget")
        service.updateSessionTitles(from: [document(2, "Budget", frame: CGRect(x: 10, y: 20, width: 30, height: 40))])
        suite.expect(service.windows == [budget], "a recovered title appears in the existing search without changing its frame")

        let budgetCover = document(1, "Budget cover")
        service.hoveredWindowIndex = 0
        service.iconRowEdgeHoverIndex = 0
        service.updateSessionTitles(from: [closed, budget, document(3, "Budget notes", owner: 99), budgetCover])
        suite.expect(service.sessionItems == [budgetCover, budget, notes, app] && service.windows == [budgetCover, budget]
                     && service.selectedItemID == budget.id,
                     "recovering titles preserves order, selection and app entries, skips a new owner and keeps closed windows out")
        suite.expect(service.hoveredWindowIndex == nil && service.iconRowEdgeHoverIndex == nil,
                     "a search result inserted under the pointer cannot inherit the previous document's hover actions")
        service.updateSessionTitles(from: [document(3, "Budget notes", pid: 99), cover, report])
        suite.expect(service.searchQuery == "Budget" && service.windows.isEmpty,
                     "the old query loses its matches and a different host cannot rename a session entry")
        service.sessionActive = false
        service.updateSessionTitles(from: [budget])
        suite.expect(service.sessionItems == [cover, report, notes, app] && service.windows.isEmpty,
                     "an inactive session ignores a late title update")
    }

    private static func checkSessionPreviewCancellation(_ suite: TestSuite) {
        typealias Fake = WindowServerCaptureContract.Fake
        func wait(until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while !condition() {
                guard Date() < deadline else { return false }
                _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return true
        }
        func requestsFinished(_ requests: Task<Void, Never>?...) -> Bool {
            let finished = Fake.Flag()
            Task.detached {
                for case let task? in requests { await task.value }
                finished.set()
            }
            return wait { finished.isSet && Fake.lock.withLock { Fake.inFlight == 0 } }
        }

        // Whichever request reaches the native call first holds the queue.
        // Both clients use the shared provider and its real refresh loop.
        let provider = WindowPreviewProvider.shared
        for dockFirst in [false, true] {
            Fake.reset(holding: [dockFirst ? 3 : 1])
            let service = Service()
            service.syncWithPreferences()
            service.open()
            let windows = service.windows
            let generation = service.sessionStartGeneration
            var dockUpdates: [CGWindowID] = []
            var dockTask: Task<Void, Never>?
            func startDock() {
                dockTask = provider.refreshPreviews(for: Array(windows[2...3]), maxPixelSize: 420,
                                                    excludedAppsKey: DefaultsKey.windowPreviewExcludedApps) { id, _ in
                    dockUpdates.append(id)
                }
            }
            func startSwitcher() {
                service.refreshSessionPreviews(for: Array(windows.prefix(2)), generation: generation)
            }

            if dockFirst { startDock() } else { startSwitcher() }
            suite.expect(wait { Fake.entered.wait(timeout: .now()) == .success },
                         "the first preview request reaches the held native call")
            let clockReads = Fake.lock.withLock { Fake.clockReads }
            if dockFirst { startSwitcher() } else { startDock() }
            suite.expect(wait { Fake.lock.withLock { Fake.clockReads > clockReads } },
                         "the second client's first capture is submitted behind the held call")

            let oldTask = service.previewCaptureTask
            suite.expect(oldTask?.isCancelled == false && dockTask?.isCancelled == false,
                         "the Switcher and Dock start independent refreshes on the shared provider")
            if dockFirst {
                service.switcherEnabled = false
                service.syncWithPreferences()
            } else {
                service.cancelSession() // Closing while the first native capture is still in flight.
            }
            suite.expect(!service.sessionActive && oldTask?.isCancelled == true && dockTask?.isCancelled == false,
                         "teardown cancels only the outgoing Switcher session")
            suite.expect(provider.warming == !dockFirst,
                         "closing the panel leaves warming enabled and disabling the feature stops it")

            if !dockFirst {
                service.open()
                startSwitcher() // A delayed show callback from the old generation.
                suite.expect(service.previewCaptureTask == nil, "the retired session cannot restart its refresh")
                service.refreshSessionPreviews(for: Array(windows.suffix(2)), generation: service.sessionStartGeneration)
            }
            Fake.release.signal()
            suite.expect(requestsFinished(oldTask, dockTask, service.previewCaptureTask),
                         "all preview requests finish after releasing the native call")
            Queue.advance(to: Queue.time + 1)

            let expectedCalls: [CGWindowID] = dockFirst ? [3, 4] : [1, 3, 4, 5, 6]
            suite.expect(Fake.lock.withLock { Fake.calls.sorted() == expectedCalls && Fake.maximumInFlight == 1 },
                         "cancelled windows never reach capture after teardown and surviving requests stay serialized")
            suite.expect(provider.cachedPreview(for: 1) == nil && provider.cachedPreview(for: 2) == nil,
                         "a queued or late first capture cannot populate the cache for a cancelled session")
            suite.expect(dockUpdates == [3, 4] && dockUpdates.allSatisfy { provider.cachedPreview(for: $0) != nil },
                         "the independent Dock request still delivers and caches both thumbnails")
            let expectedPreviews: Set<CGWindowID> = dockFirst ? [] : [5, 6]
            suite.expect(Set(service.previews.keys) == expectedPreviews,
                         "only the reopened Switcher session can publish thumbnails")
            service.cancelSession()
        }

        // Switching to icon-only mode can leave the panel open with a captured
        // image awaiting publication and the next native call in progress.
        Fake.reset(holding: [2])
        let service = Service()
        service.syncWithPreferences()
        service.open()
        service.refreshSessionPreviews(for: service.windows, generation: service.sessionStartGeneration)
        suite.expect(wait { Fake.entered.wait(timeout: .now()) == .success }
                     && service.pendingPreviewUpdates[1] != nil && provider.warming,
                     "the second capture starts with the first waiting to be published")
        let task = service.previewCaptureTask
        service.simpleModeEnabled = true
        service.syncWithPreferences()
        Fake.release.signal()
        suite.expect(requestsFinished(task), "the icon-only session releases its outstanding capture request")
        Queue.advance(to: Queue.time + 1)
        suite.expect(service.sessionActive && !provider.warming && service.previews.isEmpty
                     && service.pendingPreviewUpdates.isEmpty && Fake.lock.withLock { Fake.calls == [1, 2] }
                     && provider.cachedPreview(for: 1) != nil && provider.cachedPreview(for: 2) == nil,
                     "icon-only mode stops the batch and warming, preserving the previously cached thumbnail")
        service.cancelSession()
    }

    private static func press(_ service: Service, shortcut: GlobalShortcut = .switcherDefault) -> UInt64 {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true)!
        event.flags = shortcut.modifiers.cgFlags
        _ = service.route(type: .keyDown, event: event)
        Queue.advance(to: Queue.time)
        return service.sessionStartGeneration
    }

    private static func checkPendingWindowSelection(_ suite: TestSuite) {
        let earlierItems = FrontAppEnumerator.items, earlierReads = FrontAppEnumerator.reads
        defer { FrontAppEnumerator.items = earlierItems; FrontAppEnumerator.reads = earlierReads }
        func waitingService() -> Service {
            let service = Service()
            service.tap = Tap()
            service.windowInventory.items = nil
            service.panel?.isVisible = false
            return service
        }
        let release = CGEvent(source: nil)!
        release.type = .flagsChanged
        release.flags = []
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: .zero, mouseButton: .left)!
        let window = Inventory.sampleWindows[0]
        let previousActivations = Activator.activated
        defer { Activator.activated = previousActivations }

        let flick = waitingService()
        let first = press(flick, shortcut: .switcherWindowDefault)
        suite.expect(flick.routePendingSessionStart?.generation == first && flick.startedGenerations.isEmpty
                     && !flick.sessionActive && flick.keyboardInputOwnership.isOwned,
                     "the current-app shortcut stays pending until its private window read answers")
        _ = flick.route(type: .flagsChanged, event: release)
        FrontAppEnumerator.items = [window]
        flick.windowInventory.publish([window])
        suite.expect(flick.startedGenerations.isEmpty && flick.frontAppReadQueue.pending.count == 1,
                     "an inventory publication cannot consume or duplicate a private read")
        flick.frontAppReadQueue.drain()
        Queue.advance(to: Queue.time)
        suite.expect(flick.startedGenerations == [first] && Activator.activated == previousActivations + [window.id]
                     && !flick.keyboardInputOwnership.isOwned && flick.panel?.isVisible == false,
                     "the original modifier release commits the freshly read window exactly once")

        for fullscreen in [false, true] {
            let service = waitingService()
            _ = press(service)
            if fullscreen { service.setYieldsToExclusiveFullscreen(true) }
            else { _ = service.route(type: .leftMouseDown, event: click) }
            service.windowInventory.publish([window])
            Queue.advance(to: Queue.time)
            suite.expect(service.startedGenerations.isEmpty && !service.keyboardInputOwnership.isOwned
                         && !service.sessionActive && service.panel?.isVisible == false,
                         "a window arriving after a cancelling click or full-screen hand-back cannot revive the shortcut")
        }

        let replaced = waitingService()
        let retired = press(replaced)
        _ = replaced.route(type: .flagsChanged, event: release)
        let current = press(replaced, shortcut: .switcherWindowDefault)
        replaced.windowInventory.items = [window]
        replaced.beginPendingSession(generation: retired)
        suite.expect(current != retired && replaced.routePendingSessionStart?.generation == current
                     && replaced.startedGenerations.isEmpty,
                     "a late opening for the released chord leaves the newer shortcut pending")
        replaced.windowInventory.publish([window])
        replaced.frontAppReadQueue.drain()
        Queue.advance(to: Queue.time)
        suite.expect(replaced.startedGenerations == [current] && replaced.sessionScope == .frontmostApp
                     && replaced.windows.map(\.id) == [window.id] && replaced.sessionActive,
                     "the private read opens only the replacement shortcut and preserves its scope")

        let empty = waitingService()
        _ = press(empty)
        empty.windowInventory.publish([])
        suite.expect(!empty.keyboardInputOwnership.isOwned && empty.startedGenerations.isEmpty,
                     "a confirmed empty list releases the shortcut without presenting a session")
        empty.windowInventory.items = [window]
        let warm = press(empty)
        suite.expect(empty.startedGenerations == [warm] && empty.sessionActive,
                     "a new shortcut with a remembered window opens without another inventory notification")
    }

    private static func checkOpeningOriginAndHiddenApp(_ suite: TestSuite) {
        typealias Desktop = SwitcherRememberedSelectionTests.SessionOpening
        typealias Windows = Desktop.WindowEnumerator
        typealias Work = Desktop.DispatchQueue
        let defaults = SwitcherRememberedSelectionTests.Preferences.standard
        let previousDefaults = defaults.values
        let previousHint = Desktop.WindowUseTracker.confirmedFocus
        let previousApp = Workspace.shared.frontmostApplication
        let previousActivations = Activator.activated
        let previousHandoff = Activator.lastHandoffSourcePID
        let service = Service()
        let inventory = Desktop.SwitcherWindowInventory()
        service.tap = Tap()
        service.windowInventory.observed = inventory
        inventory.onReady = service.windowInventory.onReady
        defer {
            inventory.stop()
            Windows.items = []
            Windows.reads = []
            Work.discoveries.reset()
            Work.scans.reset()
            Work.main.deliveries.reset()
            Work.main.debounce.reset()
            defaults.values = previousDefaults
            Desktop.WindowUseTracker.confirmedFocus = previousHint
            Workspace.shared.frontmostApplication = previousApp
            Activator.activated = previousActivations
            Activator.lastHandoffSourcePID = previousHandoff
        }
        let displays = [CGRect(x: 0, y: 0, width: 900, height: 700),
                        CGRect(x: 900, y: 0, width: 900, height: 700)]
        let editor = Workspace.App(processIdentifier: 10, bundleIdentifier: "test.editor")
        let browser = Workspace.App(processIdentifier: 11, bundleIdentifier: "test.browser")
        func window(_ id: CGWindowID, _ app: Workspace.App, on index: Int) -> SwitcherItem {
            .window(id: id, title: "Window \(id)", appName: "App \(app.processIdentifier)", pid: app.processIdentifier,
                    isOnScreen: true, frame: displays[index].insetBy(dx: 40, dy: 40))
        }
        defaults.values = [DefaultsKey.switcherWindowlessApps: "off"]
        Windows.items = []
        inventory.start()
        Work.scans.drain()
        Work.main.deliveries.drain()
        Workspace.shared.frontmostApplication = editor
        service.currentDisplayScope = .init(bounds: displays, targetIndex: 0)
        let first = press(service, shortcut: .switcherWindowDefault)
        suite.expect(service.routePendingSessionStart?.generation == first && !service.sessionActive,
                     "the current-app shortcut waits for discovery on its original display")
        Workspace.shared.frontmostApplication = browser
        service.currentDisplayScope = .init(bounds: displays, targetIndex: 1)
        let target = window(21, editor, on: 0)
        Windows.items = [target, window(22, editor, on: 1), window(23, browser, on: 0), window(24, browser, on: 1)]
        Desktop.WindowUseTracker.confirmedFocus = target.windowID
        service.frontAppReadQueue.drain()
        Desktop.WindowUseTracker.confirmedFocus = nil
        Queue.advance(to: Queue.time)
        suite.expect(service.sessionActive && service.windows.map(\.id) == [target.id],
                     "a focus and pointer move during discovery preserves the original app and display for selection")
        let release = CGEvent(source: nil)!
        release.type = .flagsChanged
        release.flags = []
        _ = service.route(type: .flagsChanged, event: release)
        suite.expect(service.frontAppReadQueue.pending.isEmpty && !service.keyboardInputOwnership.isOwned
                     && Activator.activated == previousActivations + [target.id] && Activator.lastHandoffSourcePID == editor.processIdentifier,
                     "modifier release activates the original display's editor window and keeps the editor as the handoff source")

        defaults.values[DefaultsKey.switcherAppRules] = ["test.private": SwitcherAppRule.hidden.rawValue]
        Workspace.shared.frontmostApplication = .init(processIdentifier: 12, bundleIdentifier: "test.private")
        _ = press(service, shortcut: .switcherWindowDefault)
        suite.expect(!service.keyboardInputOwnership.isOwned && service.startedGenerations == [first]
                     && service.frontAppReadQueue.pending.isEmpty && Work.main.debounce.pending.isEmpty,
                     "Never show releases keyboard ownership before modifier-up without starting a refresh")
        _ = service.route(type: .flagsChanged, event: release)
        let letter = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        letter.flags = []
        let routed = service.route(type: .keyDown, event: letter)?.takeUnretainedValue()
        suite.expect(routed === letter && Activator.activated == previousActivations + [target.id],
                     "the excluded app receives the first typed letter and the switcher activates no window")
        inventory.invalidate()
        Work.main.debounce.drain()
        Work.scans.drain()
        Work.main.deliveries.drain()
        _ = press(service)
        suite.expect(service.sessionActive && service.sessionScope == .allApps && service.windows.contains { $0.pid == browser.processIdentifier },
                     "the main shortcut can still switch away from an excluded app")
        service.cancelSession()
    }

    private static func checkFreshFrontAppWindows(_ suite: TestSuite) {
        typealias Desktop = SwitcherRememberedSelectionTests.SessionOpening
        typealias Work = Desktop.DispatchQueue
        enum Case: CaseIterable {
            case front, background, noNotice, retry, omittedFocus, conflictingFocus, escape, timeout, newerFocus
            case focusWithoutRaise, changingFocusBehindFront
            case unlistedFront, foreignFront, overlayFront, rejectedPanel, focusedInspector, observedInspector, inspectorAfterMove
            case repeatWithInspector, staleInspectorHint, inspectorAfterDocument
            case observedPrevious, onlyPreviousObserved, unknownPrevious
            case repeatedFocus, changedPrevious, confirmedSource, destroyedTarget
            case repeatedPress, repeatWithoutAX, repeatSplitSignals, repeatWithConfirmation, cancelledFirstPress, newFocusBeforeRepeat
            case reconciledFocus, reconciledPrevious, openingClick, restoredPrevious, recoveredPrevious, missingPrevious, prunedSource
            case heldRepeat, helperRepeat, closedSource, closedTarget
            case destroyedBeforeFocus, destroyedAfterFocus, unrelatedDestruction
            case helperExitedBeforeKey, destroyedDuringFirstAX, liveFirstAX, omittedDuringFirstAX
            case helperExitedAfterCapture, helperExitedBeforeDelivery, otherOwnerExited
            case selectedHelperExited, replacedHelperCapture, uncertainHostSource, returningHelperWindow
            case missingInspectorPrevious, missingStackPrevious
            case heldKnown, heldLive, heldEscape, heldTyping, heldDestroyed, heldOwnerExited, carbonLive, carbonKnown
            case carbonReleasedDuringRead, carbonReleasedBeforeReplay, carbonReleasedBeforeDelivery
            case lateSpaceNotice, changedSpace, differentCapturedSpace
            case heldChangedSpace, heldLateSpaceNotice, heldSecureInput, heldSecureInputChanged

            var held: Bool {
                [.heldKnown, .heldLive, .heldEscape, .heldTyping, .heldDestroyed, .heldOwnerExited, .carbonLive, .carbonKnown,
                 .heldChangedSpace, .heldLateSpaceNotice, .heldSecureInput, .heldSecureInputChanged].contains(self)
            }
            var inspectorHasFocus: Bool {
                [.focusedInspector, .observedInspector, .inspectorAfterMove, .repeatWithInspector,
                 .staleInspectorHint, .missingInspectorPrevious].contains(self)
            }
            var omitsFront: Bool { [.unlistedFront, .foreignFront, .overlayFront, .rejectedPanel, .inspectorAfterDocument].contains(self) || inspectorHasFocus }
            var rawHelperOwner: Bool { [.helperExitedAfterCapture, .helperExitedBeforeDelivery, .otherOwnerExited].contains(self) }
            var destroyedBeforeKey: Bool { [.destroyedBeforeFocus, .destroyedAfterFocus, .unrelatedDestruction, .helperExitedBeforeKey].contains(self) || rawHelperOwner }
            var firstAXRead: Bool { [.destroyedDuringFirstAX, .liveFirstAX, .omittedDuringFirstAX].contains(self) }
            var missingHelper: Bool { [.selectedHelperExited, .replacedHelperCapture, .uncertainHostSource, .returningHelperWindow].contains(self) }
            var retriesPrevious: Bool {
                missingHelper || [.missingPrevious, .otherOwnerExited, .unrelatedDestruction, .recoveredPrevious,
                                  .missingInspectorPrevious, .missingStackPrevious].contains(self)
            }
            var carbonReleased: Bool { [.carbonReleasedDuringRead, .carbonReleasedBeforeReplay, .carbonReleasedBeforeDelivery].contains(self) }
            var repeats: Bool {
                [.repeatedPress, .repeatWithoutAX, .repeatSplitSignals, .repeatWithConfirmation,
                 .cancelledFirstPress, .newFocusBeforeRepeat, .heldRepeat, .helperRepeat,
                 .destroyedBeforeFocus, .destroyedAfterFocus, .repeatWithInspector, .helperExitedBeforeKey,
                 .helperExitedAfterCapture, .helperExitedBeforeDelivery, .selectedHelperExited, .replacedHelperCapture].contains(self) || firstAXRead
            }
        }

        _ = NSApplication.shared
        let frame = CGRect(x: 40, y: 40, width: 400, height: 300)
        let natives = ["A", "B", "C", "D"].map { title in
            let window = NSWindow(contentRect: frame.offsetBy(dx: -10_000, dy: -10_000), styleMask: .titled,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = title
            return window
        }
        defer { natives.forEach { $0.close() } }
        let ids = natives.compactMap { CGWindowID(exactly: $0.windowNumber) }.filter { $0 != 0 }
        guard Set(ids).count == natives.count else { suite.expect(false, "the fixture windows have distinct WindowServer IDs"); return }
        let pid: pid_t = 10
        let items = zip(natives, ids).map { window, id in
            SwitcherItem.window(id: id, title: window.title, appName: "Editor", pid: pid, isOnScreen: true, frame: frame)
        }
        let (a, b, c, d) = (items[0], items[1], items[2], items[3])
        let tracker = SwitcherRememberedSelectionTests.Tracker.shared
        let previousHistory = tracker.history, previousActivations = Activator.activated
        let previousSource = Activator.lastSourceWindowID, previousFocus = Desktop.WindowActivator.focusedWindow
        let previousFocusHistory = Desktop.WindowUseTracker.history.focusHistory
        let previousApp = Workspace.shared.frontmostApplication, previousSpaces = Desktop.SpaceWindowBridge.visibleSpaces
        defer {
            tracker.history = previousHistory
            Activator.activated = previousActivations
            Activator.lastSourceWindowID = previousSource
            Desktop.WindowActivator.focusedWindow = previousFocus
            Desktop.WindowUseTracker.history.focusHistory = previousFocusHistory
            Workspace.shared.frontmostApplication = previousApp
            Desktop.SpaceWindowBridge.visibleSpaces = previousSpaces
        }
        Workspace.shared.frontmostApplication = .init(processIdentifier: pid)
        for scenario in Case.allCases {
            let service = Service(), inventory = Desktop.SwitcherWindowInventory()
            service.tap = Tap()
            service.currentSpaceOnly = [.lateSpaceNotice, .changedSpace, .differentCapturedSpace, .heldChangedSpace, .heldLateSpaceNotice].contains(scenario)
            if scenario.repeats { service.useTracker = .shared }
            service.routeAllWindowsShortcut = .switcherAllWindowsDefault
            service.windowInventory.observed = inventory
            inventory.onReady = service.windowInventory.onReady
            defer {
                inventory.stop()
                FrontAppEnumerator.items = []
                FrontAppEnumerator.firstFrontAppItems = nil
                FrontAppEnumerator.focusByRead = []
                FrontAppEnumerator.stackRows = nil
                FrontAppEnumerator.capturedRows = nil
                FrontAppEnumerator.inventoryCaptureSequence = []
                FrontAppEnumerator.rejectedIDs = []
                FrontAppEnumerator.apps = []
                Desktop.WindowUseTracker.seedPID = nil
                Desktop.WindowActivator.responderPID = nil
                Desktop.WindowActivator.focusReads = []
                Permissions.shared.accessibility = true
                Workspace.shared.frontmostApplication = .init(processIdentifier: pid)
                FrontAppEnumerator.reads = []
                Work.scans.reset()
                Work.discoveries.reset()
                Work.main.debounce.reset()
                Work.main.deliveries.reset()
            }
            Desktop.SpaceWindowBridge.visibleSpaces = [1]
            let renderer = pid + 20
            if scenario == .helperRepeat {
                Workspace.shared.frontmostApplication = .init(processIdentifier: renderer, activationPolicy: .accessory)
                Desktop.WindowUseTracker.seedPID = renderer
                Desktop.WindowActivator.responderPID = renderer
                let path = "/Applications/Editor.app"
                FrontAppEnumerator.apps = [
                    .init(pid: pid, bundleIdentifier: "test.editor", localizedName: "Editor", isRegular: true,
                          isHidden: false, bundlePath: path, executablePath: nil),
                    .init(pid: renderer, bundleIdentifier: "test.renderer", localizedName: "Renderer", isRegular: false,
                          isHidden: false, bundlePath: path + "/Contents/Helpers/Renderer.app", executablePath: nil)]
            }
            let newPrevious = [.observedPrevious, .onlyPreviousObserved, .unknownPrevious].contains(scenario)
            tracker.history = newPrevious ? [ids[0]] : [ids[1], ids[0]]
            Desktop.WindowUseTracker.confirmedFocus = nil
            if scenario != .noNotice && scenario != .unknownPrevious {
                Desktop.WindowUseTracker.confirmedFocus = ids[0]
                if scenario == .observedPrevious {
                    Desktop.WindowUseTracker.confirmedFocus = ids[2]
                    tracker.history.insert(ids[2], at: 0)
                } else if !newPrevious {
                    Desktop.WindowUseTracker.confirmedFocus = ids[1]
                }
            }
            let sourceIsB = scenario == .background || scenario.omitsFront || scenario.held || scenario.destroyedBeforeKey
                || scenario == .destroyedDuringFirstAX || scenario.missingHelper || scenario == .missingStackPrevious
            let source = sourceIsB ? ids[1] : ids[2]
            FrontAppEnumerator.items = newPrevious ? [a] : [b, a]
            if scenario == .missingStackPrevious {
                Desktop.WindowUseTracker.confirmedFocus = nil
                FrontAppEnumerator.items = [c, a]
            }
            if scenario == .helperExitedBeforeKey {
                FrontAppEnumerator.items.append(.window(id: ids[2], title: c.title, appName: c.appName, pid: pid,
                                                         windowOwnerPID: renderer, isOnScreen: true, frame: frame))
            }
            if scenario.rawHelperOwner {
                FrontAppEnumerator.capturedRows = [FrontAppEnumerator.stackRow(c, owner: renderer),
                                                   FrontAppEnumerator.stackRow(b), FrontAppEnumerator.stackRow(a)]
                if scenario == .helperExitedAfterCapture {
                    // D has no owner, so this capture cannot serve as a complete activation baseline.
                    FrontAppEnumerator.capturedRows?.append([kCGWindowNumber as String: NSNumber(value: ids[3])])
                }
            }
            if scenario == .unrelatedDestruction {
                FrontAppEnumerator.items.append(.window(id: ids[3], title: "Other window", appName: "Browser", pid: pid + 1,
                                                         isOnScreen: true, frame: frame))
            }
            if scenario == .changingFocusBehindFront { FrontAppEnumerator.items = [a, b, c] }
            inventory.start()
            Work.scans.drain()
            if scenario == .helperExitedBeforeDelivery {
                suite.expect(!inventory.isReady && Work.main.deliveries.pending.count == 1,
                             "the inventory has captured the helper's CG row and queued its first delivery")
            } else {
                Work.main.deliveries.drain()
            }
            if scenario.rawHelperOwner { FrontAppEnumerator.capturedRows = nil }
            FrontAppEnumerator.reads = []
            FrontAppEnumerator.items = sourceIsB ? [b, c, a] : [c, b, a]
            Desktop.WindowActivator.focusedWindow = scenario == .noNotice ? nil : source
            if scenario == .retry {
                FrontAppEnumerator.firstFrontAppItems = [b, a]
                FrontAppEnumerator.focusByRead = [ids[1], ids[2]]
                FrontAppEnumerator.capturedRows = [c, b, a].map { FrontAppEnumerator.stackRow($0) }
            }
            if scenario == .omittedFocus { FrontAppEnumerator.items = [b, a] }
            if scenario == .conflictingFocus { Desktop.WindowActivator.focusedWindow = ids[0] }
            if scenario == .focusWithoutRaise || scenario == .changingFocusBehindFront {
                FrontAppEnumerator.items = scenario == .focusWithoutRaise ? [a, b] : [a, b, c]
                Desktop.WindowActivator.focusedWindow = ids[1]
                if scenario == .changingFocusBehindFront {
                    Desktop.WindowUseTracker.confirmedFocus = nil
                    FrontAppEnumerator.focusByRead = [ids[2], ids[1]]
                }
            }
            func reconcileHostWindows(_ remaining: [CGWindowID]) {
                let history = Desktop.WindowUseTracker.history
                history.windowHistory = tracker.history
                history.reconcile(existingWindows: Set(remaining), frontToBack: .init(windows: remaining, apps: [pid]),
                                  running: [pid], revision: history.focusHistory.revision)
                tracker.history = history.windows
            }
            if scenario == .missingStackPrevious {
                FrontAppEnumerator.items = [b, d, a]
                FrontAppEnumerator.stackRows = [b, c, d, a].map { FrontAppEnumerator.stackRow($0) }
            }
            if scenario.omitsFront {
                // An independently sampled CG surface leads the eligible editor windows.
                FrontAppEnumerator.items = [b, a]
                let top = FrontAppEnumerator.stackRow(c, owner: scenario == .foreignFront ? pid + 1 : pid,
                                                      layer: scenario == .overlayFront ? 1 : 0)
                FrontAppEnumerator.stackRows = [top, FrontAppEnumerator.stackRow(b), FrontAppEnumerator.stackRow(a)]
                if scenario == .rejectedPanel || scenario.inspectorHasFocus || scenario == .inspectorAfterDocument {
                    FrontAppEnumerator.capturedRows = FrontAppEnumerator.stackRows
                    FrontAppEnumerator.rejectedIDs = [ids[2]]
                }
                if scenario.inspectorHasFocus { Desktop.WindowActivator.focusedWindow = ids[2] }
                if scenario == .missingInspectorPrevious {
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[3], pid: pid)
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid)
                    reconcileHostWindows([ids[1], ids[0]])
                }
                if scenario == .observedInspector { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid) }
                if scenario == .staleInspectorHint || scenario == .inspectorAfterDocument {
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[0], pid: pid)
                }
            }
            if scenario.destroyedBeforeKey {
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid)
                reconcileHostWindows([ids[1], ids[0]])
                FrontAppEnumerator.items = [b, a]
                if scenario == .destroyedBeforeFocus { Desktop.Events.shared.deliver?(.destroyed(ids[2])) }
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid)
                if scenario == .destroyedAfterFocus { Desktop.Events.shared.deliver?(.destroyed(ids[2])) }
                if scenario == .unrelatedDestruction { Desktop.Events.shared.deliver?(.destroyed(ids[3])) }
                if scenario == .helperExitedBeforeKey || scenario.rawHelperOwner {
                    suite.expect(inventory.knownWindowIDs.contains(ids[2]) == (scenario == .helperExitedBeforeKey)
                                 && Workspace.shared.frontmostApplication?.processIdentifier == pid,
                                 "\(scenario) keeps keyboard focus in the host with the expected inventory candidates")
                    inventory.remove(pid: scenario == .otherOwnerExited ? renderer + 1 : renderer)
                    if scenario == .helperExitedBeforeDelivery { Work.main.deliveries.drain() }
                    suite.expect(inventory.knownWindowIDs == Set([ids[1], ids[0]]), "both host windows survive the process exit")
                }
            }
            if scenario.firstAXRead {
                let history = Desktop.WindowUseTracker.history
                guard let request = history.focusHistory.current else { suite.expect(false, "the editor is observing focus"); continue }
                let previousRead = history.readAXFocus
                defer { history.readAXFocus = previousRead }
                if scenario == .liveFirstAX {
                    history.readAXFocus = { _ in nil }
                    suite.expect(!history.readFocusedWindow(for: request), "an unanswered AX read leaves the next read available")
                }
                var firstWindow: CGWindowID?
                Desktop.WindowActivator.focusedWindow = ids[2]
                history.readAXFocus = { keyboardPID in
                    guard let reply = Desktop.WindowActivator.focusedWindowID(for: keyboardPID) else { return nil }
                    firstWindow = reply
                    if scenario == .destroyedDuringFirstAX { Desktop.Events.shared.deliver?(.destroyed(reply)) }
                    if scenario == .liveFirstAX { Desktop.Events.shared.deliver?(.destroyed(ids[3])) }
                    if scenario == .omittedDuringFirstAX { reconcileHostWindows([ids[1], ids[0]]) }
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid)
                    return reply
                }
                history.windowHistory = tracker.history
                let accepted = history.readFocusedWindow(for: request)
                tracker.history = history.windows
                suite.expect(firstWindow == ids[2] && accepted == (scenario != .destroyedDuringFirstAX),
                             "\(scenario) accepts a first AX report only while its window survives")
                reconcileHostWindows([ids[1], ids[0]])
                Desktop.WindowActivator.focusedWindow = source
                FrontAppEnumerator.items = sourceIsB ? [b, a] : [c, b, a]
            }
            if [.restoredPrevious, .recoveredPrevious, .missingPrevious, .prunedSource].contains(scenario) {
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[3], pid: pid)
                let history = Desktop.WindowUseTracker.history
                let remaining = Array(ids.prefix(3))
                history.reconcile(existingWindows: Set(remaining), frontToBack: .init(windows: remaining, apps: [pid]),
                                  running: [pid], revision: history.focusHistory.revision)
                tracker.history = history.windowHistory
                if scenario != .prunedSource {
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid)
                    if scenario != .missingPrevious { FrontAppEnumerator.items = [c, b, d, a] }
                    else {
                        // B is ahead of A in the ordinary use order, even when A is stacked higher.
                        FrontAppEnumerator.stackRows = [c, a, b].map { FrontAppEnumerator.stackRow($0) }
                    }
                    if scenario == .recoveredPrevious { FrontAppEnumerator.firstFrontAppItems = [c, b, a] }
                }
            }
            if scenario == .helperRepeat {
                FrontAppEnumerator.items = [c, b, a].map { item in
                    .window(id: item.windowID!, title: item.title, appName: item.appName, pid: pid,
                            windowOwnerPID: renderer, isOnScreen: true, frame: frame)
                }
                Desktop.WindowActivator.focusReads = []
            }
            if scenario.held || scenario == .selectedHelperExited {
                let privateWindow = SwitcherItem.window(id: ids[2], title: "AX-only C", appName: "Editor", pid: pid,
                                                        windowOwnerPID: renderer, isOnScreen: false, isMinimized: true, frame: frame)
                FrontAppEnumerator.items = [b, a, privateWindow]
                FrontAppEnumerator.stackRows = [FrontAppEnumerator.stackRow(b), FrontAppEnumerator.stackRow(a)]
                FrontAppEnumerator.capturedRows = FrontAppEnumerator.stackRows
            }
            if service.currentSpaceOnly { Desktop.SpaceWindowBridge.visibleSpaces = [2] }
            if scenario != .noNotice && !scenario.destroyedBeforeKey && !scenario.firstAXRead && !scenario.missingHelper {
                Desktop.Events.shared.deliver?(.changed(ids[2]))
            }
            let shortcut = GlobalShortcut.switcherWindowDefault
            let release = CGEvent(source: nil)!
            release.type = .flagsChanged
            release.flags = []
            if scenario.missingHelper {
                if scenario == .selectedHelperExited {
                    _ = press(service, shortcut: shortcut)
                    service.frontAppReadQueue.drain()
                    Queue.advance(to: Queue.time)
                    guard let index = service.windows.firstIndex(where: { $0.windowID == ids[2] && $0.windowOwnerPID == renderer }) else {
                        suite.expect(false, "the private panel lists the renderer's AX-only window")
                        continue
                    }
                    service.select(index: index)
                    let activations = Activator.activated
                    _ = service.route(type: .flagsChanged, event: release)
                    suite.expect(service.recordedIDs == [c.id] && Activator.activated == activations + [c.id]
                                 && Activator.lastSourceWindowID == ids[1] && !inventory.knownWindowIDs.contains(ids[2]),
                                 "the panel activates C from B before the shared inventory learns about C")
                } else {
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid)
                }
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid)
                FrontAppEnumerator.items = [b, a]
                FrontAppEnumerator.stackRows = nil
                FrontAppEnumerator.capturedRows = nil
                if scenario == .replacedHelperCapture {
                    let rows = [b, a].map { FrontAppEnumerator.stackRow($0) }
                    FrontAppEnumerator.inventoryCaptureSequence = [
                        { [FrontAppEnumerator.stackRow(c, owner: renderer)] + rows },
                        {
                            inventory.remove(pid: renderer)
                            return rows
                        }
                    ]
                    let otherPID = pid + 1
                    inventory.invalidate(pid: pid)
                    inventory.invalidate(pid: otherPID)
                    Work.main.debounce.drain()
                    Work.scans.drain()
                    Work.main.deliveries.drain()
                    suite.expect(Set(FrontAppEnumerator.reads.compactMap { $0 }) == [pid, otherPID]
                                 && FrontAppEnumerator.reads.count == 2 && FrontAppEnumerator.inventoryCaptureSequence.isEmpty,
                                 "two filtered scans run in one refresh and only the earlier capture describes C's owner")
                }
                if scenario == .selectedHelperExited || scenario == .uncertainHostSource { inventory.remove(pid: renderer) }
                if scenario == .returningHelperWindow {
                    FrontAppEnumerator.firstFrontAppItems = [b, a]
                    let returned = SwitcherItem.window(id: ids[2], title: c.title, appName: c.appName, pid: pid,
                                                       windowOwnerPID: renderer, isOnScreen: true, frame: frame)
                    FrontAppEnumerator.items = [b, returned, a]
                } else {
                    reconcileHostWindows([ids[1], ids[0]])
                }
                let focus = Desktop.WindowUseTracker.shared.frontAppFocus(for: pid)
                suite.expect(focus.windowID == ids[1] && focus.latest?.previousWindowID == ids[2]
                             && focus.observedWindows.contains(ids[2]) == (scenario == .returningHelperWindow),
                             "\(scenario) starts with B focused and C still named as its predecessor")
                Desktop.WindowActivator.focusedWindow = scenario == .uncertainHostSource ? ids[0] : ids[1]
                FrontAppEnumerator.reads = []
            }
            let before = Activator.activated
            let priorTargets = service.recordedIDs, priorGenerations = service.startedGenerations
            let generation: UInt64
            if scenario == .carbonLive || scenario == .carbonKnown || scenario.carbonReleased {
                service.secureInputEnabled = true
                service.secureInputHotKeys[1] = .init(shortcut: shortcut)
                service.tapRunLoop = CFRunLoopGetCurrent()
                service.replayModifiers = shortcut.modifiers.cgFlags
                service.routeSecureInputHotKey(id: 1)
                if scenario == .carbonReleasedBeforeReplay {
                    suite.expect(service.carbonReplay.pending.count == 1 && service.keyboardInputOwnership.isOwned,
                                 "Carbon owns the shortcut before its queued keystroke reaches the tap")
                    service.replayModifiers = []
                    _ = service.route(type: .flagsChanged, event: release)
                }
                service.carbonReplay.drain()
                Queue.advance(to: Queue.time)
                if scenario == .carbonReleasedBeforeReplay {
                    suite.expect(!service.keyboardInputOwnership.isOwned && service.frontAppReadQueue.pending.isEmpty,
                                 "a replay with its modifier already up returns the keyboard without starting a private read")
                } else {
                    suite.expect(service.routePendingSessionStart?.isSecureInputReplay == true && service.frontAppReadQueue.pending.count == 1,
                                 "the Carbon shortcut starts a private current-app read while its modifier is held")
                }
                if scenario == .carbonReleasedDuringRead {
                    service.replayModifiers = []
                    _ = service.route(type: .flagsChanged, event: release)
                    suite.expect(!service.keyboardInputOwnership.isOwned,
                                 "modifier-up gives the keyboard back before the pending window read returns")
                }
                if scenario.carbonReleased {
                    service.frontAppReadQueue.drain()
                    if scenario == .carbonReleasedBeforeDelivery { service.replayModifiers = [] }
                    Queue.advance(to: Queue.time)
                    suite.expect(service.startedGenerations.isEmpty && !service.keyboardInputOwnership.isOwned
                                 && service.recordedIDs.isEmpty && Activator.activated == before,
                                 "\(scenario) leaves the released Carbon shortcut idle after its queues drain")
                    continue
                }
                generation = service.sessionStartGeneration
            } else {
                generation = press(service, shortcut: shortcut)
            }
            if scenario == .focusWithoutRaise || scenario == .changingFocusBehindFront {
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
                suite.expect(FrontAppEnumerator.reads == [pid, pid], "a focus behind the front window is checked twice")
                if scenario == .changingFocusBehindFront {
                    suite.expect(!service.sessionActive && !service.keyboardInputOwnership.isOwned
                                 && service.startedGenerations.isEmpty && Activator.activated == before,
                                 "a focus change between the two reads releases the shortcut without switching")
                } else {
                    suite.expect(service.sessionActive && service.sessionStartWindowID == b.windowID
                                 && service.windows.map(\.id) == [b.id, a.id] && service.selectedIndex == 1,
                                 "the held shortcut opens on the previous window after a hover focuses B behind A")
                    _ = service.route(type: .flagsChanged, event: release)
                    suite.expect(Activator.activated == before + [a.id] && Activator.lastSourceWindowID == b.windowID,
                                 "releasing the shortcut switches from the keyboard's window B to A")
                }
                continue
            }
            func escape(flags: CGEventFlags) -> Bool {
                let esc = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(KeyCode.escape), keyDown: true)!
                esc.flags = flags
                return service.route(type: .keyDown, event: esc) == nil
            }
            if scenario == .escape || scenario == .openingClick || scenario == .cancelledFirstPress {
                suite.expect(inventory.onRemoval != nil, "the pending read observes window removal")
                if scenario == .openingClick {
                    let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
                    _ = service.route(type: .leftMouseDown, event: click)
                } else {
                    _ = escape(flags: shortcut.modifiers.cgFlags)
                }
                Queue.advance(to: Queue.time)
                suite.expect(inventory.onRemoval == nil && !service.keyboardInputOwnership.isOwned,
                             "cancelling an opening detaches its destruction callback before the worker replies")
            }
            if scenario == .closedSource || scenario == .closedTarget {
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
                let previousListed = Enumerator.listed, previousCloses = Activator.closed
                defer { Enumerator.listed = previousListed; Activator.closed = previousCloses }
                service.closeWindow(c)
                guard Activator.closed.count == previousCloses.count + 1, let close = Activator.closed.last else {
                    suite.expect(false, "the open panel requests closing source C")
                    continue
                }
                Desktop.Events.shared.deliver?(.destroyed(ids[2]))
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid)
                Desktop.WindowActivator.focusedWindow = ids[1]
                Enumerator.listed = [b, a]
                close.completion(true)
                Queue.advance(to: Queue.time + 0.2)
                guard service.sessionActive, !service.windows.contains(c), let index = service.windows.firstIndex(of: a) else {
                    suite.expect(false, "closing C keeps A selectable in the same session")
                    continue
                }
                service.select(index: index)
                if scenario == .closedTarget { Desktop.Events.shared.deliver?(.destroyed(ids[0])) }
                _ = service.route(type: .flagsChanged, event: release)
                let expected = scenario == .closedSource ? [a.id] : []
                suite.expect(Activator.activated == before + expected && service.recordedIDs == expected
                             && (scenario == .closedTarget || Activator.lastSourceWindowID == ids[1])
                             && service.frontAppReadQueue.pending.isEmpty && !service.keyboardInputOwnership.isOwned,
                             "after the user closes C, the selection of A survives only while A exists")
                continue
            }
            if scenario.held {
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
                let target = (scenario == .heldKnown || scenario == .carbonKnown) ? a : c
                guard let index = service.windows.firstIndex(where: { $0.id == target.id }) else {
                    suite.expect(false, "the private panel includes its AX-only card and both remembered windows")
                    continue
                }
                service.select(index: index)
                if scenario == .heldEscape { _ = escape(flags: shortcut.modifiers.cgFlags) }
                if scenario == .heldDestroyed { Desktop.Events.shared.deliver?(.destroyed(ids[2])) }
                if scenario == .heldOwnerExited { inventory.remove(pid: renderer) }
                if scenario == .heldChangedSpace { Desktop.SpaceWindowBridge.visibleSpaces = [3] }
                if scenario == .heldLateSpaceNotice { Desktop.Events.shared.deliver?(.spacesChanged) }
                if scenario == .heldSecureInput || scenario == .heldSecureInputChanged {
                    service.secureInputEnabled = true
                    if scenario == .heldSecureInputChanged {
                        service.secureInputChanged(true)
                        service.secureInputEnabled = false
                        service.secureInputChanged(false)
                    }
                }
                _ = service.route(type: .flagsChanged, event: release)
                let commit: [Case] = [.heldKnown, .heldLive, .heldTyping, .heldLateSpaceNotice, .carbonLive, .carbonKnown]
                let expected = commit.contains(scenario) ? [target.id] : []
                suite.expect(service.recordedIDs == expected && Activator.activated == before + expected
                             && service.frontAppReadQueue.pending.isEmpty && !service.keyboardInputOwnership.isOwned
                             && !service.sessionActive && service.panel?.isVisible == false,
                             "\(scenario) finishes the selection on modifier release and returns the keyboard")
                if scenario == .heldTyping {
                    var commands: [SwitcherLetterAction] = []
                    service.runProtectedLetterAction = { commands.append($0) }
                    for (key, character) in [(13, "w"), (12, "q")] {
                        let letter = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true)!
                        letter.flags = []
                        letter.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array(character.utf16))
                        suite.expect(service.route(type: .keyDown, event: letter)?.takeUnretainedValue() === letter,
                                     "the editor receives its next typed letter")
                    }
                    service.frontAppReadQueue.drain()
                    Queue.advance(to: Queue.time)
                    suite.expect(commands.isEmpty && Activator.activated == before + expected,
                                 "typing after release performs no switcher action")
                }
                continue
            }
            _ = service.route(type: .flagsChanged, event: release)
            suite.expect(Activator.activated == before && service.frontAppReadQueue.pending.count == 1,
                         "\(scenario) queues one private read and leaves the key path free")
            if scenario == .timeout { Queue.advance(to: Queue.time + 1) }
            if scenario == .differentCapturedSpace { Desktop.SpaceWindowBridge.visibleSpaces = [3] }
            service.frontAppReadQueue.drain()
            if scenario == .selectedHelperExited {
                suite.expect(FrontAppEnumerator.reads == [pid, pid], "B has been sampled twice before its AX reconfirmation")
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid)
            }
            if scenario == .inspectorAfterMove { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[3], pid: pid) }
            if scenario == .inspectorAfterDocument { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[0], pid: pid) }
            if [.observedInspector, .inspectorAfterMove, .inspectorAfterDocument, .missingInspectorPrevious].contains(scenario) {
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid)
            }
            if scenario == .newerFocus { Desktop.WindowUseTracker.confirmedFocus = ids[0] }
            if scenario == .repeatedFocus { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid) }
            if scenario == .changedPrevious { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[0], pid: pid) }
            if scenario == .changedPrevious || scenario == .confirmedSource {
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid)
            }
            if scenario == .destroyedTarget { Desktop.Events.shared.deliver?(.destroyed(ids[1])) }
            if scenario == .reconciledFocus || scenario == .reconciledPrevious {
                Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[3], pid: pid)
                let history = Desktop.WindowUseTracker.history
                let oldIDs = Array(ids.prefix(3))
                history.windowHistory = tracker.history
                history.reconcile(existingWindows: Set(oldIDs), frontToBack: .init(windows: oldIDs, apps: [pid]),
                                  running: [pid], revision: history.focusHistory.revision)
                tracker.history = history.windows
                suite.expect(Desktop.WindowUseTracker.confirmedFocus == nil && FrontAppEnumerator.reads == [pid],
                             "the scan omits D after a consistent private read of C, B and A")
                if scenario == .reconciledPrevious { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[2], pid: pid) }
            }
            if service.currentSpaceOnly {
                Desktop.SpaceWindowBridge.visibleSpaces = scenario == .changedSpace ? [3] : [2]
                Desktop.Events.shared.deliver?(.spacesChanged)
            }
            Queue.advance(to: Queue.time)
            if scenario.repeats {
                let cancelled = scenario == .cancelledFirstPress
                let firstTarget = sourceIsB ? a : b
                let firstTargets = cancelled ? [] : [firstTarget.id]
                suite.expect(service.recordedIDs == priorTargets + firstTargets && Activator.activated == before + firstTargets
                             && (cancelled || Activator.lastSourceWindowID == source),
                             "\(scenario) records the source and destination of the first completed switch")
                if scenario == .helperRepeat {
                    let recorded = Desktop.WindowUseTracker.history.focusHistory.current
                    suite.expect(recorded?.pid == pid && recorded?.focusPID == renderer,
                                 "the switch belongs to the host and records the renderer that owns keyboard focus")
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: renderer)
                }
                if scenario == .newFocusBeforeRepeat {
                    Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[3], pid: pid)
                    Desktop.WindowActivator.focusedWindow = ids[3]
                    FrontAppEnumerator.items = [d, b, c, a]
                }
                if scenario == .repeatWithoutAX { Desktop.WindowActivator.focusedWindow = nil }
                if scenario == .repeatSplitSignals { Desktop.WindowActivator.focusedWindow = ids[1] }
                if scenario == .repeatWithConfirmation { Desktop.WindowUseTracker.shared.recordObservedFocus(windowID: ids[1], pid: pid) }
                let second = press(service, shortcut: shortcut)
                if scenario != .heldRepeat { _ = service.route(type: .flagsChanged, event: release) }
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
                if scenario == .heldRepeat {
                    suite.expect(service.sessionActive && service.windows.indices.contains(service.selectedIndex)
                                 && service.windows[service.selectedIndex].id == c.id, "the second press adopts C as the selected target")
                    Queue.advance(to: Queue.time + 0.2)
                    _ = service.route(type: .flagsChanged, event: release)
                }
                if scenario == .helperRepeat {
                    suite.expect(Desktop.WindowActivator.focusReads == [renderer, renderer] && FrontAppEnumerator.reads == [pid, pid]
                                 && Activator.lastHandoffSourcePID == renderer,
                                 "both helper shortcuts read AX at the keyboard owner and enumerate only its host")
                }
                let next = cancelled || scenario == .newFocusBeforeRepeat || sourceIsB ? b : c
                let secondSource = scenario == .newFocusBeforeRepeat ? ids[3] : (cancelled ? source : firstTarget.windowID)
                let expectedReads: [pid_t?] = scenario.retriesPrevious ? [pid, pid, pid] : [pid, pid]
                suite.expect(second != generation && service.startedGenerations == priorGenerations + (cancelled ? [second] : [generation, second])
                             && Activator.activated == before + firstTargets + [next.id] && service.recordedIDs == priorTargets + firstTargets + [next.id]
                             && Activator.lastSourceWindowID == secondSource && (cancelled || FrontAppEnumerator.reads == expectedReads),
                             "\(scenario) opens a new generation from the last completed switch or newer focus")
                continue
            }
            let discarded: [Case] = [.omittedFocus, .conflictingFocus, .escape, .changedSpace, .differentCapturedSpace, .timeout, .newerFocus,
                                     .unlistedFront, .repeatedFocus, .changedPrevious, .destroyedTarget,
                                     .reconciledFocus, .reconciledPrevious, .openingClick, .prunedSource, .uncertainHostSource,
                                     .inspectorAfterMove, .inspectorAfterDocument]
            if discarded.contains(scenario) {
                suite.expect(Activator.activated == before && !service.keyboardInputOwnership.isOwned && service.recordedIDs.isEmpty
                             && (scenario == .destroyedTarget || service.startedGenerations.isEmpty),
                             "\(scenario) discards the reply without recording or activating any target")
                if [.omittedFocus, .conflictingFocus, .unlistedFront, .prunedSource, .uncertainHostSource].contains(scenario) {
                    suite.expect(FrontAppEnumerator.reads == [pid, pid], "inconsistent evidence gets one scoped retry")
                }
            } else {
                let ordinaryTarget = sourceIsB || scenario == .observedPrevious || scenario == .onlyPreviousObserved ? a : b
                let target = [.restoredPrevious, .recoveredPrevious].contains(scenario) ? d : (scenario == .returningHelperWindow ? c : ordinaryTarget)
                suite.expect(service.startedGenerations == [generation] && Activator.activated == before + [target.id]
                             && service.recordedIDs == [target.id] && Activator.lastSourceWindowID == source
                             && FrontAppEnumerator.reads == (scenario == .retry || scenario.retriesPrevious ? [pid, pid] : [pid]),
                             "\(scenario) commits once from the fresh source to the editor's previous window")
            }
        }
    }

    private static func checkGlobalWindowOpening(_ suite: TestSuite) {
        typealias Desktop = SwitcherRememberedSelectionTests.SessionOpening
        typealias Work = Desktop.DispatchQueue
        enum Mode: CaseIterable {
            case allWindowsGrid, allWindowsSimple, mainGrid, mainSimple, groupedGrid, groupedSimple, appIconRow

            var shortcut: GlobalShortcut {
                self == .allWindowsGrid || self == .allWindowsSimple ? .switcherAllWindowsDefault : .switcherDefault
            }
            var grouped: Bool { self == .groupedGrid || self == .groupedSimple }
            var simple: Bool { self == .allWindowsSimple || self == .mainSimple || self == .groupedSimple }
            var showsApps: Bool { grouped || self == .appIconRow }
        }
        enum Opening: CaseIterable {
            case announced, warm, escape, otherDisplay, changedSpace, earlierScan
            case captured, publishedBeforeOpening, backgroundWindow, newerFocus, closedSourceDuringDelivery
            case observedFocus, observedBeforeNotice, escapeBeforeNotice, windowServerFocus, unlistedInspector, backgroundWithoutAX
            case unrelatedDiscoveryBeforeNotice, unrelatedDiscoveryAfterNotice

            var announcesWindow: Bool { self != .warm && self != .unlistedInspector }
            var hasUnrelatedDiscovery: Bool { self == .unrelatedDiscoveryBeforeNotice || self == .unrelatedDiscoveryAfterNotice }
            var observesBeforeNotice: Bool { self == .observedBeforeNotice || self == .escapeBeforeNotice || hasUnrelatedDiscovery }
            var groupedOnly: Bool {
                hasUnrelatedDiscovery || [.observedFocus, .windowServerFocus, .backgroundWithoutAX].contains(self)
            }
        }

        let pid: pid_t = 10
        let displays = [CGRect(x: 0, y: 0, width: 900, height: 700), CGRect(x: 900, y: 0, width: 900, height: 700)]
        func window(_ id: CGWindowID, owner: pid_t = 10, display: Int = 0) -> SwitcherItem {
            .window(id: id, title: "Window \(id)", appName: "App \(owner)", pid: owner, isOnScreen: true,
                    frame: displays[display].insetBy(dx: 40, dy: 40))
        }
        let a = window(1), b = window(2), c = window(3), d = window(4, owner: pid + 1)
        func key(_ code: CGKeyCode, flags: CGEventFlags) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            return event
        }
        let release = CGEvent(source: nil)!
        release.type = .flagsChanged
        release.flags = []
        func captureRefresh() {
            Work.main.debounce.drain()
            Work.scans.drain()
        }

        let tracker = SwitcherRememberedSelectionTests.Tracker.shared
        let history = WindowUseTracker.history
        let previousOrder = tracker.history, previousFocus = history.focusHistory
        let previousWindows = history.windowHistory, previousApps = history.appHistory
        let previousApp = Workspace.shared.frontmostApplication, previousRegisteredApps = Desktop.NSRunningApplication.apps
        let previousSpaces = SpaceWindowBridge.visibleSpaces, previousJobs = Queue.jobs
        let previousItems = FrontAppEnumerator.items, previousReads = FrontAppEnumerator.reads
        let previousAX = Desktop.WindowActivator.focusedWindow, previousAXReads = Desktop.WindowActivator.focusReads
        let previousActivations = Activator.activated, previousSource = Activator.lastSourceWindowID
        let defaults = SwitcherRememberedSelectionTests.Preferences.standard
        let previousPreferences = defaults.values
        let previousHandoff = Activator.lastHandoffSourcePID
        defer {
            defaults.values = previousPreferences
            tracker.history = previousOrder
            history.focusHistory = previousFocus
            history.windowHistory = previousWindows
            history.appHistory = previousApps
            Workspace.shared.frontmostApplication = previousApp
            Desktop.NSRunningApplication.apps = previousRegisteredApps
            SpaceWindowBridge.visibleSpaces = previousSpaces
            Queue.jobs = previousJobs
            FrontAppEnumerator.items = previousItems
            FrontAppEnumerator.reads = previousReads
            Desktop.WindowActivator.focusedWindow = previousAX
            Desktop.WindowActivator.focusReads = previousAXReads
            Activator.activated = previousActivations
            Activator.lastSourceWindowID = previousSource
            Activator.lastHandoffSourcePID = previousHandoff
        }
        Desktop.NSRunningApplication.apps[pid] = .init()
        Desktop.NSRunningApplication.apps[pid + 1] = .init()
        let cases = Mode.allCases.flatMap { mode -> [(Mode, Opening, GlobalWindowGesture?)] in
            let openings: [Opening] = mode.showsApps
                ? [.announced, .observedFocus, .observedBeforeNotice, .unrelatedDiscoveryBeforeNotice,
                   .windowServerFocus, .backgroundWindow, .backgroundWithoutAX, .warm, .closedSourceDuringDelivery]
                : Opening.allCases.filter { !$0.groupedOnly }
            let gestures: [GlobalWindowGesture] = mode.showsApps ? [] : GlobalWindowGesture.allCases
            let cases = mode == .groupedSimple ? openings + [.escape, .unlistedInspector, .unrelatedDiscoveryAfterNotice] : openings
            return cases.map { (mode, $0, nil) } + gestures.map { (mode, .announced, $0) }
        }
        for (mode, opening, gesture) in cases {
            let shortcut = mode.shortcut
            let service = Service(), inventory = Desktop.SwitcherWindowInventory()
            let previousInventoryApp = Desktop.desktop.frontmostApplication
            let previousRows = FrontAppEnumerator.capturedRows
            defer {
                Desktop.desktop.frontmostApplication = previousInventoryApp
                FrontAppEnumerator.capturedRows = previousRows
                inventory.stop()
                Work.discoveries.reset()
                Work.scans.reset()
                Work.main.deliveries.reset()
                Work.main.debounce.reset()
            }
            Queue.jobs = []
            Workspace.shared.frontmostApplication = .init(processIdentifier: pid)
            service.tap = Tap()
            service.routeAllWindowsShortcut = .switcherAllWindowsDefault
            service.simpleModeEnabled = mode.simple
            service.usesIconRowLayout = SwitcherSupport.usesIconRowLayout(iconRowMode: mode == .appIconRow, simpleMode: mode.simple)
            service.usesWindowRow = SwitcherSupport.usesWindowRow(simpleMode: mode.simple, mergeWindowsByApp: mode.grouped,
                                                                 sessionScope: .allApps)
            defaults.values = [DefaultsKey.switcherSimpleMode: mode.simple, DefaultsKey.switcherMergeTabs: mode.grouped,
                               DefaultsKey.switcherIconRowMode: mode == .appIconRow]
            service.currentSpaceOnly = opening == .changedSpace
            if opening == .otherDisplay { service.currentDisplayScope = .init(bounds: displays, targetIndex: 0) }
            service.windowInventory.observed = inventory
            inventory.onReady = service.windowInventory.onReady
            SpaceWindowBridge.visibleSpaces = [1]
            FrontAppEnumerator.items = mode.showsApps ? [b, a, d] : [b, a]
            tracker.history = [2, 1, 4]
            WindowUseTracker.confirmedFocus = nil
            WindowUseTracker.confirmedFocus = 2
            inventory.start()
            Work.scans.drain()
            Work.main.deliveries.drain()
            FrontAppEnumerator.reads = []
            Desktop.WindowActivator.focusReads = []
            Desktop.WindowActivator.focusedWindow = [.backgroundWindow, .backgroundWithoutAX, .warm].contains(opening) ? 2 : 3
            let before = Activator.activated

            if opening == .earlierScan {
                inventory.invalidate(pid: pid + 1)
                captureRefresh()
            }
            if opening.announcesWindow {
                FrontAppEnumerator.items = [c, opening == .otherDisplay ? window(2, display: 1) : b, a]
                if mode.showsApps { FrontAppEnumerator.items.append(d) }
                if !opening.observesBeforeNotice { Desktop.Events.shared.deliver?(.changed(3)) }
                if opening == .windowServerFocus {
                    Desktop.desktop.frontmostApplication = .init(processIdentifier: pid)
                    suite.expect(WindowUseTracker.confirmedFocus == 2 && !inventory.contains(c),
                                 "the AX observer still reports B before the WindowServer announces focus on C")
                    Desktop.Events.shared.deliver?(.focused(3))
                }
            }
            if !mode.showsApps && opening == .unlistedInspector {
                // The WindowServer includes the floating inspector. Only B and A are switchable.
                FrontAppEnumerator.capturedRows = [FrontAppEnumerator.stackRow(window(93), layer: 3),
                                                   FrontAppEnumerator.stackRow(b), FrontAppEnumerator.stackRow(a)]
            }
            if mode.showsApps || opening.observesBeforeNotice || opening == .unlistedInspector {
                service.useTracker = .shared
                suite.expect(Desktop.WindowActivator.focusReads.isEmpty, "\(mode) stays idle before the shortcut")
                if opening.observesBeforeNotice || [.observedFocus, .unlistedInspector].contains(opening) {
                    guard let request = history.focusHistory.current else {
                        suite.expect(false, "the source app has a focus observer")
                        continue
                    }
                    let previousRead = history.readAXFocus
                    defer { history.readAXFocus = previousRead }
                    let id: CGWindowID = opening == .unlistedInspector ? 93 : 3
                    Desktop.WindowActivator.focusedWindow = id
                    history.readAXFocus = Desktop.WindowActivator.focusedWindowID(for:)
                    history.windowHistory = tracker.history
                    let accepted = history.readFocusedWindow(for: request)
                    tracker.history = history.windows
                    suite.expect(accepted && tracker.history.first == id && !inventory.knownWindowIDs.contains(id),
                                 "the source observer reports focus on a window absent from the inventory")
                    Desktop.WindowActivator.focusReads = []
                }
                if opening.hasUnrelatedDiscovery { Desktop.Events.shared.deliver?(.changed(99)) }
            }
            if let gesture {
                checkGlobalWindowGesture(gesture, suite, mode: String(describing: mode),
                                         service: service, shortcut: shortcut, inventory: inventory, a: a, b: b, c: c)
                continue
            }
            if opening == .captured || opening == .publishedBeforeOpening {
                Work.discoveries.drain()
                Work.main.deliveries.drain()
                captureRefresh()
                suite.expect(FrontAppEnumerator.reads == [pid] && !inventory.knownWindowIDs.contains(3),
                             "C was captured for its owner and awaits adoption")
            }

            let historyBeforePress = tracker.history, focusBeforePress = history.focusHistory.revision
            func deliverWork() {
                Work.discoveries.drain()
                Work.main.deliveries.drain()
                captureRefresh()
                Work.main.deliveries.drain()
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
            }
            _ = service.route(type: .keyDown, event: key(CGKeyCode(shortcut.keyCode), flags: shortcut.modifiers.cgFlags))
            let generation = service.sessionStartGeneration
            if opening == .publishedBeforeOpening {
                // onReady starts the session while the tap's beginPendingSession still waits on main.
                suite.expect(service.routePendingSessionStart?.generation == generation && service.keyboardInputOwnership.isOwned,
                             "the tap has claimed All Windows before the captured result reaches main")
                Work.main.deliveries.drain()
            }
            Queue.advance(to: Queue.time)
            if opening == .unlistedInspector && mode == .allWindowsSimple {
                func press() {
                    _ = service.route(type: .keyDown, event: key(CGKeyCode(shortcut.keyCode), flags: shortcut.modifiers.cgFlags))
                    Queue.advance(to: Queue.time)
                }
                func cancel() {
                    _ = service.route(type: .keyDown, event: key(CGKeyCode(KeyCode.escape), flags: shortcut.modifiers.cgFlags))
                    _ = service.route(type: .flagsChanged, event: release)
                    deliverWork()
                }
                Work.scans.drain()
                suite.expect(FrontAppEnumerator.reads == [pid] && service.routePendingSessionStart?.generation == generation,
                             "the inspector scan finishes before Escape cancels its pending shortcut")
                cancel()
                press()
                suite.expect(service.sessionActive && Work.scans.pending.isEmpty,
                             "the same inspector observation opens the second shortcut without another scan")
                cancel()
                suite.expect(FrontAppEnumerator.reads == [pid] && Activator.activated == before && service.recordedIDs.isEmpty
                             && tracker.history == historyBeforePress && history.focusHistory.revision == focusBeforePress,
                             "both cancelled shortcuts leave window use and focus history untouched")

                FrontAppEnumerator.items = [c, b, a]
                FrontAppEnumerator.capturedRows = nil
                Desktop.WindowActivator.focusedWindow = c.windowID
                WindowUseTracker.shared.recordObservedFocus(windowID: 3, pid: pid)
                press()
                _ = service.route(type: .flagsChanged, event: release)
                deliverWork()
                suite.expect(FrontAppEnumerator.reads == [pid, pid] && Activator.activated == before + [b.id]
                             && Activator.lastSourceWindowID == c.windowID && service.recordedIDs == [b.id],
                             "a new observation still scans C's app and switches from C to B")

                FrontAppEnumerator.items.append(window(93))
                Desktop.Events.shared.deliver?(.changed(93))
                deliverWork()
                suite.expect(FrontAppEnumerator.reads == [pid, pid, pid] && inventory.knownWindowIDs.contains(93),
                             "a window notification can admit the formerly excluded ID once it becomes switchable")
                continue
            }
            if opening == .escapeBeforeNotice {
                Work.discoveries.drain()
                Work.main.deliveries.drain()
                Work.scans.drain()
                suite.expect(FrontAppEnumerator.reads == [pid] && !inventory.contains(c)
                             && service.routePendingSessionStart?.generation == generation,
                             "Escape arrives after C's scan, before its result reaches the pending shortcut")
            }
            if opening == .escape || opening == .escapeBeforeNotice {
                suite.expect(service.route(type: .keyDown, event: key(CGKeyCode(KeyCode.escape), flags: shortcut.modifiers.cgFlags)) == nil,
                             "Escape cancels the shortcut while discovery is pending")
            }
            _ = service.route(type: .flagsChanged, event: release)
            if mode.showsApps {
                let label = "\(mode) \(opening)"
                let source = opening.observesBeforeNotice || [.announced, .observedFocus, .windowServerFocus].contains(opening) ? c : b
                let targets = opening == .escape ? [] : [d.id]
                suite.expect(Activator.activated == before + targets && service.recordedIDs == targets
                             && service.frontAppReadQueue.pending.isEmpty && FrontAppEnumerator.reads.isEmpty
                             && Desktop.WindowActivator.focusReads.isEmpty && !service.keyboardInputOwnership.isOwned,
                             "\(label) handles release immediately without reading focus or waiting for inventory")
                if opening == .unlistedInspector {
                    suite.expect(Activator.lastSourceWindowID == b.windowID,
                                 "an unlisted inspector leaves the known source in place for activation")
                }

                if opening != .escape { Workspace.shared.frontmostApplication = .init(processIdentifier: d.pid) }
                if opening == .windowServerFocus { Desktop.desktop.frontmostApplication = .init(processIdentifier: d.pid) }
                // Some apps have no focused AX window once another app owns the keyboard.
                if opening.observesBeforeNotice || [.observedFocus, .windowServerFocus, .backgroundWithoutAX].contains(opening) {
                    Desktop.WindowActivator.focusedWindow = nil
                }
                if opening.observesBeforeNotice {
                    suite.expect(Work.discoveries.pending.count == (opening.hasUnrelatedDiscovery ? 1 : 0) && !inventory.contains(c),
                                 "\(label) activates D before the creation of the observed C reaches the inventory")
                    if opening == .unrelatedDiscoveryBeforeNotice {
                        Work.discoveries.drain()
                        Work.main.deliveries.drain()
                    }
                    Desktop.Events.shared.deliver?(.changed(3))
                }
                Work.discoveries.drain()
                Work.main.deliveries.drain()
                captureRefresh()
                if opening == .closedSourceDuringDelivery {
                    Desktop.Events.shared.deliver?(.destroyed(3))
                    FrontAppEnumerator.items.removeAll { $0.id == c.id }
                }
                Work.main.deliveries.drain()
                suite.expect(FrontAppEnumerator.reads == (opening.announcesWindow ? [pid] : [])
                             && Desktop.WindowActivator.focusReads.isEmpty
                             && inventory.contains(c) == (opening.announcesWindow && opening != .closedSourceDuringDelivery),
                             "\(label) finishes only the announced app's refresh before the return")
                if opening == .escape {
                    suite.expect(Activator.activated == before && service.recordedIDs.isEmpty && tracker.history == [2, 1, 4]
                                 && WindowUseTracker.shared.frontAppFocus(for: pid).observedWindows == [2],
                                 "the cancelled grouped session cannot write either history when the scan arrives")
                    continue
                }
                let pair = [d, source].compactMap(\.windowID)
                let observed = WindowUseTracker.shared.frontAppFocus(for: d.pid).observedWindows
                suite.expect(tracker.history.starts(with: pair) && observed.starts(with: pair),
                             "\(label) records D followed by its surviving source window")
                let allWindows = GlobalShortcut.switcherAllWindowsDefault
                _ = service.route(type: .keyDown, event: key(CGKeyCode(allWindows.keyCode), flags: allWindows.modifiers.cgFlags))
                Queue.advance(to: Queue.time)
                _ = service.route(type: .flagsChanged, event: release)
                suite.expect(Activator.activated == before + [d.id, source.id] && service.recordedIDs == [d.id, source.id]
                             && Desktop.WindowActivator.focusReads.isEmpty && !service.keyboardInputOwnership.isOwned,
                             "\(label) returns from D to the original focused window with All Windows")
                continue
            }
            if opening.observesBeforeNotice || opening == .unlistedInspector {
                let label = "\(mode) \(opening)"
                let cancelled = opening == .escapeBeforeNotice, inspector = opening == .unlistedInspector
                let source = inspector ? b : c, target = inspector ? a : b
                let expectedIDs = cancelled ? [] : [target.id]
                // Only AX has reported the focus. Deliver worker replies while still withholding the creation notice.
                deliverWork()
                let activated = Array(Activator.activated.dropFirst(before.count))
                suite.expect(activated == expectedIDs && service.recordedIDs == expectedIDs
                             && service.startedGenerations == (cancelled ? [] : [generation])
                             && !service.keyboardInputOwnership.isOwned,
                             "\(label) before the creation notice: expected activations \(expectedIDs), got \(activated)")
                if cancelled {
                    suite.expect(tracker.history == historyBeforePress && history.focusHistory.revision == focusBeforePress,
                                 "Escape cancels the pending switch without recording a new focus or use")
                } else {
                    suite.expect(Activator.lastSourceWindowID == source.windowID && FrontAppEnumerator.reads == [pid]
                                 && tracker.history.starts(with: [target, source].compactMap(\.windowID))
                                 && inventory.knownWindowIDs == (inspector ? [1, 2] : [1, 2, 3]),
                                 "\(label) checks only the front app and uses its listed source for activation")
                }
                if inspector { continue }
                let orderBeforeNotice = tracker.history
                Desktop.Events.shared.deliver?(.changed(3))
                deliverWork()
                suite.expect(Activator.activated == before + expectedIDs && service.recordedIDs == expectedIDs
                             && tracker.history == orderBeforeNotice && !service.sessionActive && !service.keyboardInputOwnership.isOwned,
                             "\(label) cannot reopen the shortcut or write history again when the notice arrives")
                continue
            }
            if opening == .warm {
                suite.expect(Activator.activated == before + [a.id] && Activator.lastSourceWindowID == 2
                             && FrontAppEnumerator.reads.isEmpty && Desktop.WindowActivator.focusReads.isEmpty
                             && Work.main.debounce.pending.isEmpty && Work.scans.pending.isEmpty && service.frontAppReadQueue.pending.isEmpty,
                             "with a current inventory All Windows switches B to A immediately without reading windows or AX focus")
                continue
            }
            if opening == .otherDisplay { service.currentDisplayScope = .init(bounds: displays, targetIndex: 1) }
            if opening == .earlierScan {
                Work.main.deliveries.drain()
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
            }
            if opening != .escape {
                suite.expect(Activator.activated == before && service.routePendingSessionStart?.generation == generation,
                             "\(mode) \(opening) waits for C's refresh and focus before activation")
            }
            if opening == .captured {
                FrontAppEnumerator.items.append(d)
                Desktop.Events.shared.deliver?(.changed(4))
            } else {
                Work.discoveries.drain()
            }
            Work.main.deliveries.drain()
            if opening == .announced {
                suite.expect(Work.scans.pending.count == 1 && Work.main.debounce.pending.isEmpty,
                             "\(mode) starts C's scheduled scan as soon as its owner is known")
            } else if opening == .escape {
                suite.expect(Work.scans.pending.isEmpty && Work.main.debounce.pending.count == 1,
                             "\(mode) leaves the ordinary background refresh scheduled after cancellation")
            }
            captureRefresh()
            if opening == .changedSpace {
                SpaceWindowBridge.visibleSpaces = [2]
                Desktop.Events.shared.deliver?(.spacesChanged)
            }
            Work.main.deliveries.drain()
            Work.scans.drain()
            Work.main.deliveries.drain()
            service.frontAppReadQueue.drain()
            if opening == .newerFocus {
                suite.expect(Desktop.WindowActivator.focusReads == [pid] && Activator.activated == before,
                             "C's AX focus was read and awaits delivery")
                WindowUseTracker.shared.recordObservedFocus(windowID: 1, pid: pid)
            }
            if opening == .closedSourceDuringDelivery {
                suite.expect(Desktop.WindowActivator.focusReads == [pid] && inventory.contains(c) && Activator.activated == before,
                             "the pending AX answer names C before it is destroyed")
                Desktop.Events.shared.deliver?(.destroyed(3))
                FrontAppEnumerator.items.removeAll { $0.id == c.id }
            }
            Queue.advance(to: Queue.time)
            if [.escape, .changedSpace, .newerFocus, .closedSourceDuringDelivery].contains(opening) {
                suite.expect(Activator.activated == before && service.recordedIDs.isEmpty && service.startedGenerations.isEmpty
                             && !service.keyboardInputOwnership.isOwned,
                             "\(mode) \(opening) ignores the late result and releases the keyboard")
            } else {
                let target = opening == .otherDisplay || opening == .backgroundWindow ? a : b
                let source = opening == .backgroundWindow ? b : c
                suite.expect(Activator.activated == before + [target.id] && Activator.lastSourceWindowID == source.windowID
                             && Desktop.WindowActivator.focusReads == [pid] && !service.keyboardInputOwnership.isOwned,
                             "\(mode) \(opening) switches once from the focused window to its previous eligible window")
            }
            if opening == .captured {
                suite.expect(Work.discoveries.pending.count == 1 && FrontAppEnumerator.reads == [pid],
                             "the shortcut completes while the other app's later discovery is pending")
                Work.discoveries.drain()
                Work.main.deliveries.drain()
                captureRefresh()
                Work.main.deliveries.drain()
                service.frontAppReadQueue.drain()
                Queue.advance(to: Queue.time)
                suite.expect(Activator.activated == before + [b.id] && service.startedGenerations == [generation],
                             "the other app's later arrival cannot reopen or repeat the completed shortcut")
            }
        }
    }

    private enum GlobalWindowGesture: CaseIterable {
        case repeatBeforeRefresh, repeatBeforeMain, repeatDuringActivation, typeDuringWait, typeAfterTwoReleases
        case repeatWithOtherShortcut, typeOnConfirmedTarget, typeOnUnfocusedTarget, typeInOtherApp
        case typeWithoutEventPID, typeWithForeignEventPID
        case hold, heldEscape, closedWindow
        case carbonHeld, carbonReleased, carbonReleasedBeforeReplay, carbonReleasedBeforeDelivery

        var usesCarbon: Bool {
            [.carbonHeld, .carbonReleased, .carbonReleasedBeforeReplay, .carbonReleasedBeforeDelivery].contains(self)
        }
    }

    private static func checkGlobalWindowGesture(_ gesture: GlobalWindowGesture, _ suite: TestSuite, mode: String,
                                                service: Service, shortcut: GlobalShortcut, inventory: SwitcherWindowInventory,
                                                a: SwitcherItem, b: SwitcherItem, c: SwitcherItem) {
        typealias Desktop = SwitcherRememberedSelectionTests.SessionOpening
        typealias Work = Desktop.DispatchQueue
        let label = "\(mode) \(gesture)"
        let before = Activator.activated
        let release = CGEvent(source: nil)!
        release.type = .flagsChanged
        release.flags = []
        func key(_ code: CGKeyCode, flags: CGEventFlags) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            event.flags = flags
            return event
        }
        func sendShortcut(_ chord: GlobalShortcut) {
            _ = service.route(type: .keyDown, event: key(CGKeyCode(chord.keyCode), flags: chord.modifiers.cgFlags))
        }
        func keyDown() { sendShortcut(shortcut) }
        func modifierUp() { _ = service.route(type: .flagsChanged, event: release) }
        func settleFocus() {
            // A queued gesture can start a second focus read after the first reached main.
            Queue.advance(to: Queue.time)
            service.frontAppReadQueue.drain()
            Queue.advance(to: Queue.time)
            service.frontAppReadQueue.drain()
            Queue.advance(to: Queue.time)
        }
        func captureInventory() {
            Work.discoveries.drain()
            Work.main.deliveries.drain()
            Work.main.debounce.drain()
            Work.scans.drain()
            Work.main.deliveries.drain()
        }
        var delivered: [String] = []
        var commands: [SwitcherLetterAction] = []
        service.runProtectedLetterAction = { commands.append($0) }
        func typeLetter(_ text: String = "w", code: CGKeyCode = 13, eventPID: pid_t = 0, recipient: String? = nil) {
            let letter = key(code, flags: [])
            let characters = Array(text.utf16)
            letter.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
            letter.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(eventPID))
            guard let routed = service.route(type: .keyDown, event: letter)?.takeUnretainedValue() else { return }
            suite.expect(routed === letter, "\(label) returns the original typed event")
            delivered.append(recipient ?? Activator.activated.dropFirst(before.count).last ?? c.id)
        }
        service.useTracker = .shared
        if [.typeOnConfirmedTarget, .typeOnUnfocusedTarget, .typeInOtherApp, .typeWithoutEventPID, .typeWithForeignEventPID].contains(gesture) {
            let previousActivation = Activator.onActivation, previousApp = Workspace.shared.frontmostApplication
            defer {
                Activator.onActivation = previousActivation
                Workspace.shared.frontmostApplication = previousApp
            }
            var attempts = 0
            Activator.onActivation = { selected in
                attempts += 1
                suite.expect(selected.id == b.id, "\(label) requests B before the letter arrives")
                // recordSwitch already names B. Only a subsequent focus observation confirms that B has the keyboard.
                if gesture != .typeOnUnfocusedTarget {
                    Desktop.WindowActivator.focusedWindow = b.windowID
                    WindowUseTracker.shared.recordObservedFocus(windowID: 2, pid: b.pid)
                }
                let frontPID = gesture == .typeInOtherApp ? b.pid + 1 : b.pid
                Workspace.shared.frontmostApplication = .init(processIdentifier: frontPID)
                let eventPID: pid_t
                switch gesture {
                case .typeWithoutEventPID, .typeInOtherApp: eventPID = 0
                case .typeWithForeignEventPID: eventPID = b.pid + 1
                default: eventPID = b.pid
                }
                let wasBusy = Queue.mainIsBusy, waits = Queue.waitsWhileBusy
                defer { Queue.mainIsBusy = wasBusy; Queue.waitsWhileBusy = waits }
                Queue.mainIsBusy = true
                let recipientPID = eventPID == 0 ? frontPID : eventPID
                let focused = Desktop.WindowActivator.focusedWindow == b.windowID ? b : c
                typeLetter(eventPID: eventPID, recipient: recipientPID == b.pid ? focused.id : "other app")
                if gesture == .typeOnUnfocusedTarget {
                    let previous = WindowUseTracker.history.focusHistory.revision
                    Desktop.Events.shared.deliver?(.destroyed(3))
                    Desktop.WindowActivator.focusedWindow = a.windowID
                    suite.expect(WindowUseTracker.history.focusHistory.revision != previous && !inventory.contains(c),
                                 "\(label) removes predecessor C without observing focus on B")
                    typeLetter("q", code: 12, eventPID: eventPID, recipient: a.id)
                }
                suite.expect(Queue.waitsWhileBusy == waits, "\(label) resolves the letter while main is activating B")
            }
            keyDown()
            modifierUp()
            settleFocus()
            captureInventory()
            settleFocus()
            let expected = gesture == .typeOnConfirmedTarget || gesture == .typeWithoutEventPID ? [b.id] : []
            suite.expect(attempts == 1 && delivered == expected && commands.isEmpty && Activator.activated == before + [b.id]
                         && service.recordedIDs == [b.id] && !service.keyboardInputOwnership.isOwned,
                         "\(label) gives the original W only to the selected window that has keyboard focus")
            return
        }
        if [.repeatBeforeRefresh, .repeatBeforeMain, .repeatDuringActivation, .repeatWithOtherShortcut].contains(gesture) {
            Desktop.WindowActivator.focusedWindow = b.windowID
            let previousActivation = Activator.onActivation
            defer { Activator.onActivation = previousActivation }
            if gesture == .repeatDuringActivation {
                Activator.onActivation = { item in
                    Activator.onActivation = nil
                    let wasBusy = Queue.mainIsBusy, waits = Queue.waitsWhileBusy
                    defer { Queue.mainIsBusy = wasBusy; Queue.waitsWhileBusy = waits }
                    Queue.mainIsBusy = true
                    keyDown()
                    modifierUp()
                    suite.expect(item.id == a.id && waits == Queue.waitsWhileBusy,
                                 "\(label) claims the second flick while main is still activating A")
                }
            }
            keyDown()
            modifierUp()
            if gesture == .repeatBeforeRefresh || gesture == .repeatWithOtherShortcut { Queue.advance(to: Queue.time) }
            if gesture != .repeatDuringActivation {
                if gesture == .repeatWithOtherShortcut {
                    sendShortcut(shortcut == .switcherDefault ? .switcherAllWindowsDefault : .switcherDefault)
                } else {
                    keyDown()
                }
                modifierUp()
            }
            settleFocus()
            captureInventory()
            settleFocus()
            suite.expect(Activator.activated == before + [a.id, b.id] && service.recordedIDs == [a.id, b.id]
                         && Activator.lastSourceWindowID == a.windowID && !service.keyboardInputOwnership.isOwned,
                         "\(label) preserves both released gestures from B to A and back to B")
            typeLetter()
            settleFocus()
            suite.expect(delivered == [b.id] && commands.isEmpty && Activator.activated == before + [a.id, b.id],
                         "\(label) delivers the next letter once to B without another activation")
            return
        }

        if gesture.usesCarbon {
            service.secureInputEnabled = true
            service.secureInputHotKeys[1] = .init(shortcut: shortcut)
            service.tapRunLoop = CFRunLoopGetCurrent()
            service.replayModifiers = shortcut.modifiers.cgFlags
            service.routeSecureInputHotKey(id: 1)
            if gesture == .carbonReleasedBeforeReplay {
                service.replayModifiers = []
                modifierUp()
            }
            service.carbonReplay.drain()
        } else {
            keyDown()
        }
        Queue.advance(to: Queue.time)
        let typesWhilePending = gesture == .typeDuringWait || gesture == .typeAfterTwoReleases
        if typesWhilePending {
            modifierUp()
            if gesture == .typeAfterTwoReleases {
                keyDown()
                modifierUp()
                suite.expect(service.routePendingStarts.count == 2 && service.routePendingStarts.allSatisfy(\.commitWhenReady),
                             "\(label) has two released gestures before either destination was published")
            }
            typeLetter()
            suite.expect(delivered.isEmpty && service.routePendingStarts.isEmpty && !service.keyboardInputOwnership.isOwned,
                         "\(label) drops the uncertain selection and keeps its letter out of the wrong window")
        }
        if gesture == .carbonReleased {
            service.replayModifiers = []
            modifierUp()
            suite.expect(!service.keyboardInputOwnership.isOwned, "\(label) returns the keyboard immediately on modifier-up")
        }
        if gesture == .carbonReleased || gesture == .carbonReleasedBeforeReplay {
            typeLetter()
        }

        captureInventory()
        service.frontAppReadQueue.drain()
        if gesture == .carbonReleasedBeforeDelivery {
            // Secure Input can hide the tap's modifier-up. Main still sees the current physical flags.
            service.replayModifiers = []
        }
        Queue.advance(to: Queue.time)
        if gesture == .carbonReleasedBeforeDelivery { typeLetter() }
        if typesWhilePending || (gesture.usesCarbon && gesture != .carbonHeld) {
            let expectedText = gesture.usesCarbon ? [c.id] : []
            suite.expect(delivered == expectedText && commands.isEmpty && Activator.activated == before
                         && service.recordedIDs.isEmpty && !service.keyboardInputOwnership.isOwned,
                         "\(label) cannot activate a late result or take the following text")
            return
        }

        suite.expect(service.sessionActive && service.windows.indices.contains(service.selectedIndex)
                     && service.windows[service.selectedIndex].id == b.id && Activator.activated == before,
                     "\(label) opens the held shortcut on B while C remains in front")
        if gesture == .heldEscape {
            _ = service.route(type: .keyDown, event: key(CGKeyCode(KeyCode.escape), flags: shortcut.modifiers.cgFlags))
        } else if gesture == .closedWindow {
            Desktop.Events.shared.deliver?(.destroyed(2))
            FrontAppEnumerator.items.removeAll { $0.id == b.id }
            suite.expect(!inventory.contains(b), "\(label) observes the selected window's removal before release")
        }
        service.replayModifiers = []
        modifierUp()
        settleFocus()
        let targets = Array(Activator.activated.dropFirst(before.count))
        if gesture == .closedWindow {
            suite.expect(!targets.contains(b.id) && !service.recordedIDs.contains(b.id) && !service.keyboardInputOwnership.isOwned,
                         "\(label) never activates or records the closed window")
        } else {
            let expected = gesture == .heldEscape ? [] : [b.id]
            suite.expect(targets == expected && service.recordedIDs == expected && !service.keyboardInputOwnership.isOwned,
                         "\(label) finishes the held selection once and returns the keyboard")
        }
    }

    private static func checkPendingEscape(_ suite: TestSuite) {
        let service = Service()
        service.tap = Tap()
        service.windowInventory.items = nil
        service.panel?.isVisible = false
        service.routeWindowShortcut = .switcherAllWindowsDefault
        func commandKey(_ code: Int64) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)!
            event.flags = .maskCommand
            return event
        }
        let escape = commandKey(KeyCode.escape)
        let before = Activator.activated
        defer { Activator.activated = before }
        _ = service.route(type: .keyDown, event: commandKey(KeyCode.tab))
        Queue.advance(to: Queue.time)
        suite.expect(service.routePendingSessionStart?.commitWhenReady == false && service.keyboardInputOwnership.isOwned,
                     "the held shortcut is awaiting its inventory before Escape")
        let replay = service.secureInputReplays.enqueue(shortcut: service.routeShortcut)
        suite.expect(service.route(type: .keyDown, event: escape) == nil && !service.keyboardInputOwnership.isOwned
                     && !service.secureInputReplays.contains(replay),
                     "Escape with Command held cancels the pending start and invalidates queued replays")
        let release = CGEvent(source: nil)!
        release.type = .flagsChanged
        release.flags = []
        _ = service.route(type: .flagsChanged, event: release)
        service.windowInventory.publish(Inventory.sampleWindows)
        Queue.advance(to: Queue.time)
        suite.expect(service.startedGenerations.isEmpty && service.panel?.isVisible == false && Activator.activated == before
                     && service.route(type: .keyDown, event: escape)?.takeUnretainedValue() === escape,
                     "release and a late inventory leave the cancelled selection idle and the next Escape passes through")

        service.routeShortcut = GlobalShortcut(keyCode: KeyCode.escape, modifiers: [.command])
        service.windowInventory.items = nil
        _ = service.route(type: .keyDown, event: escape)
        Queue.advance(to: Queue.time)
        let generation = service.sessionStartGeneration
        _ = service.route(type: .keyDown, event: escape)
        suite.expect(service.routePendingSessionStart?.generation == generation
                     && service.routePendingSessionStart?.additionalNavigation == 1,
                     "a configured Command-Escape opens the switcher and a repeated press still navigates")
        service.windowInventory.publish(Inventory.sampleWindows)
        suite.expect(service.startedGenerations == [generation] && service.sessionActive,
                     "the configured Escape shortcut opens once when its window inventory arrives")
    }

    private static func checkTapRecovery(_ suite: TestSuite) {
        let letter = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
        let shortcut = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(KeyCode.tab), keyDown: true)!
        shortcut.flags = .maskCommand
        let release = CGEvent(source: nil)!
        release.type = .flagsChanged
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: .zero, mouseButton: .left)!
        let middleDown = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                                 mouseCursorPosition: CGPoint(x: 100, y: 100), mouseButton: .center)!
        let middleUp = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                               mouseCursorPosition: middleDown.location, mouseButton: .center)!
        let notice = CGEvent(source: nil)!
        defer {
            Queue.mainIsBusy = false
            Queue.jobs.removeAll()
            Permissions.shared.accessibility = true
            SessionActivity.shared.isActive = true
        }
        for disabled in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let service = Service()
            service.open()
            let port = Tap()
            service.tap = port
            service.hoveredWindowIndex = 1
            suite.expect(service.route(type: .otherMouseDown, event: middleDown) == nil && service.swallowingMiddleMouseUp,
                         "closing a window by middle click claims its matching release before the timeout")
            var cancelledBeforeEnable = false
            port.onEnable = { [weak service] in cancelledBeforeEnable = service?.panel?.isVisible == false }
            _ = service.secureInputReplays.enqueue(shortcut: service.routeShortcut)
            Queue.waitsWhileBusy = 0
            Queue.mainIsBusy = true
            suite.expect(service.keyboardInputOwnership.isOwned && service.scrollNavigationActive,
                         "the switcher owns keyboard and wheel routing while its session is open")
            _ = service.route(type: disabled, event: notice)
            _ = service.route(type: disabled, event: notice)
            for event in [letter, shortcut, click, middleUp, release] {
                suite.expect(service.route(type: event.type, event: event)?.takeUnretainedValue() === event,
                             "input passes unchanged while main cannot recover the disabled switcher")
            }
            suite.expect(service.route(type: .keyDown, event: shortcut, secureInputReplay: true)?.takeUnretainedValue() === shortcut
                         && !service.secureInputReplays.hasPending && service.routePendingSessionStart == nil,
                         "disabled routing drops pending replays and cannot claim another shortcut")
            suite.expect(!service.keyboardInputOwnership.isOwned && !service.scrollNavigationActive
                         && Queue.waitsWhileBusy == 0 && port.enables == 0 && Queue.jobs.count == 1,
                         "duplicate disable notices yield ownership and schedule one recovery without waiting on main or enabling the tap")
            Queue.mainIsBusy = false
            Queue.advance(to: Queue.time)
            suite.expect(port.enables == 1 && cancelledBeforeEnable && !service.sessionActive && service.appliedHotkeys == 1,
                         "the responsive main queue closes the old panel before enabling the current tap once")
            suite.expect(service.route(type: .keyDown, event: letter)?.takeUnretainedValue() === letter
                         && service.route(type: .leftMouseDown, event: click)?.takeUnretainedValue() === click
                         && service.route(type: .keyDown, event: shortcut) == nil,
                         "recovered routing passes unrelated input and claims the configured shortcut")
            let claimed = service.routePendingSessionStart?.generation
            Queue.advance(to: Queue.time)
            suite.expect(service.startedGenerations.count == 1 && service.startedGenerations.first == claimed && service.sessionActive,
                         "only the new shortcut schedules a session after recovery")
            suite.expect(service.route(type: .otherMouseUp, event: middleUp)?.takeUnretainedValue() === middleUp,
                         "a new session does not swallow a release owed to the session lost during the timeout")
        }

        for replacing in [true, false] {
            let service = Service()
            let original = Tap()
            let replacement = Tap()
            service.tap = original
            let match = (shortcut: service.routeShortcut, scope: SwitcherSessionScope.allApps, reversed: false)
            _ = service.claimPendingKey(match: match, secureInputReplay: false)
            _ = service.route(type: .tapDisabledByTimeout, event: notice)
            suite.expect(service.routePendingSessionStart == nil,
                         "the disabled tap discards a shortcut awaiting a session before main resumes")
            if replacing { service.tap = replacement } else { service.shouldStopTapThread = true }
            service.open()
            Queue.advance(to: Queue.time)
            suite.expect(service.sessionActive && service.panel?.isVisible == true && service.tapLifecycle.isEmpty
                         && original.enables == 0 && replacement.enables == 0 && service.appliedHotkeys == 0,
                         "work for a replaced or stopping port leaves the new session and its shortcuts alone")
        }
        for invalid in [true, false] {
            let service = Service()
            let port = Tap()
            service.tap = port
            _ = service.route(type: .tapDisabledByTimeout, event: notice)
            port.valid = !invalid
            port.acceptsEnable = false
            Queue.advance(to: Queue.time)
            suite.expect(port.enables == (invalid ? 0 : 1) && service.tapLifecycle == ["restore", "remove", "sync"]
                         && service.wantedAtPreferenceSync == true && service.appliedHotkeys == 0,
                         "a dead port or unsuccessful re-enable returns the shortcuts and removes the tap before resyncing")
        }
        for permissionLost in [true, false] {
            let service = Service()
            let port = Tap()
            service.tap = port
            _ = service.route(type: .tapDisabledByTimeout, event: notice)
            Permissions.shared.accessibility = !permissionLost
            SessionActivity.shared.isActive = permissionLost
            Queue.advance(to: Queue.time)
            suite.expect(port.enables == 0 && service.tapLifecycle == ["restore", "remove", "sync"]
                         && service.wantedAtPreferenceSync == false && service.appliedHotkeys == 0,
                         "a lost permission or inactive session leaves the old tap stopped after the preference check")
            Permissions.shared.accessibility = true
            SessionActivity.shared.isActive = true
        }
        let regranted = Service()
        regranted.installTap()
        guard let oldPort = regranted.tap else {
            suite.expect(false, "the eligible switcher publishes its initial port")
            return
        }
        _ = regranted.route(type: .tapDisabledByTimeout, event: notice)
        Permissions.shared.accessibility = false
        regranted.onRemoveTap = { Permissions.shared.accessibility = true }
        Queue.advance(to: Queue.time)
        suite.expect(oldPort.enables == 0 && regranted.tapLifecycle == ["restore", "remove", "sync"]
                     && regranted.shouldStopTapThread && regranted.pendingStartAfterStop && regranted.wantedAtPreferenceSync == true
                     && regranted.appliedHotkeys == 0,
                     "permission restored during teardown is visible to the next install decision with the old tap already stopping")
        checkTapReplacement(suite, notice: notice, shortcut: shortcut, middleDown: middleDown, middleUp: middleUp)
    }

    private static func checkTapReplacement(_ suite: TestSuite, notice: CGEvent, shortcut: CGEvent,
                                            middleDown: CGEvent, middleUp: CGEvent) {
        let service = Service()
        service.installTap()
        let retired = service.tap
        service.open()
        service.hoveredWindowIndex = 1
        suite.expect(service.route(type: .otherMouseDown, event: middleDown) == nil && service.swallowingMiddleMouseUp,
                     "the original tap claims the middle down that closes a card")
        _ = service.route(type: .tapDisabledByTimeout, event: notice)
        suite.expect(service.route(type: .otherMouseUp, event: middleUp)?.takeUnretainedValue() === middleUp,
                     "the release during the interruption passes before main can dismiss the session")
        service.removeTap()
        service.installTap()
        service.installTap()
        suite.expect(service.shouldStopTapThread && service.pendingStartAfterStop && service.startedTaps == 1,
                     "repeated install requests wait for the retiring tap thread")
        service.finishEventTapThread()
        suite.expect(service.tap == nil && service.tapThread == nil && service.startedTaps == 1,
                     "the outgoing tap thread leaves the replacement decision to main")
        Queue.advance(to: Queue.time)
        suite.expect(service.startedTaps == 2 && service.tap !== retired && service.isTapLive,
                     "an eligible restart publishes just one live replacement")
        let outside = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown,
                              mouseCursorPosition: CGPoint(x: 900, y: 900), mouseButton: .center)!
        let outsideUp = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                                mouseCursorPosition: outside.location, mouseButton: .center)!
        suite.expect(service.route(type: .otherMouseDown, event: outside)?.takeUnretainedValue() === outside
                     && service.route(type: .keyDown, event: shortcut) == nil,
                     "the app receives a fresh middle down outside the panel and the next shortcut belongs to the switcher")
        let claimed = service.routePendingSessionStart?.generation
        Queue.advance(to: Queue.time)
        suite.expect(service.startedGenerations.count == 1 && service.startedGenerations.first == claimed && service.sessionActive,
                     "the replacement claims exactly one session opening for the shortcut")
        suite.expect(service.route(type: .otherMouseUp, event: outsideUp)?.takeUnretainedValue() === outsideUp,
                     "opening the replacement switcher between the app's down and up preserves their pairing")
        guard service.windows.indices.contains(service.selectedIndex) else {
            suite.expect(false, "the replacement session has a selected fixture window")
            return
        }
        let selected = service.windows[service.selectedIndex].id
        let previousActivations = Activator.activated
        let released = CGEvent(source: nil)!
        released.type = .flagsChanged
        released.flags = []
        suite.expect(service.route(type: .flagsChanged, event: released)?.takeUnretainedValue() === released
                     && !service.sessionActive && Activator.activated == previousActivations + [selected],
                     "releasing the recovered shortcut finishes the session and activates only the selected window")

        for suspended in [true, false] {
            let stopping = Service()
            stopping.installTap()
            stopping.tap?.acceptsEnable = false
            _ = stopping.route(type: .tapDisabledByTimeout, event: notice)
            Queue.advance(to: Queue.time)
            suite.expect(stopping.shouldStopTapThread && stopping.pendingStartAfterStop,
                         "a failed re-enable requests a replacement while the retired thread still exists")
            stopping.finishEventTapThread()
            if suspended { stopping.suspend() } else { Permissions.shared.accessibility = false }
            Queue.advance(to: Queue.time)
            suite.expect(stopping.tap == nil && stopping.tapThread == nil && stopping.startedTaps == 1,
                         "a restart captured before suspension or permission loss cannot revive the tap")
            Permissions.shared.accessibility = true
        }
        for superseded in [false, true] {
            let failed = Service()
            failed.refusesPortCreation = true
            failed.installTap()
            if superseded {
                failed.refusesPortCreation = false
                failed.installTap()
            }
            Queue.advance(to: Queue.time)
            suite.expect(failed.restoredHotkeys == (superseded ? 0 : 1) && failed.isTapLive == superseded,
                         "a failed creation restores native shortcuts only if a newer installation has not claimed them")
        }
    }
}

extension SwitcherHoverSelectionTests.Service {
    func recordTapRecoveryPreferenceSync() {
        tapLifecycle.append("sync")
        wantedAtPreferenceSync = tapIsWanted
        routeCanStartSession = tapIsWanted
        if routeCanStartSession { installTap() }
    }
    func open(icons: Bool = false, windowRow: Bool = false) {
        sessionStartGeneration &+= 1
        sessionActive = true
        usesIconRowLayout = icons
        usesWindowRow = windowRow
        panel = SwitcherHoverSelectionTests.Panel()
        windows = SwitcherHoverSelectionTests.Inventory.sampleWindows
        sessionItems = windows
        totalWindowCount = windows.count
        SwitcherHoverSelectionTests.Enumerator.listed = windows
        iconRowLayout = SwitcherHoverSelectionTests.Row()
        selectedIndex = 1
        sessionShortcut = routeShortcut
        SwitcherHoverSelectionTests.Pointer.mouseLocation = NSPoint(x: 100, y: 100)
        hoverAnchor = SwitcherHoverSelectionTests.Pointer.mouseLocation
    }
}
