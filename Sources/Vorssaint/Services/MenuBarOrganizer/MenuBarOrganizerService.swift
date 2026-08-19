// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class MenuBarOrganizerService: ObservableObject {
    static let shared = MenuBarOrganizerService()

    @Published private(set) var items: [ManagedMenuBarItem] = []
    @Published private(set) var capabilities = MenuBarOrganizerCapabilities(
        canEnumerate: false,
        canMove: AXIsProcessTrusted(),
        canHide: MenuBarOrganizerSupport.canHide(
            on: MenuBarOrganizerSupport.backend()),
        hasPrivateWindowList: false,
        unresolvedItemCount: 0)
    @Published private(set) var isRunning = false
    @Published private(set) var hiddenSectionShown = true
    @Published private(set) var alwaysHiddenSectionShown = true
    @Published private(set) var operationMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var conflictingManagers: [MenuBarManagerDetection.RunningManager] = []

    private let provider = MenuBarWindowProvider()
    private let mover = MenuBarItemMover()
    private var controlItem: MenuBarDividerItem?
    private var hiddenDivider: MenuBarDividerItem?
    private var alwaysHiddenDivider: MenuBarDividerItem?
    private var secondaryPanel: MenuBarOrganizerPanelController?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var editingCount = 0
    private var preEditingState: (hidden: Bool, always: Bool)?
    private var undoRecord: UndoRecord?
    private var suppressUndo = false

    private struct UndoRecord {
        let itemID: MenuBarItemIdentity
        let previousSection: MenuBarOrganizerSection
        let previousRightNeighbor: MenuBarItemIdentity?
    }

    private init() {}

    func syncWithPreferences() {
        // Never touch a backend on unvalidated future systems. macOS 27 is
        // routed to the AX provider before any WindowServer probe is made.
        guard AppFeature.menuBarOrganizer.isSupportedOnCurrentSystem else {
            stop()
            return
        }
        let enabled = AppFeature.menuBarOrganizer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        conflictingManagers = MenuBarManagerDetection.runningManagers()
        guard enabled else {
            stop()
            return
        }
        guard conflictingManagers.isEmpty else {
            stop(preservingDiagnostics: true)
            return
        }
        guard AXIsProcessTrusted() else {
            stop(preservingDiagnostics: true)
            capabilities = MenuBarOrganizerCapabilities(
                canEnumerate: capabilities.canEnumerate,
                canMove: false,
                canHide: capabilities.canHide,
                hasPrivateWindowList: capabilities.hasPrivateWindowList,
                unresolvedItemCount: capabilities.unresolvedItemCount)
            return
        }

        startIfNeeded()
        syncAlwaysHiddenDivider()
        applyDividerState()
        refresh()
    }

    func stop() {
        stop(preservingDiagnostics: false)
    }

    func beginEditing() {
        editingCount += 1
        guard editingCount == 1, isRunning else { return }
        preEditingState = (hiddenSectionShown, alwaysHiddenSectionShown)
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        secondaryPanel?.close()
        applyDividerState()
        scheduleRefreshTimer()
        refresh()
    }

    func endEditing() {
        editingCount = max(0, editingCount - 1)
        guard editingCount == 0 else { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete),
           let preEditingState {
            hiddenSectionShown = preEditingState.hidden
            alwaysHiddenSectionShown = preEditingState.always
        }
        preEditingState = nil
        applyDividerState()
        scheduleRefreshTimer()
        refresh()
    }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        editingCount = 0
        preEditingState = nil
        hideAll()
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            _ = await self?.refreshNow()
        }
    }

    func retryStart() {
        conflictingManagers = MenuBarManagerDetection.runningManagers()
        syncWithPreferences()
    }

    func toggleHiddenSection() {
        guard isRunning, capabilities.canHide else { return }
        if hiddenSectionShown || secondaryPanel?.isVisible == true {
            hideAll()
        } else {
            show(.hidden)
        }
    }

    func toggleAlwaysHiddenSection() {
        guard isRunning,
              capabilities.canHide,
              UserDefaults.standard.bool(
                forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        else { return }
        if alwaysHiddenSectionShown || secondaryPanel?.isVisible == true {
            alwaysHiddenSectionShown = false
            secondaryPanel?.close()
            applyDividerState()
            refresh()
        } else {
            show(.alwaysHidden)
        }
    }

    func showSecondaryBar() {
        guard isRunning else { return }
        refresh()
        if secondaryPanel == nil {
            secondaryPanel = MenuBarOrganizerPanelController(service: self)
        }
        secondaryPanel?.show(anchor: controlItem?.frame)
    }

    func hideAll() {
        secondaryPanel?.close()
        guard capabilities.canHide else {
            hiddenSectionShown = true
            alwaysHiddenSectionShown = true
            applyDividerState()
            refresh()
            return
        }
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
        refresh()
    }

    func move(itemID: MenuBarItemIdentity,
              before targetID: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) {
        guard !mover.isMoving else {
            operationMessage = moveErrorMessage(.busy)
            return
        }
        Task { [weak self] in
            await self?.performMove(itemID: itemID, before: targetID, to: section)
        }
    }

    func undoLastMove() {
        guard let record = undoRecord else { return }
        suppressUndo = true
        Task { [weak self] in
            guard let self else { return }
            await performMove(itemID: record.itemID,
                              before: record.previousRightNeighbor,
                              to: record.previousSection)
            suppressUndo = false
            undoRecord = nil
            canUndo = false
        }
    }

    func activate(itemID: MenuBarItemIdentity) {
        Task { [weak self] in
            guard let self,
                  let original = items.first(where: { $0.id == itemID })
            else { return }
            secondaryPanel?.close()
            if original.section != .visible {
                showInMenuBar(original.section)
                try? await Task.sleep(for: .milliseconds(160))
                _ = await refreshNow()
            }
            guard let current = items.first(where: { $0.id == itemID }) else {
                operationMessage = moveErrorMessage(.itemUnavailable)
                return
            }
            do {
                try await mover.click(item: current)
            } catch let error as MenuBarItemMoveError {
                operationMessage = moveErrorMessage(error)
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    func clearOperationMessage() {
        operationMessage = nil
    }

    private func startIfNeeded() {
        guard !isRunning else {
            scheduleRefreshTimer()
            return
        }
        teardownTask?.cancel()
        teardownTask = nil
        let control = MenuBarDividerItem(kind: .control)
        let hidden = MenuBarDividerItem(kind: .hidden)
        control.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        control.onRightClick = { [weak self, weak control] in
            self?.showContextMenu(relativeTo: control)
        }
        hidden.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        controlItem = control
        hiddenDivider = hidden
        secondaryPanel = MenuBarOrganizerPanelController(service: self)
        isRunning = true

        let setupComplete = UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        let supportsHiding = MenuBarOrganizerSupport.canHide(
            on: MenuBarOrganizerSupport.backend())
        hiddenSectionShown = supportsHiding ? !setupComplete : true
        alwaysHiddenSectionShown = supportsHiding ? !setupComplete : true
        installObservers()
        scheduleRefreshTimer()
    }

    private func stop(preservingDiagnostics: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        removeObservers()
        secondaryPanel?.close()
        secondaryPanel = nil
        editingCount = 0
        preEditingState = nil
        undoRecord = nil
        canUndo = false

        guard isRunning || controlItem != nil || hiddenDivider != nil
                || alwaysHiddenDivider != nil
        else {
            if !preservingDiagnostics {
                items = []
                conflictingManagers = []
            }
            return
        }

        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        hiddenDivider?.expandForRemoval()
        alwaysHiddenDivider?.expandForRemoval()
        let removing = [controlItem, hiddenDivider, alwaysHiddenDivider].compactMap { $0 }
        controlItem = nil
        hiddenDivider = nil
        alwaysHiddenDivider = nil
        isRunning = false
        items = []

        teardownTask?.cancel()
        teardownTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            removing.forEach { $0.removePreservingPosition() }
        }
        if !preservingDiagnostics {
            conflictingManagers = []
            capabilities = MenuBarOrganizerCapabilities(
                canEnumerate: false,
                canMove: AXIsProcessTrusted(),
                canHide: MenuBarOrganizerSupport.canHide(
                    on: MenuBarOrganizerSupport.backend()),
                hasPrivateWindowList: false,
                unresolvedItemCount: 0)
        }
    }

    private func syncAlwaysHiddenDivider() {
        let enabled = UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        if enabled, alwaysHiddenDivider == nil {
            let divider = MenuBarDividerItem(kind: .alwaysHidden)
            divider.onLeftClick = { [weak self] in self?.toggleAlwaysHiddenSection() }
            alwaysHiddenDivider = divider
        } else if !enabled, let divider = alwaysHiddenDivider {
            alwaysHiddenSectionShown = true
            divider.expandForRemoval()
            alwaysHiddenDivider = nil
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                divider.removePreservingPosition()
            }
        }
    }

    private func applyDividerState() {
        let setupComplete = UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        let markers = editingCount > 0
            || !setupComplete
            || UserDefaults.standard.bool(
                forKey: DefaultsKey.menuBarOrganizerShowDividers)
        let length = MenuBarOrganizerSupport.collapsedLength(
            screenWidths: NSScreen.screens.map(\.frame.width))
        if !MenuBarOrganizerSupport.canHide(on: MenuBarOrganizerSupport.backend()) {
            hiddenDivider?.setCollapsed(false,
                                        markerVisible: true,
                                        collapsedLength: length)
            alwaysHiddenDivider?.setCollapsed(false,
                                              markerVisible: true,
                                              collapsedLength: length)
            return
        }
        hiddenDivider?.setCollapsed(
            !hiddenSectionShown && editingCount == 0,
            markerVisible: markers,
            collapsedLength: length)
        alwaysHiddenDivider?.setCollapsed(
            !alwaysHiddenSectionShown && editingCount == 0,
            markerVisible: markers,
            collapsedLength: length)
    }

    @discardableResult
    private func refreshNow() async -> MenuBarItemSnapshot? {
        guard isRunning else { return nil }
        let excluded = Set([
            controlItem?.windowID,
            hiddenDivider?.windowID,
            alwaysHiddenDivider?.windowID,
        ].compactMap { $0 })
        let snapshot = await provider.snapshot(
            hiddenDividerMidX: hiddenDivider?.frame?.midX,
            alwaysHiddenDividerMidX: alwaysHiddenDivider?.frame?.midX,
            excludedWindowIDs: excluded)
        guard !Task.isCancelled, isRunning else { return nil }
        capabilities = snapshot.capabilities
        if !MenuBarOrganizerSupport.shouldKeepPreviousSnapshot(
            previousCount: items.count,
            newCount: snapshot.items.count,
            enumerationSucceeded: snapshot.enumerationSucceeded) {
            items = snapshot.items
        }
        return snapshot
    }

    private func performMove(itemID: MenuBarItemIdentity,
                             before targetID: MenuBarItemIdentity?,
                             to section: MenuBarOrganizerSection) async {
        operationMessage = nil
        guard targetID != itemID else { return }
        guard MenuBarManagerDetection.runningManagers().isEmpty else {
            conflictingManagers = MenuBarManagerDetection.runningManagers()
            operationMessage = moveErrorMessage(.busy)
            return
        }

        showInMenuBar(.alwaysHidden)
        try? await Task.sleep(for: .milliseconds(100))
        _ = await refreshNow()
        guard let original = items.first(where: { $0.id == itemID }) else {
            operationMessage = moveErrorMessage(.itemUnavailable)
            return
        }
        guard original.identityState == .stable else {
            operationMessage = moveErrorMessage(.provisionalIdentity)
            return
        }
        let orderedBefore = MenuBarOrganizerSupport.orderedItems(items, in: original.section)
        let rightNeighbor = orderedBefore
            .drop(while: { $0.id != original.id })
            .dropFirst()
            .first?.id
        if !suppressUndo {
            undoRecord = UndoRecord(itemID: original.id,
                                    previousSection: original.section,
                                    previousRightNeighbor: rightNeighbor)
        }

        var lastError: MenuBarItemMoveError = .verificationFailed
        for attempt in 0..<2 {
            _ = await refreshNow()
            guard let current = items.first(where: { $0.id == itemID }) else {
                lastError = .itemUnavailable
                break
            }
            guard let destination = destination(
                for: section,
                targetID: targetID,
                referenceFrame: current.frame)
            else {
                lastError = .itemUnavailable
                break
            }
            do {
                try await mover.move(item: current,
                                     destinationFrame: destination.frame,
                                     placeAfter: destination.placeAfter)
                try? await Task.sleep(for: .milliseconds(120 + attempt * 80))
                _ = await refreshNow()
                if moveWasVerified(itemID: itemID,
                                   targetID: targetID,
                                   section: section) {
                    canUndo = undoRecord != nil
                    return
                }
                lastError = .verificationFailed
            } catch let error as MenuBarItemMoveError {
                lastError = error
                if error != .verificationFailed { break }
            } catch {
                operationMessage = error.localizedDescription
                break
            }
        }

        operationMessage = moveErrorMessage(lastError)
        if !suppressUndo {
            undoRecord = nil
            canUndo = false
        }
        _ = await refreshNow()
    }

    private func destination(for section: MenuBarOrganizerSection,
                             targetID: MenuBarItemIdentity?,
                             referenceFrame: CGRect) -> (frame: CGRect, placeAfter: Bool)? {
        if let targetID,
           let target = items.first(where: { $0.id == targetID }) {
            return (target.frame, false)
        }
        func quartzFrame(_ frame: CGRect, placeAfter: Bool) -> (CGRect, Bool) {
            (CGRect(x: frame.minX,
                    y: referenceFrame.minY,
                    width: frame.width,
                    height: referenceFrame.height),
             placeAfter)
        }
        switch section {
        case .visible:
            return hiddenDivider?.frame.map { quartzFrame($0, placeAfter: true) }
        case .hidden:
            return hiddenDivider?.frame.map { quartzFrame($0, placeAfter: false) }
        case .alwaysHidden:
            return alwaysHiddenDivider?.frame.map { quartzFrame($0, placeAfter: false) }
        }
    }

    private func moveWasVerified(itemID: MenuBarItemIdentity,
                                 targetID: MenuBarItemIdentity?,
                                 section: MenuBarOrganizerSection) -> Bool {
        guard let current = items.first(where: { $0.id == itemID }),
              current.section == section
        else { return false }
        guard let targetID else { return true }
        guard let target = items.first(where: { $0.id == targetID }) else {
            return false
        }
        return current.frame.maxX <= target.frame.minX + 3
    }

    private func show(_ section: MenuBarOrganizerSection) {
        guard editingCount == 0 else {
            showInMenuBar(section)
            return
        }
        let mode = MenuBarOrganizerPresentationMode.sanitized(
            UserDefaults.standard.string(
                forKey: DefaultsKey.menuBarOrganizerPresentationMode))
        let hiddenWidth = items.filter {
            section == .alwaysHidden ? $0.section != .visible : $0.section == .hidden
        }.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let screen = controlItem?.frame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let availableWidth = (screen?.visibleFrame.width ?? 1_024) * 0.45
        let hasNotch = screen?.auxiliaryTopLeftArea != nil
            || screen?.auxiliaryTopRightArea != nil
        if MenuBarOrganizerSupport.shouldUseSecondaryBar(
            mode: mode,
            hiddenWidth: hiddenWidth,
            availableWidth: availableWidth,
            hasNotch: hasNotch) {
            showSecondaryBar()
        } else {
            showInMenuBar(section)
        }
    }

    private func showInMenuBar(_ section: MenuBarOrganizerSection) {
        secondaryPanel?.close()
        switch section {
        case .visible:
            break
        case .hidden:
            hiddenSectionShown = true
        case .alwaysHidden:
            hiddenSectionShown = true
            alwaysHiddenSectionShown = true
        }
        applyDividerState()
        refresh()
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        guard isRunning else {
            refreshTimer = nil
            return
        }
        let interval: TimeInterval = editingCount > 0 ? 2 : 10
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = interval * 0.25
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func installObservers() {
        removeObservers()
        func observe(_ center: NotificationCenter,
                     _ name: Notification.Name,
                     action: @escaping @MainActor () -> Void) {
            let token = center.addObserver(
                forName: name, object: nil, queue: .main) { _ in
                    Task { @MainActor in action() }
                }
            observers.append((center, token))
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didLaunchApplicationNotification) { [weak self] in
            self?.refresh()
        }
        observe(workspace, NSWorkspace.didTerminateApplicationNotification) { [weak self] in
            self?.conflictingManagers = MenuBarManagerDetection.runningManagers()
            self?.refresh()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { [weak self] in
            Task { await self?.provider.invalidateIdentityCache() }
            self?.refresh()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            Task { await self?.provider.invalidateIdentityCache() }
            self?.refresh()
        }
    }

    private func removeObservers() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    private func showContextMenu(relativeTo item: MenuBarDividerItem?) {
        guard let button = item?.statusItem.button else { return }
        let text = FeatureStrings.menuBarOrganizer(L10n.shared.language)
        let menu = NSMenu()
        menu.addItem(
            withTitle: hiddenSectionShown ? text.contextHideHidden : text.contextShowHidden,
            action: #selector(contextToggleHidden),
            keyEquivalent: "")
        if UserDefaults.standard.bool(
            forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) {
            menu.addItem(
                withTitle: alwaysHiddenSectionShown
                    ? text.contextHideAlways
                    : text.contextShowAlways,
                action: #selector(contextToggleAlways),
                keyEquivalent: "")
        }
        menu.addItem(
            withTitle: text.secondaryBar,
            action: #selector(contextSecondary),
            keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(
            withTitle: text.contextSettings,
            action: #selector(contextSettings),
            keyEquivalent: "")
        menu.addItem(
            withTitle: text.contextDisable,
            action: #selector(contextDisable),
            keyEquivalent: "")
        for menuItem in menu.items { menuItem.target = self }
        item?.statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { item?.statusItem.menu = nil }
    }

    private func moveErrorMessage(_ error: MenuBarItemMoveError) -> String {
        let text = FeatureStrings.menuBarOrganizer(L10n.shared.language)
        switch error {
        case .permissionMissing: return text.errorPermission
        case .itemUnavailable: return text.errorUnavailable
        case .itemNotMovable: return text.errorNotMovable
        case .provisionalIdentity: return text.errorUnresolved
        case .menuOpen: return text.errorMenuOpen
        case .eventCreationFailed: return text.errorEvent
        case .verificationFailed: return text.errorVerification
        case .busy: return text.errorBusy
        }
    }

    @objc private func contextToggleHidden() { toggleHiddenSection() }
    @objc private func contextToggleAlways() { toggleAlwaysHiddenSection() }
    @objc private func contextSecondary() { showSecondaryBar() }
    @objc private func contextSettings() {
        SettingsRouter.shared.page = .menuBarOrganizer
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
    @objc private func contextDisable() {
        UserDefaults.standard.set(false, forKey: DefaultsKey.menuBarOrganizerEnabled)
        syncWithPreferences()
    }
}
