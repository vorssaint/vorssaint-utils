// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct SwitcherInventorySpaces {
    private(set) var visible: Set<UInt64>?
    private(set) var revision = 0

    mutating func changed(to newSpaces: Set<UInt64>?, notified: Bool) -> Bool {
        guard visible != newSpaces || (notified && newSpaces == nil) else { return false }
        visible = newSpaces
        revision += 1
        return true
    }
}

final class SwitcherWindowInventory {
    private struct EmptySelectionRefresh: Equatable {
        let generation: UInt64
        let isFollowup: Bool
        var discoveries: Set<CGWindowID>
        var completed = false
    }

    private struct NewWindow {
        let appPID: pid_t
        let ownerPID: pid_t?
        let focusRevision: UUID
    }

    private struct FocusNotice {
        let id: CGWindowID
        let pid: pid_t
        var revision: UUID
    }

    private final class SourceCheck {
        let generation: UInt64
        let appPID: pid_t
        let frontPID: pid_t
        let deadline = DispatchTime.now() + 1
        var expired = false
        var attempts = 0
        var queued = false
        var reading = false
        var needsAXFocus = false
        var answer: (windowID: CGWindowID?, revision: UUID)?

        init(generation: UInt64, appPID: pid_t, frontPID: pid_t) {
            self.generation = generation
            self.appPID = appPID
            self.frontPID = frontPID
        }
    }

    private var sourceCheck: SourceCheck?
    private var newWindows: [CGWindowID: NewWindow] = [:]
    private var focusNotices: [FocusNotice] = []
    private var remembered = WindowEnumerator.WindowList(items: [], sourceItems: [])
    private var observers: [NSObjectProtocol] = []
    private var screenObservers: [NSObjectProtocol] = []
    private var pendingRefresh: DispatchWorkItem?
    private var refreshInFlight = false
    private var spaces = SwitcherInventorySpaces()
    private var fallbackTimer: Timer?
    private var observesWindowEvents = false
    private var needsFullRefresh = false
    private var emptySelectionRefresh: EmptySelectionRefresh?
    private var pendingPIDs: Set<pid_t> = []
    private var pendingWindowIDs: Set<CGWindowID> = []
    private var destroyedDuringRefresh: Set<CGWindowID> = []
    private var terminatedDuringRefresh: Set<pid_t> = []
    private let lifetimeLock = NSLock()
    private var lifetime: UUID?
    private let queue = DispatchQueue(label: "com.vorssaint.switcher.inventory", qos: .userInitiated)
    private let discoveryQueue = DispatchQueue(label: "com.vorssaint.switcher.discovery", qos: .utility)
    private let titles = SwitcherWindowTitles()

    var onReady: (([SwitcherItem]) -> Void)?
    private(set) var isReady = false

