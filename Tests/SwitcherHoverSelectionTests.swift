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
    typealias WindowPreviewProvider = PreviewProvider
    typealias SwitcherAppIconCache = IconCache
    typealias ScrollWheelHIDStage = HIDStage
    typealias MouseAppExceptions = Exceptions

    enum Pointer { static var mouseLocation = NSPoint(x: 100, y: 100) }
    enum Permissions {
        static let shared = State()
        final class State { var accessibility = true }
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
    enum PreviewProvider {
        static let shared = State()
        struct State { func cancel() {} }
    }
    final class Panel {
        var isVisible = true
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
        struct Scheduler {
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
    class Fixture {
        var sessionActive = false
        let routeLock = NSLock()
        var sessionStartGeneration: UInt64 = 0
        let routeShortcut = GlobalShortcut.switcherDefault
        let routeWindowShortcut = GlobalShortcut.switcherWindowDefault
        var sessionShortcut: GlobalShortcut?
        var sessionScope: SwitcherSessionScope = .allApps
        var windows: [SwitcherItem] = []
        var sessionItems: [SwitcherItem] = []
        var previews: [CGWindowID: Int] = [:]
        var totalWindowCount = 0
        var sessionSourceContext: SwitcherSourceContext?
        // Main's activation snapshot and Secure Input cleanup are inert here.
        var sessionWindowServerSnapshot: Any?
        var sessionStartWindowID: CGWindowID?
        var sessionPlacementVisibleFrame: CGRect?
        var panel: Panel? = Panel()
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
        var grid = Grid()
        var iconRowLayout = Row()
        var shiftBackNavigationHeld = false
        var shiftBackChordDeadline: TimeInterval = 0
        func updateIconRowLayoutForCurrentSelection() {}
        func recomputeLayouts(for items: [SwitcherItem]) {}
        func resizePanel(animated: Bool = true) {}
        func cancelLetterConfirmation() {}
        func stopObservingTermination() {}
        func cancelPendingPreviewBatch() {}
        func invalidateSecureInputReplays() {}
        func unregisterSecureInputActionHotKeys() {}
        func recordUse(_ item: SwitcherItem, previous: CGWindowID?) {}
        func runProtectedLetterAction(_ action: SwitcherLetterAction) {
            preconditionFailure("quit-protection commands are covered separately")
        }
    }

    static func run(_ suite: TestSuite) {
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
}

extension SwitcherHoverSelectionTests.Service {
    func open(icons: Bool = false, windowRow: Bool = false) {
        sessionStartGeneration &+= 1
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
