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
    private struct SourceFocus: Equatable {
        let pid: pid_t
        let windowID: CGWindowID?
        let revision: UUID
        let confirmed: Bool
    }

    private struct SelectionRefresh: Equatable {
        let generation: UInt64
        let isFollowup: Bool
        var discoveries: Set<CGWindowID>
        let sourcePID: pid_t?
        let previousFocus: SourceFocus?
        let focusRevision: UUID
        var focusedWindowID: CGWindowID?
        var completed = false

        func resolveFocus(in items: [SwitcherItem]) -> CGWindowID? {
            guard let sourcePID else { return nil }
            if let id = focusedWindowID {
                if let item = items.first(where: { $0.windowID == id }) {
                    if item.pid == sourcePID || item.windowOwnerPID == sourcePID { return id }
                } else if !isFollowup {
                    // Keep the reported focus for the retry if the first scan still predates its window.
                    return id
                }
            }
            // Creation alone does not identify the focused window. This AX read runs on the inventory queue.
            return WindowActivator.focusedWindowID(for: sourcePID)
        }
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
    private var selectionRefresh: SelectionRefresh?
    private var pendingPIDs: Set<pid_t> = []
    private var pendingWindowIDs: Set<CGWindowID> = []
    // Owner discovery can finish before the new window or its focus reaches the inventory.
    private var newWindowByApp: [pid_t: CGWindowID] = [:]
    private var sourceFocus: SourceFocus?
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
        selectionRefresh = nil
        pendingPIDs = []
        pendingWindowIDs = []
        newWindowByApp = [:]
        sourceFocus = nil
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
        // An older scan may publish while this shortcut's confirmation is queued.
        let request = selectionRefresh.flatMap { $0.generation == generation ? $0 : nil }
        if let request, !request.completed { return nil }
        let appPID = SwitcherSupport.appPID(forFrontmost: frontmostPID, items: remembered.items)
        let tracker = WindowUseTracker.shared
        let evidence = sourceFocus.flatMap {
            $0.pid == frontmostPID && $0.revision == tracker.historyRevision ? $0 : nil
        }
        let reported = evidence?.windowID ?? tracker.focusedWindowID(for: frontmostPID)
        let sourceID = request?.focusedWindowID ?? reported
        func visibleSource(_ id: CGWindowID) -> Bool {
            remembered.items.contains { $0.windowID == id && $0.pid == appPID && $0.isOnScreen && !$0.isMinimized }
        }
        let focused = sourceID.flatMap { visibleSource($0) ? $0 : nil } ?? tracker.windows.first(where: visibleSource)
        let list = SwitcherWindowSelection.select(
            remembered: remembered,
            scope: scope,
            frontmostPID: frontmostPID,
            focusedWindowID: focused,
            displayScope: displayScope)
        let newWindow = newWindowByApp[appPID]
        let missingFocus: CGWindowID? = sourceID.flatMap { id in remembered.items.contains { $0.windowID == id } ? nil : id }
        let needsFocusCheck = missingFocus != nil && (request != nil || evidence?.confirmed != true)
        let sourceMayBeMissing = !pendingWindowIDs.isEmpty || needsFocusCheck
            || (newWindow != nil && newWindow != focused)
        if list.items.isEmpty || sourceMayBeMissing {
            guard confirmedSelection(for: generation, previous: request, sourcePID: sourceMayBeMissing ? frontmostPID : nil,
                                     reportedFocus: missingFocus) else { return nil }
        }
        if let newWindow, newWindow == focused {
            newWindowByApp.removeValue(forKey: appPID)
        }
        selectionRefresh = nil
        titles.refreshUnobserved(in: list.items, accessibilityGranted: Permissions.shared.accessibility)
        return (list, focused)
    }

    private func confirmedSelection(for generation: UInt64, previous: SelectionRefresh?,
                                    sourcePID: pid_t?, reportedFocus: CGWindowID?) -> Bool {
        if let previous {
            // If a window event overtook the scan, include the work already known
            // at its return. Later background traffic cannot prolong this request.
            let caughtUp = reportedFocus == nil && pendingWindowIDs.isEmpty && pendingPIDs.isEmpty && !needsFullRefresh
            if previous.isFollowup || caughtUp {
                return true
            }
        }
        // The shortcut can beat even the notification that introduces a new window.
        let discoveries = previous != nil ? pendingWindowIDs : []
        selectionRefresh = SelectionRefresh(generation: generation, isFollowup: previous != nil,
                                           discoveries: discoveries, sourcePID: sourcePID,
                                           previousFocus: previous == nil ? sourceFocus : previous?.previousFocus,
                                           focusRevision: previous?.focusRevision ?? WindowUseTracker.shared.historyRevision,
                                           focusedWindowID: reportedFocus)
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
        guard !NSApp.windows.contains(where: { SwitcherWindowEvents.matchesWindowNumber($0.windowNumber, windowID: windowID) }) else {
            return
        }
        let item = remembered.items.first { $0.windowID == windowID }
        switch event {
        case .focused:
            sourceFocus = nil
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if let item, let frontPID,
               item.pid == frontPID || item.windowOwnerPID == frontPID {
                WindowUseTracker.shared.recordObservedFocus(windowID: windowID, pid: frontPID)
            } else if item == nil {
                if let frontPID {
                    sourceFocus = SourceFocus(pid: frontPID, windowID: windowID,
                                              revision: WindowUseTracker.shared.historyRevision, confirmed: false)
                }
                discover(windowID)
            }
        case .destroyed:
            if sourceFocus?.windowID == windowID { sourceFocus = nil }
            newWindowByApp = newWindowByApp.filter { $0.value != windowID }
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
        guard let generation = lifetime, pendingWindowIDs.insert(windowID).inserted else { return }
        discoveryQueue.async { [weak self] in
            guard let self, self.lifetimeLock.withLock({ self.lifetime == generation }) else { return }
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
            let window = info?.first
            let owner = (window?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let layer = (window?[kCGWindowLayer as String] as? NSNumber)?.intValue
            let regular = owner.flatMap { NSRunningApplication(processIdentifier: $0) }?.activationPolicy == .regular
            DispatchQueue.main.async { [weak self] in
                guard let self, self.lifetime == generation else { return }
                self.pendingWindowIDs.remove(windowID)
                if self.selectionRefresh?.discoveries.remove(windowID) != nil,
                   self.selectionRefresh?.discoveries.isEmpty == true {
                    self.invalidate()
                }
                guard layer == 0, let owner, owner != ProcessInfo.processInfo.processIdentifier else { return }
                let appPID = SwitcherSupport.appPID(forFrontmost: owner, items: self.remembered.items)
                self.newWindowByApp[appPID] = windowID
                self.invalidate(pid: regular ? owner : nil)
            }
        }
    }

    private func remove(pid: pid_t) {
        newWindowByApp.removeValue(forKey: pid)
        if sourceFocus?.pid == pid { sourceFocus = nil }
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
              needsFullRefresh || !pendingPIDs.isEmpty else { return }
        pendingRefresh = nil
        let spaceRevision = spaces.revision
        let pids = needsFullRefresh ? nil : pendingPIDs
        let sessionRefresh = selectionRefresh.flatMap {
            pids == nil && !$0.completed && $0.discoveries.isEmpty ? $0 : nil
        }
        let sourceApp = sessionRefresh?.sourcePID.map { SwitcherSupport.appPID(forFrontmost: $0, items: remembered.items) }
        let newWindow = sourceApp.flatMap { newWindowByApp[$0] }
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
                    combined.activationSnapshot = part.activationSnapshot
                }
                result = combined
            } else {
                result = WindowEnumerator.rememberSwitcherWindows(snapshot: snapshot, isCancelled: isCancelled)
            }
            let focus = sessionRefresh?.resolveFocus(in: result.items)
            DispatchQueue.main.async {
                guard let self, !isCancelled() else { return }
                self.refreshInFlight = false
                guard self.spaces.revision == spaceRevision else {
                    self.refresh()
                    return
                }
                if let sessionRefresh, self.selectionRefresh == sessionRefresh {
                    self.selectionRefresh?.completed = true
                    self.selectionRefresh?.focusedWindowID = focus
                    if let pid = sessionRefresh.sourcePID {
                        let examinedFocus = focus == nil || result.items.contains { $0.windowID == focus }
                        if (examinedFocus || sessionRefresh.isFollowup), self.sourceFocus == sessionRefresh.previousFocus,
                           WindowUseTracker.shared.historyRevision == sessionRefresh.focusRevision {
                            self.sourceFocus = SourceFocus(pid: pid, windowID: focus,
                                                          revision: sessionRefresh.focusRevision, confirmed: true)
                        }
                        if let sourceApp, self.newWindowByApp[sourceApp] == newWindow {
                            self.newWindowByApp.removeValue(forKey: sourceApp)
                        }
                    }
                }
                self.adopt(result, replacing: pids)
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
        let watching = SwitcherWindowEvents.shared.watch(updated.observedWindowIDs.subtracting(destroyedDuringRefresh))
        setFallbackPolling(!observesWindowEvents || !watching)
        titles.update(updated.accessibilityElements)
        isReady = true
        onReady?(refreshedItems)
    }
}
