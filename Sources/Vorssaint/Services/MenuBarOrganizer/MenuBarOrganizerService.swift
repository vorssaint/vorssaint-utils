// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Advanced tools share the hider's dividers rather than installing a second
/// set. Inventory is refreshed only while an editor, drawer or operation needs it.
@MainActor
final class MenuBarOrganizerService: ObservableObject {
    static let shared = MenuBarOrganizerService()
    @Published private(set) var items: [ManagedMenuBarItem] = []
    @Published private(set) var inventoryUnavailable = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var canUndo = false
    @Published private(set) var isRunning = false
    @Published private(set) var canRestoreSpacing = false

    private let provider = MenuBarWindowProvider()
    private let mover = MenuBarItemMover()
    private let appearance = MenuBarAppearanceController()
    private var panel: MenuBarOrganizerPanelController?
    private var operationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var subscriptions: Set<AnyCancellable> = []
    private var editorVisible = false
    private var undo: (id: MenuBarItemIdentity, section: MenuBarOrganizerSection, neighbor: MenuBarItemAnchor?)?
    private var generation: UInt64 = 0
    private var needsIdentityRefresh = true
    private var inventoryRevision: UInt64 = 0
    private var activationRecovery: (state: MenuBarHiderSupport.DisplayState, mayBeDisplaced: Bool)?