    func start() {
        guard lifetime == nil else { return }
        lifetimeLock.withLock { lifetime = UUID() }
        titles.onChange = { [weak self] pid in self?.invalidate(pid: pid) }
        observesWindowEvents = SwitcherWindowEvents.shared.start { [weak self] event in self?.receive(event) }
        setFallbackPolling(!observesWindowEvents)
        _ = spaces.changed(to: SpaceWindowBridge.topology()?.visibleSpaces, notified: false)
        let center = NSWorkspace.shared.notificationCenter
        let notifications = [NSWorkspace.didLaunchApplicationNotification,
                             NSWorkspace.didTerminateApplicationNotification,
                             NSWorkspace.didActivateApplicationNotification,
                             NSWorkspace.didHideApplicationNotification,
                             NSWorkspace.didUnhideApplicationNotification,
                             NSWorkspace.activeSpaceDidChangeNotification,
                             NSWorkspace.didWakeNotification]
        observers = notifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    if name == NSWorkspace.didTerminateApplicationNotification {
                        self.remove(pid: app.processIdentifier)
                    }
                    self.invalidate(pid: app.processIdentifier)
                } else if name == NSWorkspace.activeSpaceDidChangeNotification {
                    self.checkSpaces(notified: true)
                } else {
                    self.invalidate()
                }
            }
        }
        screenObservers = observeScreenChanges()
        needsFullRefresh = true
        refresh()
    }

    private func observeScreenChanges(in center: NotificationCenter = .default) -> [NSObjectProtocol] {
        let displays = center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                          object: nil, queue: .main) { [weak self] _ in self?.invalidate() }
        // Displays can share a Space, and receive(_:) ignores WindowServer moves for our own windows.
        let windowScreen = center.addObserver(forName: NSWindow.didChangeScreenNotification,
                                              object: nil, queue: .main) { [weak self] note in
            guard let window = note.object as? NSWindow, window.level == .normal,
                  WindowEnumerator.ownWindowID(for: window) != nil else { return }
            self?.invalidate(pid: ProcessInfo.processInfo.processIdentifier)
        }
        return [displays, windowScreen]
    }

    private func setFallbackPolling(_ needed: Bool) {
        if !needed {
            fallbackTimer?.invalidate()
            fallbackTimer = nil
        } else if fallbackTimer == nil {
            fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.invalidate() }
        }
    }

    func stop() {
        lifetimeLock.withLock { lifetime = nil }
        setFallbackPolling(false)
        spaces = SwitcherInventorySpaces()
        pendingRefresh?.cancel()
        pendingRefresh = nil
        refreshInFlight = false
        needsFullRefresh = false
        emptySelectionRefresh = nil
        sourceCheck = nil
        newWindows = [:]
        focusNotices = []
        pendingPIDs = []
        pendingWindowIDs = []
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        for observer in screenObservers { NotificationCenter.default.removeObserver(observer) }
        screenObservers = []
        SwitcherWindowEvents.shared.stop()
        titles.stop()
        remembered = WindowEnumerator.WindowList(items: [], sourceItems: [])
        isReady = false
    }

    func excludesFrontmostApp(pid: pid_t, regularBundleIdentifier: String?) -> Bool {
        SwitcherWindowSelection.excludesFrontmostApp(pid: pid, regularBundleIdentifier: regularBundleIdentifier,
                                                     remembered: remembered)
    }

    func selection(
        for generation: UInt64,
        scope: SwitcherSessionScope,
        frontmostPID: pid_t,
        displayScope: WindowEnumerator.DisplayScope?
    ) -> (list: WindowEnumerator.WindowList, focusedWindowID: CGWindowID?)? {
        if sourceCheck?.generation != generation { sourceCheck = nil }
        // An older scan may publish while this shortcut's confirmation is queued.
        if let request = emptySelectionRefresh, request.generation == generation, !request.completed { return nil }
        let appPID = SwitcherSupport.appPID(forFrontmost: frontmostPID, items: remembered.items)
        let tracker = WindowUseTracker.shared
        let observed = scope == .frontmostApp ? tracker.focusSnapshot(for: frontmostPID) : nil
        func visibleSource(_ id: CGWindowID) -> Bool {
            remembered.items.contains { $0.windowID == id && $0.pid == appPID && $0.isOnScreen && !$0.isMinimized }
        }
        let focused = observed?.windowID.flatMap { visibleSource($0) ? $0 : nil } ?? tracker.windows.first(where: visibleSource)
        let list = SwitcherWindowSelection.select(
            remembered: remembered,
            scope: scope,
            frontmostPID: frontmostPID,
            focusedWindowID: focused,
            displayScope: displayScope)
        if let observed, emptySelectionRefresh?.generation != generation,
           sourceCheck != nil || !list.items.isEmpty {
            return frontAppSelection(for: generation, appPID: appPID, frontPID: frontmostPID,
                                     displayScope: displayScope, observed: observed, warmList: list, warmFocus: focused)
        }
        if list.items.isEmpty, !confirmedEmptySelection(for: generation) { return nil }
        emptySelectionRefresh = nil
        titles.refreshUnobserved(in: list.items, accessibilityGranted: Permissions.shared.accessibility)
        return (list, focused)
    }

    private func frontAppSelection(
        for generation: UInt64, appPID: pid_t, frontPID: pid_t,
        displayScope: WindowEnumerator.DisplayScope?, observed: (revision: UUID, windowID: CGWindowID?),
        warmList: WindowEnumerator.WindowList, warmFocus: CGWindowID?
    ) -> (list: WindowEnumerator.WindowList, focusedWindowID: CGWindowID?)? {
        let tracker = WindowUseTracker.shared
        let ids = Set(remembered.items.lazy.filter { $0.pid == appPID }.compactMap(\.windowID))
        if let id = observed.windowID, !ids.contains(id), newWindows[id] == nil {
            newWindows[id] = NewWindow(appPID: appPID, ownerPID: frontPID, focusRevision: observed.revision)
        }
        let notices = newWindows.filter { $0.value.appPID == appPID }
        let listed = ids.isSuperset(of: notices.keys)
        let observedIsCurrent = observed.windowID != nil && notices.allSatisfy { id, notice in
            id == observed.windowID || notice.focusRevision != observed.revision
        }

        func selected(_ source: CGWindowID?, list: WindowEnumerator.WindowList,
                      consumeNotices: Bool = true) -> (WindowEnumerator.WindowList, CGWindowID?) {
            if consumeNotices {
                for id in notices.keys { newWindows.removeValue(forKey: id) }
            }
            sourceCheck = nil
            emptySelectionRefresh = nil
            titles.refreshUnobserved(in: list.items, accessibilityGranted: Permissions.shared.accessibility)
            return (list, source)
        }
        // If discovery ruled out the front app, resume immediately from the same inventory.
        let warmSourceIsKnown = listed && (ids.count == 1 || (observedIsCurrent && warmFocus == observed.windowID))
        if pendingWindowIDs.isEmpty, notices.isEmpty || warmSourceIsKnown,
           (sourceCheck?.attempts ?? 0) == 0, tracker.focusRevision == observed.revision {
            return selected(warmFocus, list: warmList)
        }
        let check: SourceCheck
        if let sourceCheck { check = sourceCheck }
        else {
            check = SourceCheck(generation: generation, appPID: appPID, frontPID: frontPID)
            sourceCheck = check
            DispatchQueue.main.asyncAfter(deadline: check.deadline) { [weak self, weak check] in
                guard let self, let check, self.sourceCheck === check else { return }
                check.expired = true
                check.queued = false
                self.onReady?([])
                if self.sourceCheck === check { self.sourceCheck = nil }
            }
        }
        func discard() -> (WindowEnumerator.WindowList, CGWindowID?) {
            sourceCheck = nil
            return (WindowEnumerator.WindowList(items: [], sourceItems: []), nil)
        }
        guard !check.expired, DispatchTime.now() < check.deadline else { return discard() }
        guard pendingWindowIDs.isEmpty, !check.reading, !check.queued else { return nil }

        // A focus event identifies the source directly. A creation needs the front app's current AX focus.
        let source: CGWindowID?
        if observedIsCurrent || (check.answer != nil && check.answer?.revision != observed.revision) {
            source = observed.windowID
        } else {
            source = check.answer?.windowID
        }
        if listed, let source, remembered.items.contains(where: {
            $0.pid == appPID && $0.windowID == source && $0.isOnScreen && !$0.isMinimized
        }) {
            let list = SwitcherWindowSelection.select(remembered: remembered, scope: .frontmostApp,
                                                       frontmostPID: frontPID, focusedWindowID: source, displayScope: displayScope)
            if list.sourceItems.contains(where: { $0.windowID == source }),
               tracker.focusRevision == observed.revision {
                if source != observed.windowID,
                   tracker.recordObservedFocus(windowID: source, pid: frontPID, ifRevision: observed.revision) == nil {
                    // The observer may not yet be attached to the original app. The live AX
                    // result is still usable unless a newer focus arrived while selecting.
                    guard tracker.focusRevision == observed.revision else { return discard() }
                    return selected(source, list: list, consumeNotices: false)
                }
                return selected(source, list: list)
            }
        }
        guard check.attempts < 2 else {
            // Discard this shortcut. An unverified owner or an excluded surface should not
            // block later shortcuts once both scoped attempts have examined the notice.
            for (id, notice) in notices where !ids.contains(id) && observed.windowID != id {
                let otherFocus = source.map { ids.contains($0) } == true
                let excluded = remembered.observedWindowIDs.contains(id) || notice.focusRevision != observed.revision
                if notice.ownerPID == nil || (otherFocus && excluded) {
                    newWindows.removeValue(forKey: id)
                    focusNotices.removeAll { $0.id == id }
                }
            }
            recordDiscoveredFocus()
            return discard()
        }
        check.needsAXFocus = !observedIsCurrent
        check.queued = true
        refresh()
        return nil
    }

    func sourceCheckExpired(for generation: UInt64) -> Bool {
        guard let check = sourceCheck, check.generation == generation,
              check.expired || DispatchTime.now() >= check.deadline else { return false }
        sourceCheck = nil
        return true
    }

    private func confirmedEmptySelection(for generation: UInt64) -> Bool {
        let isFollowup = emptySelectionRefresh?.generation == generation
        if let request = emptySelectionRefresh, isFollowup {
            // If a window event overtook the scan, include the work already known
            // at its return. Later background traffic cannot prolong this request.
            if request.isFollowup || (pendingWindowIDs.isEmpty && pendingPIDs.isEmpty && !needsFullRefresh) {
                return true
            }
        }
        // The shortcut can beat even the notification that introduces a new window.
        let discoveries = isFollowup ? pendingWindowIDs : []
        emptySelectionRefresh = EmptySelectionRefresh(generation: generation, isFollowup: isFollowup,
                                                     discoveries: discoveries)
        if discoveries.isEmpty { invalidate() }
        return false
    }

    func contains(_ item: SwitcherItem) -> Bool {
        SwitcherWindowSelection.contains(item, in: remembered.items)
    }

    /// The shortcut can precede the workspace notification for its new Space.
    func readyForSession(currentSpaceOnly: Bool) -> Bool {
        if currentSpaceOnly { checkSpaces(notified: false) }
        return isReady
    }

    private func checkSpaces(notified: Bool) {
        guard spaces.changed(to: SpaceWindowBridge.topology()?.visibleSpaces, notified: notified) else { return }
        isReady = false
        needsFullRefresh = true
        pendingRefresh?.cancel()
        pendingRefresh = nil
        refresh()
    }

    func invalidate(pid: pid_t? = nil) {
        guard lifetime != nil else { return }
        if let pid {
            let appPID = remembered.items.first { $0.windowOwnerPID == pid }?.pid ?? pid
            pendingPIDs.insert(appPID)
        }
        else { needsFullRefresh = true }
        guard !refreshInFlight else { return }
        invalidatePendingRefresh()
    }

    private func receive(_ event: SwitcherWindowEvents.Event) {
        let windowID: CGWindowID
        switch event {
        case .spacesChanged:
            checkSpaces(notified: true)
            return
        case .membershipChanged:
            invalidate()
            return
        case .changed(let id), .destroyed(let id), .focused(let id):
            windowID = id
        }
        guard windowID != kCGNullWindowID, !NSApp.windows.contains(where: { SwitcherWindowEvents.matchesWindowNumber($0.windowNumber, windowID: windowID) }) else {
            return
        }
        let item = remembered.items.first { $0.windowID == windowID }
        switch event {
        case .focused:
            if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                focusNotices.removeAll { $0.id == windowID }
                focusNotices.append(FocusNotice(id: windowID, pid: frontPID, revision: WindowUseTracker.shared.focusRevision))
            }
            if item == nil { discover(windowID) }
            recordDiscoveredFocus()
        case .destroyed:
            pendingWindowIDs.remove(windowID)
            newWindows.removeValue(forKey: windowID)
            focusNotices.removeAll { $0.id == windowID }
            WindowUseTracker.shared.removeWindow(windowID)
            recordDiscoveredFocus()
            destroyedDuringRefresh.insert(windowID)
            remembered.items.removeAll { $0.windowID == windowID }
            remembered.observedWindowIDs.remove(windowID)
            if let item { invalidate(pid: item.pid) }
        case .changed:
            if let item { invalidate(pid: item.pid) }
            else { discover(windowID) }
        case .spacesChanged, .membershipChanged:
            break
        }
    }

    // Discovery runs on a serial queue, but a later focus can already have a known owner.
    // Apply the notifications in arrival order. An intervening AX focus or activation wins.
    private func recordDiscoveredFocus() {
        while let notice = focusNotices.first, !pendingWindowIDs.contains(notice.id) {
            let known = remembered.items.first { $0.windowID == notice.id }
            let found = newWindows[notice.id]
            if let found, found.ownerPID == nil, known == nil, focusNotices.count == 1,
               WindowUseTracker.shared.focusRevision == notice.revision {
                // A scoped walk may still identify this window. A subsequent notification
                // with a known owner must continue to update history in the meantime.
                return
            }
            focusNotices.removeFirst()
            guard known?.pid == notice.pid || known?.windowOwnerPID == notice.pid
                    || (found?.ownerPID != nil && found?.appPID == notice.pid) || found?.ownerPID == notice.pid,
                  let revision = WindowUseTracker.shared.recordObservedFocus(windowID: notice.id, pid: notice.pid,
                                                                            ifRevision: notice.revision) else { continue }
            for index in focusNotices.indices where focusNotices[index].revision == notice.revision {
                focusNotices[index].revision = revision
            }
        }
    }

    private func discover(_ windowID: CGWindowID) {
        guard let generation = lifetime, pendingWindowIDs.insert(windowID).inserted else { return }
        let revision = WindowUseTracker.shared.focusRevision
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        discoveryQueue.async { [weak self] in
            guard let self, self.lifetimeLock.withLock({ self.lifetime == generation }) else { return }
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
            let window = info?.first
            let owner = (window?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (window?[kCGWindowLayer as String] as? NSNumber)?.intValue
            let appPID = owner.flatMap { pid -> pid_t? in
                guard layer == 0, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
                return WindowEnumerator.appPID(forWindowOwner: pid, runningApps: WindowEnumerator.runningApplications())
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifetime == generation else { return }
                let stillPending = self.pendingWindowIDs.remove(windowID) != nil
                if self.emptySelectionRefresh?.discoveries.remove(windowID) != nil,
                   self.emptySelectionRefresh?.discoveries.isEmpty == true {
                    self.invalidate()
                }
                if stillPending && !self.destroyedDuringRefresh.contains(windowID) {
                    if let owner, layer == 0, owner != ProcessInfo.processInfo.processIdentifier {
                        let host = appPID ?? self.remembered.items.first { $0.windowOwnerPID == owner }?.pid
                        if let host {
                            self.newWindows[windowID] = NewWindow(appPID: host, ownerPID: owner, focusRevision: revision)
                        } else if host == nil, let frontPID {
                            self.newWindows[windowID] = NewWindow(appPID: frontPID, ownerPID: nil, focusRevision: revision)
                        }
                        self.invalidate(pid: host)
                    } else if (layer == nil || layer == 0), owner != ProcessInfo.processInfo.processIdentifier, let frontPID {
                        // No description yet. Only a verified different owner rules the front app out.
                        self.newWindows[windowID] = NewWindow(appPID: frontPID, ownerPID: nil, focusRevision: revision)
                    }
                }
                self.recordDiscoveredFocus()
                if self.sourceCheck != nil { self.onReady?([]) }
            }
        }
    }

    private func remove(pid: pid_t) {
        newWindows = newWindows.filter { $0.value.appPID != pid && $0.value.ownerPID != pid }
        focusNotices.removeAll { $0.pid == pid }
        terminatedDuringRefresh.insert(pid)
        let removed = remembered.items.filter { $0.pid == pid || $0.windowOwnerPID == pid }
        let affectedPIDs = Set(removed.map(\.pid))
        remembered.items.removeAll { $0.pid == pid || $0.windowOwnerPID == pid }
        for item in removed {
            if let windowID = item.windowID {
                destroyedDuringRefresh.insert(windowID)
                remembered.observedWindowIDs.remove(windowID)
            }
        }
        for affectedPID in affectedPIDs { invalidate(pid: affectedPID) }
    }

    private func refresh() {
        guard let generation = lifetime, !refreshInFlight,
              sourceCheck?.queued == true || needsFullRefresh || !pendingPIDs.isEmpty else { return }
        pendingRefresh?.cancel()
        pendingRefresh = nil
        let spaceRevision = spaces.revision
        let sessionRefresh = emptySelectionRefresh
        let check = sourceCheck.flatMap { $0.queued ? $0 : nil }
        let pids: Set<pid_t>?
        let focusPID = check.flatMap { $0.needsAXFocus ? $0.frontPID : nil }
        if let check {
            pids = [check.appPID]
            pendingPIDs.remove(check.appPID)
            check.queued = false
            check.reading = true
            check.attempts += 1
        } else {
            pids = needsFullRefresh ? nil : pendingPIDs
            needsFullRefresh = false
            pendingPIDs = []
        }
        destroyedDuringRefresh = []
        terminatedDuringRefresh = []
        refreshInFlight = true
        let appKitSnapshot = WindowEnumerator.snapshot(includingRunningApps: false)
        let isCancelled: () -> Bool = { [weak self] in
            guard let self else { return true }
            return self.lifetimeLock.withLock { self.lifetime != generation }
        }
        queue.async { [weak self] in
            guard !isCancelled() else { return }
            let snapshot = WindowEnumerator.Snapshot(
                accessibilityGranted: appKitSnapshot.accessibilityGranted,
                runningApps: WindowEnumerator.runningApplications(),
                ownWindowTitles: appKitSnapshot.ownWindowTitles,
                screenFrames: appKitSnapshot.screenFrames,
                displayIDsByUUID: appKitSnapshot.displayIDsByUUID)
            let result: WindowEnumerator.WindowList
            if let pids {
                var combined = WindowEnumerator.WindowList(items: [], sourceItems: [])
                for pid in pids {
                    guard !isCancelled() else { return }
                    let part = WindowEnumerator.rememberSwitcherWindows(snapshot: snapshot, filterPID: pid,
                                                                       includingNewHelpers: check != nil, isCancelled: isCancelled)
                    combined.items += part.items.filter { $0.pid == pid }
                    combined.bundleIdentifiers.merge(part.bundleIdentifiers) { _, new in new }
                    combined.nativeFullscreenWindowIDs.formUnion(part.nativeFullscreenWindowIDs)
                    combined.observedWindowIDs.formUnion(part.observedWindowIDs)
                    combined.accessibilityElements.merge(part.accessibilityElements) { _, new in new }
                    combined.activationSnapshot = part.activationSnapshot
                }
                result = combined
            } else {
                result = WindowEnumerator.rememberSwitcherWindows(snapshot: snapshot, isCancelled: isCancelled)
            }
            let answer = check.map { _ in
                let revision = WindowUseTracker.shared.focusRevision
                let focus = focusPID.flatMap { WindowActivator.focusedWindowID(for: $0) }
                return (windowID: focus, revision: revision)
            }
            DispatchQueue.main.async {
                guard let self, !isCancelled() else { return }
                self.refreshInFlight = false
                check?.reading = false
                guard self.spaces.revision == spaceRevision else {
                    self.refresh()
                    return
                }
                if pids == nil, let sessionRefresh, sessionRefresh.discoveries.isEmpty,
                   self.emptySelectionRefresh == sessionRefresh {
                    self.emptySelectionRefresh?.completed = true
                }
                if let check, self.sourceCheck === check { check.answer = answer }
                self.adopt(result, replacing: pids)
                if self.sourceCheck?.queued == true { self.refresh() }
                if self.needsFullRefresh || !self.pendingPIDs.isEmpty { self.invalidatePendingRefresh() }
            }
        }
    }

    private func invalidatePendingRefresh() {
        guard let generation = lifetime, !refreshInFlight, pendingRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lifetime == generation else { return }
            self.pendingRefresh = nil
            self.refresh()
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func adopt(_ result: WindowEnumerator.WindowList, replacing pids: Set<pid_t>?) {
        var updated = result
        updated.items.removeAll { item in
            terminatedDuringRefresh.contains(item.pid) || terminatedDuringRefresh.contains(item.windowOwnerPID)
                || item.windowID.map { destroyedDuringRefresh.contains($0) } == true
        }
        let refreshedItems = updated.items
        if let pids {
            let retained = remembered.items.filter { !pids.contains($0.pid) }
            updated.items = retained + updated.items
            updated.bundleIdentifiers = remembered.bundleIdentifiers.merging(updated.bundleIdentifiers) { _, new in new }
            let retainedIDs = Set(retained.compactMap(\.windowID))
            updated.observedWindowIDs.formUnion(retainedIDs)
            updated.nativeFullscreenWindowIDs.formUnion(remembered.nativeFullscreenWindowIDs.intersection(retainedIDs))
            updated.accessibilityElements.merge(remembered.accessibilityElements.filter { retainedIDs.contains($0.key) }) { new, _ in new }
        }
        let currentIDs = Set(updated.items.compactMap(\.windowID))
        updated.accessibilityElements = updated.accessibilityElements.filter { currentIDs.contains($0.key) }
        remembered = updated
        for item in refreshedItems {
            if let id = item.windowID, let note = newWindows[id], note.ownerPID == nil, note.appPID != item.pid {
                newWindows.removeValue(forKey: id)
            }
        }
        recordDiscoveredFocus()
        let watching = SwitcherWindowEvents.shared.watch(updated.observedWindowIDs.subtracting(destroyedDuringRefresh))
        setFallbackPolling(!observesWindowEvents || !watching)
        titles.update(updated.accessibilityElements)
        isReady = true
        onReady?(refreshedItems)
    }
}
