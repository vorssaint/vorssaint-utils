// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Production hover, click callbacks, keyboard routing, commit, close and
/// teardown bodies run with synthetic entries and an explicit clock. Only OS
/// effects and layout are doubles. No input is posted or real window touched;
/// these checks do not exercise SwiftUI hit testing or Accessibility transport.
enum SwitcherHoverSelectionTests {
    typealias NSEvent = Pointer
    typealias NSWorkspace = Workspace
    typealias DispatchQueue = Queue
    typealias WindowActivator = Activator
    typealias WindowEnumerator = Enumerator
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
        final class State { var frontmostApplication: App? { nil } }
        struct App { let processIdentifier: pid_t }
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
    enum IconCache { static func endSession() {} }
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
        static var closed: [(item: SwitcherItem, completion: (Bool) -> Void)] = []
        static func activate(_ item: SwitcherItem, sourceWasFullscreen: Bool,
                             sourcePID: pid_t?, handoffSourcePID: pid_t?,
                             sourceWindowID: CGWindowID?, sourceWindowOwnerPID: pid_t?,
                             windowServerSnapshot: Any? = nil) {
            activated.append(item.id)
        }
        static func closeWindowIncludingHiddenState(_ item: SwitcherItem,
                                                   completion: @escaping (Bool) -> Void) {
            closed.append((item, completion))
        }
    }
    enum Enumerator {
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
        var removedIDs: Set<String> = []
        func contains(_ item: SwitcherItem) -> Bool { !removedIDs.contains(item.id) }
        func start() {}
        func stop() {}
    }
    struct Watch {
        func start() {}
        func stop() {}
    }

    class Fixture {
        let windowInventory = Inventory()
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
        var wantedAtPreferenceSync: Bool?
        let secureInputWatch = Watch()
        let exclusiveFullscreenWatch = Watch()
        var secureInputRegistrationFailed = false
        func startObservingKeyboardLayout() {}
        func stopObservingKeyboardLayout() {}
        func startObservingWake() {}
        func stopObservingExclusiveFullscreen() {}
        func stopObservingWake() {}
        var routeSessionActive: Bool { sessionActive }
        var routeCanStartSession = true
        var routeCapturing = false
        var yieldsToExclusiveFullscreen = false
        var routeYieldsToExclusiveFullscreen = false
        var routePendingSessionStart: SwitcherPendingSessionStart?
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
        var sessionWindowServerSnapshot: Any?
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
        func recordUse(_ item: SwitcherItem, previous: CGWindowID?) {}
        func runProtectedLetterAction(_ action: SwitcherLetterAction) {
            preconditionFailure("quit-protection commands are covered separately")
        }
    }

    static func run(_ suite: TestSuite) {
        checkSessionTitleSearch(suite)
        checkSessionPreviewCancellation(suite)
        checkTapRecovery(suite)
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
        routing.routePendingSessionStart?.commitWhenReady = true
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
    // Substitute the window inventory and presentation for the claimed generation.
    func beginPendingSession(generation: UInt64) {
        startedGenerations.append(generation)
        guard routePendingSessionStart?.generation == generation else { return }
        routePendingSessionStart = nil
        open(generation: generation)
    }
    func recordTapRecoveryPreferenceSync() {
        tapLifecycle.append("sync")
        wantedAtPreferenceSync = tapIsWanted
        routeCanStartSession = tapIsWanted
        if routeCanStartSession { installTap() }
    }
    func open(icons: Bool = false, windowRow: Bool = false, generation: UInt64? = nil) {
        sessionStartGeneration = generation ?? (sessionStartGeneration &+ 1)
        sessionActive = true
        usesIconRowLayout = icons
        usesWindowRow = windowRow
        panel = SwitcherHoverSelectionTests.Panel()
        windows = (0..<6).map { index in
            SwitcherItem.window(id: CGWindowID(index + 1), title: "Window \(index)", appName: "App \(index)",
                                pid: pid_t(index + 10), isOnScreen: true, frame: .zero)
        }
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
