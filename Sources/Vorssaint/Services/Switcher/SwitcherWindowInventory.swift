// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class SwitcherWindowInventory {
    private var remembered = WindowEnumerator.WindowList(items: [], sourceItems: [])
    private var observers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var pendingRefresh: DispatchWorkItem?
    private var refreshInFlight = false
    private var needsFullRefresh = false
    private var pendingPIDs: Set<pid_t> = []
    private var pendingWindowIDs: Set<CGWindowID> = []
    private var destroyedDuringRefresh: Set<CGWindowID> = []
    private var terminatedDuringRefresh: Set<pid_t> = []
    private let lifetimeLock = NSLock()
    private var lifetime: UUID?
    private let queue = DispatchQueue(label: "com.vorssaint.switcher.inventory", qos: .userInitiated)
    private let discoveryQueue = DispatchQueue(label: "com.vorssaint.switcher.discovery", qos: .utility)
    private let titles = SwitcherWindowTitles()

    var onReady: (() -> Void)?
    private(set) var isReady = false

    func start() {
        guard lifetime == nil else { return }
        lifetimeLock.withLock { lifetime = UUID() }
        titles.onChange = { [weak self] pid in self?.invalidate(pid: pid) }
        SwitcherWindowEvents.shared.start { [weak self] event in self?.receive(event) }
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
                } else {
                    self.invalidate()
                }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.invalidate() }
        needsFullRefresh = true
        refresh()
    }

    func stop() {
        lifetimeLock.withLock { lifetime = nil }
        pendingRefresh?.cancel()
        pendingRefresh = nil
        refreshInFlight = false
        needsFullRefresh = false
        pendingPIDs = []
        pendingWindowIDs = []
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        SwitcherWindowEvents.shared.stop()
        titles.stop()
        remembered = WindowEnumerator.WindowList(items: [], sourceItems: [])
        isReady = false
    }

    func selection(
        scope: SwitcherSessionScope,
        frontmostPID: pid_t,
        displayScope: WindowEnumerator.DisplayScope?
    ) -> (list: WindowEnumerator.WindowList, focusedWindowID: CGWindowID?) {
        let appPID = SwitcherSupport.appPID(forFrontmost: frontmostPID, items: remembered.items)
        let focused = WindowUseTracker.shared.windows.first { id in
            remembered.items.contains { $0.windowID == id && $0.pid == appPID && $0.isOnScreen && !$0.isMinimized }
        }
        let list = SwitcherWindowSelection.select(
            remembered: remembered,
            scope: scope,
            frontmostPID: frontmostPID,
            focusedWindowID: focused,
            displayScope: displayScope)
        return (list, focused)
    }

    func contains(_ item: SwitcherItem) -> Bool {
        remembered.items.contains { $0.id == item.id }
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
            if let item,
               let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
               item.pid == frontPID || item.windowOwnerPID == frontPID {
                WindowUseTracker.shared.recordObservedFocus(windowID: windowID, pid: frontPID)
            } else if item == nil {
                discover(windowID)
            }
        case .destroyed:
            destroyedDuringRefresh.insert(windowID)
            remembered.items.removeAll { $0.windowID == windowID }
            remembered.observedWindowIDs.remove(windowID)
            if let item { invalidate(pid: item.pid) }
        case .changed:
            if let item { invalidate(pid: item.pid) }
            else { discover(windowID) }
        case .spacesChanged:
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
                guard layer == 0, let owner, owner != ProcessInfo.processInfo.processIdentifier else { return }
                self.invalidate(pid: regular ? owner : nil)
            }
        }
    }

    private func remove(pid: pid_t) {
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
                    combined.activationSnapshot = part.activationSnapshot
                }
                result = combined
            } else {
                result = WindowEnumerator.rememberSwitcherWindows(snapshot: snapshot, isCancelled: isCancelled)
            }
            DispatchQueue.main.async {
                guard let self, !isCancelled() else { return }
                self.adopt(result, replacing: pids)
                self.refreshInFlight = false
                if self.needsFullRefresh || !self.pendingPIDs.isEmpty { self.invalidatePendingRefresh() }
            }
        }
    }

    private func invalidatePendingRefresh() {
        guard let generation = lifetime else { return }
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lifetime == generation else { return }
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
        if let pids {
            let retained = remembered.items.filter { !pids.contains($0.pid) }
            updated.items = retained + updated.items
            updated.bundleIdentifiers = remembered.bundleIdentifiers.merging(updated.bundleIdentifiers) { _, new in new }
            let retainedIDs = Set(retained.compactMap(\.windowID))
            updated.nativeFullscreenWindowIDs.formUnion(remembered.nativeFullscreenWindowIDs.intersection(retainedIDs))
            updated.accessibilityElements.merge(remembered.accessibilityElements.filter { retainedIDs.contains($0.key) }) { new, _ in new }
        }
        let currentIDs = Set(updated.items.compactMap(\.windowID))
        updated.accessibilityElements = updated.accessibilityElements.filter { currentIDs.contains($0.key) }
        remembered = updated
        SwitcherWindowEvents.shared.watch(updated.observedWindowIDs.subtracting(destroyedDuringRefresh))
        titles.update(updated.accessibilityElements)
        isReady = true
        onReady?()
    }
}