    private var text: MenuBarOrganizerStrings { FeatureStrings.menuBarOrganizer(L10n.shared.language) }
    private var hider: MenuBarHiderService { .shared }
    private var enabled: Bool {
        AppFeature.menuBarHider.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderEnabled)
    }

    private init() {
        Permissions.shared.$accessibility.removeDuplicates().sink { [weak self] _ in
            Task { @MainActor in self?.inventoryChanged() }
        }.store(in: &subscriptions)
        Permissions.shared.$screenRecording.removeDuplicates().sink { [weak self] granted in
            Task { @MainActor in
                if !granted { MenuBarItemPreviewProvider.shared.stop() }
                self?.refresh()
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.inventoryChanged() } }
            .store(in: &subscriptions)
        for notification in [NSWorkspace.didLaunchApplicationNotification,
                             NSWorkspace.didTerminateApplicationNotification,
                             NSWorkspace.didWakeNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: notification)
                .sink { [weak self] _ in Task { @MainActor in self?.inventoryChanged() } }
                .store(in: &subscriptions)
        }
        canRestoreSpacing = MenuBarGlobalSpacing.hasSavedValues
    }

    func syncWithPreferences() {
        canRestoreSpacing = MenuBarGlobalSpacing.hasSavedValues
        let hasConflict = !MenuBarOrganizerPolicy.conflictingManagers().isEmpty
        // Decoration is independent of the Accessibility-backed organizer.
        appearance.sync(enabled: enabled && !hasConflict)
        if !AXIsProcessTrusted(), isBusy || panel?.isVisible == true {
            // Read-only inventory can continue, but pending input must stop now.
            stopOperations()
        }
        guard enabled, MenuBarOrganizerPolicy.supportsAdvancedBackend, !hasConflict else {
            stopOperations()
            return
        }
        isRunning = true
        updateRefreshTimer()
        if editorVisible || panel?.isVisible == true { refresh() }
    }

    func stop() {
        appearance.sync(enabled: false)
        stopOperations()
    }

    private func inventoryChanged() {
        inventoryRevision &+= 1
        undo = nil
        canUndo = false
        needsIdentityRefresh = true
        MenuBarItemPreviewProvider.shared.stop()
        syncWithPreferences()
        refresh()
    }

    private func stopOperations() {
        MenuBarItemPreviewProvider.shared.stop()
        generation &+= 1
        isRunning = false
        operationTask?.cancel()
        mover.cancel()
        finishActivationRecovery()
        hider.endOrganizerOperation(resume: false)
        operationTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel?.close()
        panel = nil
        items = []
        undo = nil
        canUndo = false
        isBusy = false
        needsIdentityRefresh = true
        // Never continue a drag after disable or permission loss.
    }

    private func finishActivationRecovery() {
        guard let recovery = activationRecovery else { return }
        activationRecovery = nil
        hider.endOrganizerOperation(resume: false)
        if recovery.mayBeDisplaced {
            // A drag may have reached the server even when verification failed.
            // Keep recovery reachable; never synthesize further input on cancel.
            hider.revealForStatusItemRecovery()
        } else {
            hider.restoreAfterOrganizerActivation(recovery.state)
        }
    }

    func setEditorVisible(_ visible: Bool) {
        editorVisible = visible
        syncWithPreferences()
        if visible { refresh() }
    }

    func refresh() {
        guard isRunning, !isBusy, refreshTask == nil else { return }
        let expected = generation
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == expected { refreshTask = nil } }
            _ = await snapshot(expected: expected)
        }
    }

    private func updateRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard isRunning, editorVisible || panel?.isVisible == true else {
            MenuBarItemPreviewProvider.shared.stop()
            return
        }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.enabled else { self.syncWithPreferences(); return }
                self.refresh()
            }
        }
        timer.tolerance = 0.6
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func checkAccess() throws {
        try Task.checkCancellation()
        guard enabled, isRunning, MenuBarOrganizerPolicy.supportsAdvancedBackend else {
            throw MenuBarItemMoveError.itemUnavailable
        }
        guard AXIsProcessTrusted() else { throw MenuBarItemMoveError.permissionMissing }
        guard MenuBarOrganizerPolicy.conflictingManagers().isEmpty else { throw MenuBarItemMoveError.busy }
    }

    @discardableResult
    private func snapshot(expected: UInt64) async -> MenuBarItemSnapshot? {
        guard !Task.isCancelled, isRunning, enabled else { return nil }
        guard let geometry = await hider.organizerGeometry() else {
            if generation == expected, !Task.isCancelled {
                items = []
                MenuBarItemPreviewProvider.shared.stop()
                inventoryUnavailable = true
                diagnostic("inventory unavailable: separator geometry")
            }
            return nil
        }
        let refreshIdentities = needsIdentityRefresh
        let revision = inventoryRevision
        needsIdentityRefresh = false
        let snapshot = await provider.snapshot(hiddenDivider: geometry.hidden,
                                              alwaysHiddenDividerMidX: geometry.always?.midX,
                                              excludedWindowIDs: geometry.excluded,
                                              refreshIdentities: refreshIdentities)
        guard !Task.isCancelled, generation == expected, inventoryRevision == revision,
              isRunning else { return nil }
        inventoryUnavailable = !snapshot.enumerationSucceeded
        // Failed scans are never used as candidates for input synthesis.
        items = snapshot.enumerationSucceeded ? snapshot.items.filter { MenuBarOrganizerPolicy.validFrame($0.frame) } : []
        if !isBusy, editorVisible || panel?.isVisible == true {
            MenuBarItemPreviewProvider.shared.refresh(editorVisible ? items : items.filter { $0.section != .alwaysHidden })
        }
        diagnostic(snapshot.enumerationSucceeded ? "inventory read: \(items.count) items" : "inventory unavailable: window enumeration")
        return snapshot.enumerationSucceeded ? snapshot : nil
    }

    private func uniqueItem(_ id: MenuBarItemIdentity, allowProtected: Bool = false) throws -> ManagedMenuBarItem {
        guard let item = MenuBarOrganizerPolicy.uniquelyIdentified(id, in: items, allowProtected: allowProtected) else {
            throw MenuBarItemMoveError.itemUnavailable
        }
        return item
    }

    private func run(_ action: @escaping (UInt64) async throws -> Void) {
        guard !isBusy else { message = text.busy; return }
        do { try checkAccess() } catch { report(error); return }
        refreshTask?.cancel()
        refreshTask = nil
        needsIdentityRefresh = true // Revalidate identities once before new input.
        isBusy = true // Reserve before scheduling so rapid drops cannot overlap.
        hider.beginOrganizerOperation()
        message = nil
        let expected = generation
        operationTask = Task { [weak self] in
            guard let self else { return }
            var completed = false
            defer {
                if generation == expected {
                    hider.endOrganizerOperation(resume: completed)
                    isBusy = false
                    operationTask = nil
                    updateRefreshTimer()
                }
            }
            do { try await action(expected); completed = true }
            catch is CancellationError { }
            catch { if generation == expected { report(error) } }
        }
    }

    func move(id: MenuBarItemIdentity, before target: MenuBarItemIdentity?, to section: MenuBarOrganizerSection) {
        guard id != target else { return }
        let anchor = target.flatMap { target in items.first(where: { $0.id == target }).map(MenuBarItemAnchor.init) }
        guard target == nil || anchor != nil else { report(MenuBarItemMoveError.itemUnavailable); return }
        run { [weak self] expected in
            guard let self else { return }
            hider.prepareForOrganizerOperation()
            try await Task.sleep(for: .milliseconds(180))
            guard await snapshot(expected: expected) != nil else { throw MenuBarItemMoveError.itemUnavailable }
            let original = try uniqueItem(id)
            let ordered = MenuBarOrganizerSupport.orderedItems(items, in: original.section)
            let index = ordered.firstIndex { $0.windowID == original.windowID }!
            let neighbor = index + 1 < ordered.count ? MenuBarItemAnchor(ordered[index + 1]) : nil
            try await relocate(id: id, before: anchor, to: section, expected: expected)
            undo = (id, original.section, neighbor)
            canUndo = true
            hider.resumeAfterOrganizerOperation()
        }
    }

    func undoLastMove() {
        guard let undo else { return }
        run { [weak self] expected in
            guard let self else { return }
            hider.prepareForOrganizerOperation()
            try await Task.sleep(for: .milliseconds(180))
            try await relocate(id: undo.id, before: undo.neighbor, to: undo.section, expected: expected)
            self.undo = nil
            canUndo = false
            hider.resumeAfterOrganizerOperation()
        }
    }

    private func relocate(id: MenuBarItemIdentity, before target: MenuBarItemAnchor?,
                          to section: MenuBarOrganizerSection, expected: UInt64,
                          requiresVisibleDestination: Bool = false) async throws {
        for attempt in 0..<2 {
            try checkAccess()
            guard await snapshot(expected: expected) != nil,
                  let geometry = await hider.organizerGeometry() else { throw MenuBarItemMoveError.itemUnavailable }
            let item = try uniqueItem(id)
            guard item.isMovable else { throw MenuBarItemMoveError.itemNotMovable }
            let targetItem = target?.resolve(in: items)
            guard target == nil || targetItem != nil else { throw MenuBarItemMoveError.itemUnavailable }
            if let targetItem, targetItem.section != section { throw MenuBarItemMoveError.itemUnavailable }
            if requiresVisibleDestination {
                guard let targetItem, let strip = visibleStrip(containing: geometry.hidden),
                      MenuBarOrganizerPolicy.activationTarget(for: item, in: items, strip: strip)?.id == targetItem.id
                else { throw MenuBarItemMoveError.itemUnavailable }
            }
            let divider: CGRect?
            switch section {
            case .visible, .hidden: divider = geometry.hidden
            case .alwaysHidden: divider = geometry.always
            }
            let lastVisible = section == .visible && targetItem == nil
                ? MenuBarOrganizerSupport.orderedItems(items, in: .visible).last(where: { $0.id != id }) : nil
            guard let destination = targetItem?.frame ?? lastVisible?.frame ?? divider else { throw MenuBarItemMoveError.itemUnavailable }
            let destinationWindowID = targetItem?.windowID ?? lastVisible?.windowID
                ?? (MenuBarWindowServerBridge.menuBarWindowIDs() ?? []).first {
                    MenuBarWindowServerBridge.frame(of: $0) == destination
                }
            guard let destinationWindowID else { throw MenuBarItemMoveError.itemUnavailable }
            let placeAfter = targetItem == nil && section == .visible
            let insertion = MenuBarOrganizerPolicy.insertionFrame(destination, after: placeAfter)
            let quartzDestination = CGRect(x: insertion.minX, y: item.frame.minY,
                                           width: insertion.width, height: item.frame.height)
            // A native item belongs to one menu bar; do not drag across displays.
            guard abs(destination.midY - item.frame.midY) < 8 else { throw MenuBarItemMoveError.itemUnavailable }
            try await mover.move(item: item, destinationFrame: quartzDestination,
                                 destinationWindowID: destinationWindowID,
                                 placeAfter: placeAfter,
                                 onDragStart: { [weak self] in self?.activationRecovery?.mayBeDisplaced = true })
            try await Task.sleep(for: .milliseconds(180 + attempt * 80))
            guard await snapshot(expected: expected) != nil else { throw MenuBarItemMoveError.itemUnavailable }
            guard let refreshed = MenuBarOrganizerPolicy.uniquelyIdentified(id, in: items),
                  refreshed.windowID == item.windowID, refreshed.ownerPID == item.ownerPID else {
                throw MenuBarItemMoveError.itemUnavailable
            }
            if MenuBarOrganizerPolicy.verifiedMove(windowID: item.windowID, before: targetItem?.windowID,
                                                   section: section, items: items) { return }
        }
        throw MenuBarItemMoveError.verificationFailed
    }

    func activate(id: MenuBarItemIdentity) {
        run { [weak self] expected in
            guard let self else { return }
            panel?.close()
            let previousDisplayState = hider.organizerDisplayState
            activationRecovery = (previousDisplayState, false)
            defer { if generation == expected { finishActivationRecovery() } }
            hider.prepareForOrganizerOperation()
            try await Task.sleep(for: .milliseconds(180))
            guard await snapshot(expected: expected) != nil else { throw MenuBarItemMoveError.itemUnavailable }
            let original = try uniqueItem(id)
            guard MenuBarOrganizerPolicy.canActivate(original) else { throw MenuBarItemMoveError.itemUnavailable }
            let ordered = MenuBarOrganizerSupport.orderedItems(items, in: original.section)
            let index = ordered.firstIndex { $0.windowID == original.windowID }!
            let neighbor = index + 1 < ordered.count ? MenuBarItemAnchor(ordered[index + 1]) : nil
            let moved = original.section != .visible
            if moved {
                // The first visible item can abut the notch on a crowded bar.
                // Choose a reachable slot farther right before sending input.
                guard let geometry = await hider.organizerGeometry(),
                      let strip = visibleStrip(containing: geometry.hidden),
                      let target = MenuBarOrganizerPolicy.activationTarget(for: original, in: items, strip: strip)
                else { throw MenuBarItemMoveError.itemUnavailable }
                try await relocate(id: id, before: MenuBarItemAnchor(target), to: .visible, expected: expected,
                                   requiresVisibleDestination: true)
            }
            try checkAccess()
            guard await snapshot(expected: expected) != nil else { throw MenuBarItemMoveError.itemUnavailable }
            let current = try uniqueItem(id)
            guard onVisibleStrip(current.frame) else { throw MenuBarItemMoveError.itemUnavailable }
            try await mover.click(item: current)
            try await Task.sleep(for: .milliseconds(500))
            // Keep its real menu open. A slow user is never cut off by a timer.
            let pids = Set([current.ownerPID, current.sourcePID].compactMap { $0 })
            while MenuBarItemMover.hasOpenMenu(for: pids) || NSEvent.pressedMouseButtons != 0 {
                try checkAccess()
                try await Task.sleep(for: .milliseconds(250))
            }
            if moved {
                try await relocate(id: id, before: neighbor, to: original.section, expected: expected)
                activationRecovery?.mayBeDisplaced = false
            }
        }
    }

    private func visibleStrip(containing divider: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let point = CGPoint(x: divider.midX, y: primary.frame.maxY - divider.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return nil }
        let cocoa = screen.auxiliaryTopRightArea
            ?? CGRect(x: screen.frame.minX, y: screen.frame.maxY - NSStatusBar.system.thickness,
                      width: screen.frame.width, height: NSStatusBar.system.thickness)
        return CGRect(x: cocoa.minX, y: primary.frame.maxY - cocoa.maxY,
                      width: cocoa.width, height: cocoa.height)
    }

    private func onVisibleStrip(_ frame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let cocoa = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY,
                           width: frame.width, height: frame.height)
        return NSScreen.screens.contains { screen in
            guard screen.frame.contains(cocoa) else { return false }
            if let right = screen.auxiliaryTopRightArea { return right.contains(cocoa) }
            return true
        }
    }

    func showDrawer(search: Bool = false) {
        do { try checkAccess() } catch { report(error); return }
        if panel == nil { panel = MenuBarOrganizerPanelController(service: self) }
        panel?.show(anchor: hider.organizerAnchor, search: search)
        updateRefreshTimer()
        refresh()
    }

    func drawerClosed() { updateRefreshTimer() }

    func applySpacing(restore: Bool = false) {
        guard restore || (enabled && MenuBarOrganizerPolicy.supportsAdvancedBackend) else { return }
        let success = restore ? MenuBarGlobalSpacing.restore() : MenuBarGlobalSpacing.apply(
            spacing: UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOrganizerSpacing))
        canRestoreSpacing = MenuBarGlobalSpacing.hasSavedValues
        message = success ? text.spacingCaption : text.failed
    }

    private func report(_ error: Error) {
        diagnostic("operation failed: \(error)")
        switch error {
        case MenuBarItemMoveError.permissionMissing: message = text.permission
        case MenuBarItemMoveError.busy, MenuBarItemMoveError.menuOpen: message = text.busy
        case MenuBarItemMoveError.verificationFailed: message = text.failed
        default: message = text.unavailable
        }
    }

    private func diagnostic(_ message: String) {
        if ProcessInfo.processInfo.environment["VORSSAINT_MENU_BAR_DIAGNOSTICS"] == "1" {
            NSLog("Menu bar %@", message)
        }
    }
}
