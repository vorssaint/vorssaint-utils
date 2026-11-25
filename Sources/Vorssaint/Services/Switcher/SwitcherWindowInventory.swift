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
    /// Group selection can finish before the source app's announced windows arrive.
    /// Keep the history entry addressable until those particular discoveries finish.
    final class GroupedSource {
        let request: WindowFocusHistory.Request
        let representative: SwitcherItem
        fileprivate(set) var confirmed: SwitcherItem?
        fileprivate var observedWindowID: CGWindowID?
        fileprivate var discoveries: [UUID: CGWindowID]
        var awaitsDiscovery: Bool { !discoveries.isEmpty }
        var pendingRequest: WindowFocusHistory.Request? { awaitsDiscovery || observedWindowID != nil ? request : nil }

        fileprivate init(representative: SwitcherItem, frontmostPID: pid_t, discoveries: [UUID: CGWindowID]) {
            request = .init(pid: representative.pid, focusPID: frontmostPID)
            self.representative = representative
            self.discoveries = discoveries
        }

        fileprivate func confirm(in items: [SwitcherItem], axFocus: CGWindowID?, tickets: Set<UUID>) {
            let discoveredFocus = axFocus.flatMap { id in tickets.contains { discoveries[$0] == id } ? id : nil }
            for id in [observedWindowID, discoveredFocus].compactMap({ $0 }) {
                guard let focus = items.first(where: {
                    $0.windowID == id && $0.pid == request.pid && $0.isOnScreen && !$0.isMinimized
                }), let previous = representative.windowID else { continue }
                WindowUseTracker.shared.confirmSwitchSource(id, replacing: previous, for: request)
                confirmed = focus
                observedWindowID = nil
                discoveries = [:]
                return
            }
        }
    }

    private struct EmptySelectionRefresh: Equatable {
        let generation: UInt64
        let isFollowup: Bool
        var discoveries: Set<CGWindowID>
        var completed = false
    }

    private struct FocusProbe: Equatable {
        let frontmostPID: pid_t
        let confirmation: UUID
        let spaceRevision: Int
    }

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
    private var pendingWindowIDs: [CGWindowID: UUID] = [:]
    private var discoveriesForRefresh: [UUID: CGWindowID] = [:]
    private var unlistedFocus: (ticket: UUID, frontmostPID: pid_t, observation: UUID?)?
    private var lastFocusProbe: FocusProbe?
    private var groupedSources: [pid_t: GroupedSource] = [:]
    private var discoveryWait: (tickets: Set<UUID>, isPending: () -> Bool, resume: () -> Void)?
    private var destroyedDuringRefresh: Set<CGWindowID> = []
    private var terminatedDuringRefresh: Set<pid_t> = []
    private let lifetimeLock = NSLock()
    private var lifetime: UUID?
    private let queue = DispatchQueue(label: "com.vorssaint.switcher.inventory", qos: .userInitiated)
    private let discoveryQueue = DispatchQueue(label: "com.vorssaint.switcher.discovery", qos: .utility)
    private let titles = SwitcherWindowTitles()

    var onReady: (([SwitcherItem]) -> Void)?
    enum Removal: Hashable {
        case window(CGWindowID)
        case process(pid_t)

        func matches(windowID: CGWindowID?, pid: pid_t, ownerPID: pid_t?) -> Bool {
            switch self {
            case .window(let id): return windowID == id
            case .process(let exited): return pid == exited || ownerPID == exited
            }
        }

        func removes(_ item: SwitcherItem) -> Bool {
            matches(windowID: item.windowID, pid: item.pid, ownerPID: item.windowOwnerPID)
        }
    }

    var onRemoval: ((Removal) -> Void)?
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
                    if name == NSWorkspace.didActivateApplicationNotification {
                        self.unlistedFocus = nil
                        self.groupedSources.removeValue(forKey: app.processIdentifier)
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
        pendingPIDs = []
        pendingWindowIDs = [:]
        discoveriesForRefresh = [:]
        unlistedFocus = nil
        lastFocusProbe = nil
        groupedSources = [:]
        discoveryWait = nil
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
        displayScope: WindowEnumerator.DisplayScope?,
        confirmedFocus: CGWindowID? = nil
    ) -> (list: WindowEnumerator.WindowList, focusedWindowID: CGWindowID?)? {
        // An older scan may publish while this shortcut's confirmation is queued.
        if let request = emptySelectionRefresh, request.generation == generation, !request.completed { return nil }
        let appPID = SwitcherSupport.appPID(forFrontmost: frontmostPID, items: remembered.items)
        let focused = confirmedFocus ?? WindowUseTracker.shared.windows.first { id in
            remembered.items.contains { $0.windowID == id && $0.pid == appPID && $0.isOnScreen && !$0.isMinimized }
        }
        let list = SwitcherWindowSelection.select(
            remembered: remembered,
            scope: scope,
            frontmostPID: frontmostPID,
            focusedWindowID: focused,
            displayScope: displayScope)
        if list.items.isEmpty, !confirmedEmptySelection(for: generation) { return nil }
        emptySelectionRefresh = nil
        titles.refreshUnobserved(in: list.items, accessibilityGranted: Permissions.shared.accessibility)
        return (list, focused)
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
        let discoveries = isFollowup ? Set(pendingWindowIDs.keys) : []
        emptySelectionRefresh = EmptySelectionRefresh(generation: generation, isFollowup: isFollowup,
                                                     discoveries: discoveries)
        if discoveries.isEmpty { invalidate() }
        return false
    }

    var currentSpaceRevision: Int { spaces.revision }

    func groupedSource(frontmostPID: pid_t, representative: SwitcherItem) -> GroupedSource? {
        guard let fallback = representative.windowID else { return nil }
        let tracker = WindowUseTracker.shared
        let hasDiscovery = !pendingWindowIDs.isEmpty || !discoveriesForRefresh.isEmpty
        guard hasDiscovery || tracker.windows.first != fallback else { return nil }
        var discoveries = discoveriesForRefresh
        for (id, ticket) in pendingWindowIDs { discoveries[ticket] = id }
        let focus = tracker.frontAppFocus(for: frontmostPID, appPID: representative.pid)
        let source = GroupedSource(representative: representative, frontmostPID: frontmostPID, discoveries: discoveries)
        if let unlistedFocus, unlistedFocus.frontmostPID == frontmostPID,
           focus.latest?.confirmation == unlistedFocus.observation {
            source.observedWindowID = discoveries[unlistedFocus.ticket]
        } else if let observed = focus.latest, observed.wasObserved, observed.windowID != fallback,
                  focus.windowID == observed.windowID || discoveries.values.contains(observed.windowID) {
            // An unrelated discovery can still be pending when AX has already observed the source.
            source.observedWindowID = observed.windowID
        }
        guard source.pendingRequest != nil else { return nil }
        // onReady can open the session inside the scan that first lists the source.
        source.confirm(in: remembered.items, axFocus: remembered.focusedWindowIDsByOwner[frontmostPID],
                       tickets: Set(discoveriesForRefresh.keys))
        if source.pendingRequest != nil { groupedSources[frontmostPID] = source }
        return source
    }

    /// Wait only for discoveries known at the key press, including a window AX
    /// has already observed. Later notifications cannot extend this wait.
    func afterAnnouncedWindows(frontmostPID: pid_t, isPending: @escaping () -> Bool,
                               resume: @escaping (_ needsFocus: Bool) -> Void) -> Bool {
        // onReady will retry against the first snapshot if there is no discovery to wait for yet.
        guard isReady || !pendingWindowIDs.isEmpty || !discoveriesForRefresh.isEmpty else { return false }
        let appPID = remembered.items.first { $0.windowOwnerPID == frontmostPID || $0.pid == frontmostPID }?.pid
        let focus = WindowUseTracker.shared.frontAppFocus(for: frontmostPID, appPID: appPID)
        if let observed = focus.latest, observed.wasObserved,
           !remembered.items.contains(where: { $0.windowID == observed.windowID }),
           pendingWindowIDs[observed.windowID] == nil, !discoveriesForRefresh.values.contains(observed.windowID) {
            // An excluded inspector can remain focused across shortcut presses.
            let probe = FocusProbe(frontmostPID: frontmostPID, confirmation: observed.confirmation, spaceRevision: spaces.revision)
            if lastFocusProbe != probe {
                lastFocusProbe = probe
                discoveriesForRefresh[UUID()] = observed.windowID
                invalidate(pid: appPID)
            }
        }
        guard !pendingWindowIDs.isEmpty || !discoveriesForRefresh.isEmpty else { return false }
        let ids = Set(pendingWindowIDs.keys).union(discoveriesForRefresh.values)
        let tickets = Set(pendingWindowIDs.values).union(discoveriesForRefresh.keys)
        discoveryWait = (tickets, isPending, { [weak self] in
            guard let self else { return }
            let pid = SwitcherSupport.appPID(forFrontmost: frontmostPID, items: self.remembered.items)
            let newSourceCandidate = self.remembered.items.contains {
                $0.pid == pid && $0.isOnScreen && !$0.isMinimized && $0.windowID.map(ids.contains) == true
            }
            resume(newSourceCandidate && SwitcherSupport.needsFocusedWindowLookup(frontmostPID: frontmostPID,
                                                                                  items: self.remembered.items))
        })
        if pendingRefresh != nil { invalidatePendingRefresh() }
        return true
    }

    private func finishDiscoveries(_ tickets: Set<UUID>) {
        if let focus = unlistedFocus, tickets.contains(focus.ticket) { unlistedFocus = nil }
        for (pid, source) in groupedSources {
            for ticket in tickets { source.discoveries.removeValue(forKey: ticket) }
            if source.pendingRequest == nil { groupedSources.removeValue(forKey: pid) }
        }
        guard var wait = discoveryWait else { return }
        wait.tickets.subtract(tickets)
        if wait.tickets.isEmpty {
            discoveryWait = nil
            wait.resume()
        } else {
            discoveryWait = wait
        }
    }

    var knownWindowIDs: Set<CGWindowID> { Set(remembered.items.compactMap(\.windowID)) }

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
        case .destroyed(let id):
            WindowUseTracker.shared.recordDestroyedWindow(id)
            for source in groupedSources.values where source.observedWindowID == id { source.observedWindowID = nil }
            onRemoval?(.window(id))
            windowID = id
        case .changed(let id), .focused(let id):
            windowID = id
        }
        guard !NSApp.windows.contains(where: { SwitcherWindowEvents.matchesWindowNumber($0.windowNumber, windowID: windowID) }) else {
            return
        }
        let item = remembered.items.first { $0.windowID == windowID }
        switch event {
        case .focused:
            unlistedFocus = nil
            if let item,
               let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               item.pid == frontPID || item.windowOwnerPID == frontPID {
                WindowUseTracker.shared.recordObservedFocus(windowID: windowID, pid: frontPID)
            } else if item == nil {
                discover(windowID)
                if let ticket = pendingWindowIDs[windowID],
                   let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    unlistedFocus = (ticket, pid, WindowUseTracker.shared.frontAppFocus(for: pid).latest?.confirmation)
                }
            }
        case .destroyed:
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

    private func discover(_ windowID: CGWindowID) {
        guard let generation = lifetime, pendingWindowIDs[windowID] == nil else { return }
        let ticket = UUID()
        pendingWindowIDs[windowID] = ticket
        discoveryQueue.async { [weak self] in
            guard let self, self.lifetimeLock.withLock({ self.lifetime == generation }) else { return }
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
            let window = info?.first
            let owner = (window?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (window?[kCGWindowLayer as String] as? NSNumber)?.intValue
            let regular = owner.flatMap { NSRunningApplication(processIdentifier: $0) }?.activationPolicy == .regular
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifetime == generation else { return }
                self.pendingWindowIDs.removeValue(forKey: windowID)
                if self.emptySelectionRefresh?.discoveries.remove(windowID) != nil,
                   self.emptySelectionRefresh?.discoveries.isEmpty == true {
                    self.invalidate()
                }
                guard layer == 0, let owner, owner != ProcessInfo.processInfo.processIdentifier else {
                    self.finishDiscoveries([ticket])
                    return
                }
                self.discoveriesForRefresh[ticket] = windowID
                self.invalidate(pid: regular ? owner : nil)
            }
        }
    }

    private func remove(pid: pid_t) {
        groupedSources = groupedSources.filter { !$0.value.request.involves(pid) }
        onRemoval?(.process(pid))
        terminatedDuringRefresh.insert(pid)
        recordTerminatedWindows(of: pid, in: remembered)
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

    private func recordTerminatedWindows(of pid: pid_t, in list: WindowEnumerator.WindowList) {
        // CG may already know the owner before AX lists its window. AX-only windows live in items.
        var ids = list.activationSnapshot?.windowIDsByOwner[pid] ?? []
        for item in list.items where item.windowOwnerPID == pid {
            if let id = item.windowID { ids.insert(id) }
        }
        for id in ids { WindowUseTracker.shared.recordDestroyedWindow(id) }
    }

    private func refresh() {
        guard let generation = lifetime, !refreshInFlight,
              needsFullRefresh || !pendingPIDs.isEmpty else { return }
        pendingRefresh = nil
        let spaceRevision = spaces.revision
        let sessionRefresh = emptySelectionRefresh
        let discoveries = Set(discoveriesForRefresh.keys)
        let pids = needsFullRefresh ? nil : pendingPIDs
        needsFullRefresh = false
        pendingPIDs = []
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
                    let part = WindowEnumerator.rememberSwitcherWindows(snapshot: snapshot, filterPID: pid, isCancelled: isCancelled)
                    combined.items += part.items.filter { $0.pid == pid }
                    combined.bundleIdentifiers.merge(part.bundleIdentifiers) { _, new in new }
                    combined.nativeFullscreenWindowIDs.formUnion(part.nativeFullscreenWindowIDs)
                    combined.observedWindowIDs.formUnion(part.observedWindowIDs)
                    combined.accessibilityElements.merge(part.accessibilityElements) { _, new in new }
                    combined.focusedWindowIDsByOwner.merge(part.focusedWindowIDsByOwner) { _, new in new }
                    combined.activationSnapshot = part.activationSnapshot
                }
                result = combined
            } else {
                result = WindowEnumerator.rememberSwitcherWindows(snapshot: snapshot, isCancelled: isCancelled)
            }
            DispatchQueue.main.async {
                guard let self, !isCancelled() else { return }
                self.refreshInFlight = false
                for pid in self.terminatedDuringRefresh { self.recordTerminatedWindows(of: pid, in: result) }
                guard self.spaces.revision == spaceRevision else {
                    self.refresh()
                    return
                }
                if pids == nil, let sessionRefresh, sessionRefresh.discoveries.isEmpty,
                   self.emptySelectionRefresh == sessionRefresh {
                    self.emptySelectionRefresh?.completed = true
                }
                // onReady can be the shortcut's first turn on main, before its queued key handler.
                self.adopt(result, replacing: pids, discoveries: discoveries)
                for ticket in discoveries { self.discoveriesForRefresh.removeValue(forKey: ticket) }
                self.finishDiscoveries(discoveries)
                if self.needsFullRefresh || !self.pendingPIDs.isEmpty { self.invalidatePendingRefresh() }
            }
        }
    }

    private func invalidatePendingRefresh() {
        guard let generation = lifetime, !refreshInFlight else { return }
        // A press waiting on this scan need not pay the background coalescing delay.
        if let wait = discoveryWait, wait.tickets.isDisjoint(with: pendingWindowIDs.values),
           !wait.tickets.isDisjoint(with: discoveriesForRefresh.keys), wait.isPending() {
            pendingRefresh?.cancel()
            pendingRefresh = nil
            refresh()
            return
        }
        guard pendingRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lifetime == generation else { return }
            self.pendingRefresh = nil
            self.refresh()
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func adopt(_ result: WindowEnumerator.WindowList, replacing pids: Set<pid_t>?, discoveries: Set<UUID>) {
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
        updated.focusedWindowIDsByOwner = updated.focusedWindowIDsByOwner.filter { currentIDs.contains($0.value) }
        for (pid, source) in groupedSources {
            source.confirm(in: refreshedItems, axFocus: updated.focusedWindowIDsByOwner[pid], tickets: discoveries)
            if let observed = source.observedWindowID, pids?.contains(source.request.pid) != false,
               result.observedWindowIDs.contains(observed) || discoveries.contains(where: { source.discoveries[$0] == observed }) {
                source.observedWindowID = nil
            }
        }
        remembered = updated
        let watching = SwitcherWindowEvents.shared.watch(updated.observedWindowIDs.subtracting(destroyedDuringRefresh))
        setFallbackPolling(!observesWindowEvents || !watching)
        titles.update(updated.accessibilityElements)
        isReady = true
        onReady?(refreshedItems)
    }
}
