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
        canEnumerate: true,
        canMove: AXIsProcessTrusted(),
        canCapture: CGPreflightScreenCaptureAccess(),
        hasPrivateFrameAPI: DynamicMenuBarAPI.shared.hasWindowFrame)
    @Published private(set) var isRunning = false
    @Published private(set) var hiddenSectionShown = true
    @Published private(set) var alwaysHiddenSectionShown = true
    @Published private(set) var operationMessage: String?
    @Published private(set) var canUndo = false
    @Published private(set) var hotkeyRegistrationFailed = false
    @Published private(set) var presets: [MenuBarOrganizerPresetSlot: MenuBarOrganizerPreset] = [:]
    @Published private(set) var namedPresets: [MenuBarOrganizerNamedPreset] = []
    @Published private(set) var groups: [MenuBarOrganizerGroupSlot: MenuBarOrganizerGroup] = [:]
    @Published private(set) var customGroups: [MenuBarOrganizerCustomGroup] = []

    private let provider = MenuBarWindowProvider()
    private let mover = MenuBarItemMover()
    private let hotkeys = MenuBarOrganizerHotkeyController()
    private var controlItem: MenuBarDividerItem?
    private var hiddenDivider: MenuBarDividerItem?
    private var alwaysHiddenDivider: MenuBarDividerItem?
    private var searchPanel: MenuBarOrganizerPanelController?
    private var secondaryPanel: MenuBarOrganizerPanelController?
    private var groupPanels: [MenuBarOrganizerGroupReference: MenuBarOrganizerPanelController] = [:]
    private var groupStatusItems: [MenuBarOrganizerGroupReference: MenuBarGroupStatusItem] = [:]
    private var spacerItems: [MenuBarSpacerItem] = []
    private var refreshTimer: Timer?
    private var triggerTimer: Timer?
    private var rehideTimer: Timer?
    private var globalMouseMonitor: Any?
    private var globalScrollMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private var editingCount = 0
    private var scrollAccumulator: CGFloat = 0
    private var undoRecord: UndoRecord?
    private var suppressUndo = false
    private var snapshotTask: Task<Void, Never>?
    private var groupAutoHideTask: Task<Void, Never>?
    private var automationTask: Task<Void, Never>?
    private var lastAutomationSignature: String?
    private var imageCache: [MenuBarItemIdentity: NSImage] = [:]
    private var notchBorrowedItems: [UndoRecord] = []

    private struct UndoRecord {
        let itemID: MenuBarItemIdentity
        let previousSection: MenuBarOrganizerSection
        let previousRightNeighbor: MenuBarItemIdentity?
    }

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.menuBarOrganizer.isAvailable
            && defaults.bool(forKey: DefaultsKey.menuBarOrganizerEnabled)
        if enabled {
            loadPresets()
            loadGroups()
            startIfNeeded()
            syncAlwaysHiddenDivider()
            syncGroupStatusItems()
            syncSpacerItems()
            syncHotkeys()
            installEventMonitors()
            applyDividerState()
            refresh()
            applyGroupedItemVisibilityPreference()
            evaluateAutomationTriggers()
        } else {
            stop()
        }
    }

    func stop() {
        guard isRunning else {
            hotkeys.unregisterAll()
            return
        }
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        applyDividerState()
        searchPanel?.close()
        secondaryPanel?.close()
        groupPanels.values.forEach { $0.close() }
        groupPanels = [:]
        groupStatusItems.values.forEach { $0.removePreservingPosition() }
        groupStatusItems = [:]
        spacerItems.forEach { $0.removePreservingPosition() }
        spacerItems = []
        refreshTimer?.invalidate()
        refreshTimer = nil
        triggerTimer?.invalidate()
        triggerTimer = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        groupAutoHideTask?.cancel()
        groupAutoHideTask = nil
        automationTask?.cancel()
        automationTask = nil
        lastAutomationSignature = nil
        rehideTimer?.invalidate()
        rehideTimer = nil
        removeEventMonitors()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        hotkeys.unregisterAll()
        hiddenDivider?.removePreservingPosition()
        alwaysHiddenDivider?.removePreservingPosition()
        controlItem?.removePreservingPosition()
        hiddenDivider = nil
        alwaysHiddenDivider = nil
        controlItem = nil
        items = []
        undoRecord = nil
        notchBorrowedItems = []
        canUndo = false
        isRunning = false
    }

    func beginEditing() {
        editingCount += 1
        guard isRunning else { return }
        hiddenSectionShown = true
        alwaysHiddenSectionShown = true
        cancelRehide()
        applyDividerState()
        refresh()
    }

    func endEditing() {
        editingCount = max(0, editingCount - 1)
        guard editingCount == 0 else { return }
        applyDividerState()
        scheduleRehide()
    }

    func completeSetup() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        editingCount = 0
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
        refresh()
    }

    func refresh() {
        refresh(captureImages: UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerCapturePreviews))
    }

    func toggleHiddenSection() {
        guard isRunning else { return }
        if hiddenSectionShown
            || secondaryPanel?.isVisible == true
            || groupPanels.values.contains(where: { $0.isVisible }) {
            hideAll()
        } else {
            show(.hidden)
        }
    }

    func toggleAlwaysHiddenSection() {
        guard isRunning,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        else { return }
        if alwaysHiddenSectionShown {
            alwaysHiddenSectionShown = false
            applyDividerState()
        } else {
            show(.alwaysHidden)
        }
    }

    func showSearch() {
        guard isRunning else { return }
        refresh()
        if searchPanel == nil {
            searchPanel = MenuBarOrganizerPanelController(kind: .search, service: self)
        }
        searchPanel?.show()
    }

    func closeSearch() {
        searchPanel?.close()
    }

    func showSecondaryBar() {
        guard isRunning else { return }
        refresh()
        if secondaryPanel == nil {
            secondaryPanel = MenuBarOrganizerPanelController(kind: .secondary, service: self)
        }
        secondaryPanel?.show(anchor: controlItem?.frame)
        scheduleRehide()
    }

    func showGroup(slot: MenuBarOrganizerGroupSlot) {
        showGroup(reference: .slot(slot))
    }

    func showGroup(reference: MenuBarOrganizerGroupReference) {
        guard isRunning else { return }
        refresh()
        searchPanel?.close()
        secondaryPanel?.close()
        if groupPanels[reference] == nil {
            groupPanels[reference] = MenuBarOrganizerPanelController(kind: .group(reference), service: self)
        }
        groupPanels[reference]?.show(anchor: controlItem?.frame)
        scheduleRehide()
    }

    func hideAll() {
        Task { await hideAllRestoringBorrowedItems() }
    }

    func move(itemID: MenuBarItemIdentity,
              before targetID: MenuBarItemIdentity?,
              to section: MenuBarOrganizerSection) {
        Task { await performMove(itemID: itemID, before: targetID, to: section) }
    }

    func undoLastMove() {
        guard let record = undoRecord else { return }
        suppressUndo = true
        Task {
            await performMove(itemID: record.itemID,
                              before: record.previousRightNeighbor,
                              to: record.previousSection)
            suppressUndo = false
            undoRecord = nil
            canUndo = false
        }
    }

    func savePreset(slot: MenuBarOrganizerPresetSlot) {
        refresh()
        presets[slot] = MenuBarOrganizerSupport.preset(slot: slot, items: items)
        persistPresets()
    }

    func applyPreset(slot: MenuBarOrganizerPresetSlot) {
        guard let preset = presets[slot] else { return }
        Task { await applyPreset(preset) }
    }

    func clearPreset(slot: MenuBarOrganizerPresetSlot) {
        presets.removeValue(forKey: slot)
        persistPresets()
    }

    func saveNamedPreset(name: String) {
        refresh()
        namedPresets.append(MenuBarOrganizerSupport.namedPreset(name: name, items: items))
        persistNamedPresets()
    }

    func applyNamedPreset(id: String) {
        guard let preset = namedPresets.first(where: { $0.id == id }) else { return }
        Task { await applyNamedPreset(preset) }
    }

    func deleteNamedPreset(id: String) {
        namedPresets.removeAll { $0.id == id }
        persistNamedPresets()
    }

    func addToGroup(itemID: MenuBarItemIdentity, slot: MenuBarOrganizerGroupSlot) {
        addToGroup(itemID: itemID, reference: .slot(slot))
    }

    func addToGroup(itemID: MenuBarItemIdentity, reference: MenuBarOrganizerGroupReference) {
        refresh()
        guard items.contains(where: { $0.id == itemID }) else { return }
        if case .custom(let id) = reference,
           !customGroups.contains(where: { $0.id == id }) {
            return
        }
        removeFromGroup(itemID: itemID, persists: false)
        switch reference {
        case .slot(let slot):
            var group = groups[slot] ?? MenuBarOrganizerSupport.group(slot: slot, items: [])
            if !group.items.contains(itemID) {
                group.items.append(itemID)
            }
            groups[slot] = MenuBarOrganizerSupport.group(slot: slot, items: group.items)
        case .custom(let id):
            guard let index = customGroups.firstIndex(where: { $0.id == id }) else { return }
            if !customGroups[index].items.contains(itemID) {
                customGroups[index].items.append(itemID)
            }
            customGroups[index] = MenuBarOrganizerSupport.customGroup(
                name: customGroups[index].name,
                symbolName: customGroups[index].symbolName,
                items: customGroups[index].items,
                now: customGroups[index].savedAt,
                id: customGroups[index].id)
        }
        persistGroups()
        persistCustomGroups()
        syncGroupStatusItems()
        applyGroupedItemVisibilityPreference()
    }

    func removeFromGroup(itemID: MenuBarItemIdentity) {
        removeFromGroup(itemID: itemID, persists: true)
    }

    func clearGroup(slot: MenuBarOrganizerGroupSlot) {
        clearGroup(reference: .slot(slot))
    }

    func clearGroup(reference: MenuBarOrganizerGroupReference) {
        switch reference {
        case .slot(let slot):
            groups.removeValue(forKey: slot)
        case .custom(let id):
            if let index = customGroups.firstIndex(where: { $0.id == id }) {
                customGroups[index].items = []
                persistCustomGroups()
            }
        }
        groupPanels[reference]?.close()
        groupPanels.removeValue(forKey: reference)
        if case .slot = reference {
            persistGroups()
        }
        syncGroupStatusItems()
    }

    func createCustomGroup(name: String, symbolName: String) {
        customGroups.append(MenuBarOrganizerSupport.customGroup(name: name, symbolName: symbolName))
        persistCustomGroups()
    }

    func updateCustomGroup(id: String, name: String, symbolName: String) {
        guard let index = customGroups.firstIndex(where: { $0.id == id }) else { return }
        let group = customGroups[index]
        customGroups[index] = MenuBarOrganizerSupport.customGroup(
            name: name, symbolName: symbolName, items: group.items,
            now: group.savedAt, id: group.id)
        persistCustomGroups()
        syncGroupStatusItems()
    }

    func deleteCustomGroup(id: String) {
        let reference = MenuBarOrganizerGroupReference.custom(id)
        customGroups.removeAll { $0.id == id }
        groupPanels[reference]?.close()
        groupPanels.removeValue(forKey: reference)
        groupStatusItems[reference]?.removePreservingPosition()
        groupStatusItems.removeValue(forKey: reference)
        persistCustomGroups()
        syncGroupStatusItems()
    }

    func items(inGroup slot: MenuBarOrganizerGroupSlot) -> [ManagedMenuBarItem] {
        items(inGroup: .slot(slot))
    }

    func items(inGroup reference: MenuBarOrganizerGroupReference) -> [ManagedMenuBarItem] {
        let ids: [MenuBarItemIdentity]
        switch reference {
        case .slot(let slot):
            ids = groups[slot]?.items ?? []
        case .custom(let id):
            ids = customGroups.first(where: { $0.id == id })?.items ?? []
        }
        return ids.compactMap { id in items.first(where: { $0.id == id }) }
    }

    func groupReferencesWithItems() -> [MenuBarOrganizerGroupReference] {
        let fixed = MenuBarOrganizerGroupSlot.allCases
            .map(MenuBarOrganizerGroupReference.slot)
            .filter { !items(inGroup: $0).isEmpty }
        let custom = customGroups
            .map { MenuBarOrganizerGroupReference.custom($0.id) }
            .filter { !items(inGroup: $0).isEmpty }
        return fixed + custom
    }

    func title(forGroup reference: MenuBarOrganizerGroupReference) -> String {
        switch reference {
        case .slot(let slot): return groupTitle(slot)
        case .custom(let id):
            return customGroups.first(where: { $0.id == id })?.name ?? "Group"
        }
    }

    func symbolName(forGroup reference: MenuBarOrganizerGroupReference) -> String {
        switch reference {
        case .slot(let slot):
            switch slot {
            case .cloud: return "icloud"
            case .audio: return "speaker.wave.2"
            case .work: return "briefcase"
            case .custom: return "folder"
            }
        case .custom(let id):
            return customGroups.first(where: { $0.id == id })?.symbolName ?? "folder"
        }
    }

    func group(for itemID: MenuBarItemIdentity) -> MenuBarOrganizerGroupReference? {
        if let slot = MenuBarOrganizerGroupSlot.allCases.first(where: {
            groups[$0]?.items.contains(itemID) == true
        }) {
            return .slot(slot)
        }
        if let group = customGroups.first(where: { $0.items.contains(itemID) }) {
            return .custom(group.id)
        }
        return nil
    }

    func isGrouped(itemID: MenuBarItemIdentity) -> Bool {
        group(for: itemID) != nil
    }

    func activate(itemID: MenuBarItemIdentity) {
        Task {
            guard let original = items.first(where: { $0.id == itemID }) else { return }
            searchPanel?.close()
            secondaryPanel?.close()
            groupPanels.values.forEach { $0.close() }
            if original.section != .visible {
                showInMenuBar(original.section)
                try? await Task.sleep(for: .milliseconds(140))
                refresh(captureImages: false)
            }
            guard let current = items.first(where: { $0.id == itemID }) else {
                operationMessage = MenuBarItemMoveError.itemUnavailable.localizedDescription
                return
            }
            do {
                try await mover.click(item: current)
                scheduleRehide()
            } catch {
                operationMessage = error.localizedDescription
            }
        }
    }

    func reveal(itemID: MenuBarItemIdentity) {
        Task {
            guard let item = items.first(where: { $0.id == itemID }) else { return }
            searchPanel?.close()
            groupPanels.values.forEach { $0.close() }
            if item.section != .visible {
                showInMenuBar(item.section)
                scheduleRehide()
            }
        }
    }

    func clearOperationMessage() {
        operationMessage = nil
    }

    private func startIfNeeded() {
        guard !isRunning else { return }
        let control = MenuBarDividerItem(kind: .control)
        let hidden = MenuBarDividerItem(kind: .hidden)
        control.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        control.onRightClick = { [weak self, weak control] in
            self?.showContextMenu(relativeTo: control)
        }
        hidden.onLeftClick = { [weak self] in self?.toggleHiddenSection() }
        controlItem = control
        hiddenDivider = hidden
        searchPanel = MenuBarOrganizerPanelController(kind: .search, service: self)
        secondaryPanel = MenuBarOrganizerPanelController(kind: .secondary, service: self)
        isRunning = true

        let setupComplete = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        hiddenSectionShown = !setupComplete
        alwaysHiddenSectionShown = !setupComplete
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(captureImages: false) }
        }
        refreshTimer?.tolerance = 0.5
        triggerTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateAutomationTriggers() }
        }
        triggerTimer?.tolerance = 4
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self,
                          MenuBarOrganizerRehideMode.sanitized(
                            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerRehideMode)) == .focusedApp,
                          self.editingCount == 0,
                          self.searchPanel?.isVisible != true,
                          self.secondaryPanel?.isVisible != true,
                          !self.pointerIsInsideMenuBar()
                    else { return }
                    self.hideAll()
                }
            }
    }

    private func syncAlwaysHiddenDivider() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
        if enabled, alwaysHiddenDivider == nil {
            let divider = MenuBarDividerItem(kind: .alwaysHidden)
            divider.onLeftClick = { [weak self] in self?.toggleAlwaysHiddenSection() }
            alwaysHiddenDivider = divider
        } else if !enabled, let divider = alwaysHiddenDivider {
            alwaysHiddenSectionShown = true
            divider.setCollapsed(false, markerVisible: false, collapsedLength: 1)
            divider.removePreservingPosition()
            alwaysHiddenDivider = nil
        }
    }

    private func applyDividerState() {
        let defaults = UserDefaults.standard
        let setupComplete = defaults.bool(forKey: DefaultsKey.menuBarOrganizerSetupComplete)
        let markers = editingCount > 0
            || !setupComplete
            || defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowDividers)
        let length = MenuBarOrganizerSupport.collapsedLength(
            screenWidths: NSScreen.screens.map(\.frame.width))
        hiddenDivider?.setCollapsed(!hiddenSectionShown && editingCount == 0,
                                    markerVisible: markers,
                                    collapsedLength: length)
        alwaysHiddenDivider?.setCollapsed(!alwaysHiddenSectionShown && editingCount == 0,
                                          markerVisible: markers,
                                          collapsedLength: length)
    }

    private func refresh(captureImages: Bool) {
        guard isRunning else { return }
        let defaults = UserDefaults.standard
        let canCapture = CGPreflightScreenCaptureAccess()
        let usesExactPreviews = MenuBarOrganizerSupport.usesExactPreviews(
            preferenceEnabled: defaults.bool(forKey: DefaultsKey.menuBarOrganizerCapturePreviews),
            screenRecordingGranted: canCapture)
        if !usesExactPreviews {
            snapshotTask?.cancel()
            snapshotTask = nil
            imageCache.removeAll()
        }
        let records = provider.records()
        let ownWindowIDs = Set(([controlItem?.windowID, hiddenDivider?.windowID,
                                 alwaysHiddenDivider?.windowID]
            + groupStatusItems.values.map(\.windowID)
            + spacerItems.map(\.windowID)).compactMap { $0 })
        let filtered = records.filter { !ownWindowIDs.contains($0.windowID) }
        let identities = MenuBarOrganizerSupport.identities(for: filtered)
        let hiddenX = hiddenDivider?.frame?.midX
        let alwaysX = alwaysHiddenDivider?.frame?.midX
        items = filtered.compactMap { record in
            guard let identity = identities[record.windowID] else { return nil }
            let section = MenuBarOrganizerSupport.section(itemMidX: record.frame.midX,
                                                          hiddenDividerMidX: hiddenX,
                                                          alwaysHiddenDividerMidX: alwaysX)
            // Organizer-owned divider windows were removed by window id
            // above. Other Vorssaint status items (metrics, battery time)
            // are normal user-manageable items and must remain movable.
            let protected = false
            let immovable = MenuBarOrganizerSupport.isSystemImmovable(
                bundleIdentifier: record.bundleIdentifier, title: record.title)
            let fallbackIcon = NSRunningApplication(processIdentifier: record.ownerPID)
                .flatMap(\.bundleURL)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            return ManagedMenuBarItem(id: identity,
                                      windowID: record.windowID,
                                      ownerPID: record.ownerPID,
                                      ownerName: record.ownerName,
                                      bundleIdentifier: record.bundleIdentifier,
                                      title: record.title,
                                      frame: record.frame,
                                      section: section,
                                      isMovable: !protected && !immovable,
                                      isProtected: protected,
                                      image: usesExactPreviews
                                        ? (imageCache[identity] ?? fallbackIcon)
                                        : fallbackIcon)
        }
        .sorted { $0.frame.minX < $1.frame.minX }
        capabilities = MenuBarOrganizerCapabilities(
            canEnumerate: true,
            canMove: AXIsProcessTrusted(),
            canCapture: canCapture,
            hasPrivateFrameAPI: DynamicMenuBarAPI.shared.hasWindowFrame)
        if captureImages, usesExactPreviews {
            loadSnapshots(records: filtered, identities: identities)
        }
        syncGroupStatusItems()
    }

    private func performMove(itemID: MenuBarItemIdentity,
                             before targetID: MenuBarItemIdentity?,
                             to section: MenuBarOrganizerSection) async {
        operationMessage = nil
        guard targetID != itemID else { return }
        showInMenuBar(.alwaysHidden)
        try? await Task.sleep(for: .milliseconds(80))
        refresh(captureImages: false)
        guard let item = items.first(where: { $0.id == itemID }) else {
            operationMessage = MenuBarItemMoveError.itemUnavailable.localizedDescription
            return
        }

        let orderedBefore = MenuBarOrganizerSupport.orderedItems(items, in: item.section)
        let rightNeighbor = orderedBefore.drop(while: { $0.id != item.id }).dropFirst().first?.id
        if !suppressUndo {
            undoRecord = UndoRecord(itemID: item.id,
                                    previousSection: item.section,
                                    previousRightNeighbor: rightNeighbor)
        }

        let destination: (CGRect, Bool)?
        if let targetID, let target = items.first(where: { $0.id == targetID }) {
            destination = (target.frame, false)
        } else {
            destination = boundaryDestination(for: section, referenceFrame: item.frame)
        }
        guard let destination else {
            operationMessage = "The section divider is not available."
            return
        }

        do {
            try await mover.move(item: item,
                                 destinationFrame: destination.0,
                                 placeAfter: destination.1) { [weak self] in
                guard let self else { return false }
                self.refresh(captureImages: false)
                guard let current = self.items.first(where: { $0.id == itemID }) else { return false }
                if let targetID,
                   let target = self.items.first(where: { $0.id == targetID }) {
                    return current.section == section
                        && current.frame.maxX <= target.frame.minX + 3
                }
                return current.section == section
            }
            canUndo = undoRecord != nil
            refresh()
            scheduleRehide()
        } catch {
            operationMessage = error.localizedDescription
            if !suppressUndo {
                undoRecord = nil
                canUndo = false
            }
            refresh()
        }
    }

    private func boundaryDestination(for section: MenuBarOrganizerSection,
                                     referenceFrame: CGRect) -> (CGRect, Bool)? {
        // Divider windows expose AppKit frames while CGWindow records and
        // synthesized mouse events use Quartz coordinates. Their horizontal
        // axis is shared; copy only x/width and keep the item's Quartz y.
        func quartzBoundary(_ frame: CGRect, placeAfter: Bool) -> (CGRect, Bool) {
            (CGRect(x: frame.minX,
                    y: referenceFrame.minY,
                    width: frame.width,
                    height: referenceFrame.height),
             placeAfter)
        }
        switch section {
        case .visible:
            return hiddenDivider?.frame.map { quartzBoundary($0, placeAfter: true) }
        case .hidden:
            return hiddenDivider?.frame.map { quartzBoundary($0, placeAfter: false) }
        case .alwaysHidden:
            return alwaysHiddenDivider?.frame.map { quartzBoundary($0, placeAfter: false) }
        }
    }

    private func show(_ section: MenuBarOrganizerSection) {
        guard editingCount == 0 else {
            showInMenuBar(section)
            scheduleRehide()
            return
        }
        switch presentation(for: section) {
        case .secondary:
            showSecondaryBar()
        case .smartNotch:
            Task { await showWithSmartNotch(section: section) }
        case .menuBar:
            showInMenuBar(section)
            scheduleRehide()
        }
    }

    private enum PresentationDecision {
        case menuBar
        case secondary
        case smartNotch
    }

    private func showInMenuBar(_ section: MenuBarOrganizerSection) {
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
        refresh(captureImages: false)
    }

    private func presentation(for section: MenuBarOrganizerSection) -> PresentationDecision {
        let mode = MenuBarOrganizerPresentationMode.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerPresentationMode))
        let width = items.filter { item in
            section == .alwaysHidden ? item.section != .visible : item.section == .hidden
        }.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let screen = controlItem?.frame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let available = (screen?.visibleFrame.width ?? 1_024) * 0.45
        let hasNotch = screen?.auxiliaryTopLeftArea != nil || screen?.auxiliaryTopRightArea != nil
        if MenuBarOrganizerSupport.shouldUseSmartNotchMode(
            mode: mode,
            enabled: UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerSmartNotchMode),
            hasNotch: hasNotch) {
            return .smartNotch
        }
        return MenuBarOrganizerSupport.shouldUseSecondaryBar(
            mode: mode, hiddenWidth: width, availableWidth: available, hasNotch: hasNotch)
            ? .secondary
            : .menuBar
    }

    private func showWithSmartNotch(section: MenuBarOrganizerSection) async {
        await restoreNotchBorrowedItems()
        refresh(captureImages: false)
        let hiddenWidth = items.filter { item in
            section == .alwaysHidden ? item.section != .visible : item.section == .hidden
        }.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let screen = controlItem?.frame.flatMap { frame in
            NSScreen.screens.first { $0.frame.intersects(frame) }
        } ?? NSScreen.main
        let available = (screen?.visibleFrame.width ?? 1_024) * 0.45
        let visibleItems = MenuBarOrganizerSupport.orderedItems(items, in: .visible)
            .filter(\.isMovable)
        let borrowCount = MenuBarOrganizerSupport.visibleItemsToBorrowForNotch(
            visibleWidths: visibleItems.map(\.frame.width),
            hiddenWidth: hiddenWidth,
            availableWidth: available)
        guard borrowCount < visibleItems.count else {
            showSecondaryBar()
            return
        }
        if borrowCount > 0 {
            suppressUndo = true
            for item in visibleItems.prefix(borrowCount) {
                refresh(captureImages: false)
                let orderedBefore = MenuBarOrganizerSupport.orderedItems(items, in: .visible)
                let rightNeighbor = orderedBefore.drop(while: { $0.id != item.id }).dropFirst().first?.id
                notchBorrowedItems.append(UndoRecord(itemID: item.id,
                                                     previousSection: .visible,
                                                     previousRightNeighbor: rightNeighbor))
                await performMove(itemID: item.id, before: nil, to: .hidden)
            }
            suppressUndo = false
        }
        showInMenuBar(section)
        scheduleRehide()
    }

    private func hideAllRestoringBorrowedItems() async {
        secondaryPanel?.close()
        groupPanels.values.forEach { $0.close() }
        await restoreNotchBorrowedItems()
        hiddenSectionShown = false
        alwaysHiddenSectionShown = false
        applyDividerState()
        cancelRehide()
        refresh(captureImages: false)
    }

    private func restoreNotchBorrowedItems() async {
        guard !notchBorrowedItems.isEmpty else { return }
        let records = notchBorrowedItems.reversed()
        notchBorrowedItems = []
        suppressUndo = true
        for record in records {
            await performMove(itemID: record.itemID,
                              before: record.previousRightNeighbor,
                              to: record.previousSection)
        }
        suppressUndo = false
        undoRecord = nil
        canUndo = false
    }

    private func scheduleRehide() {
        cancelRehide()
        guard editingCount == 0,
              MenuBarOrganizerRehideMode.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerRehideMode)) == .afterDelay
        else { return }
        let seconds = MenuBarOrganizerSupport.sanitizedRehideDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.menuBarOrganizerRehideDelay))
        rehideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, !self.pointerIsInsideMenuBar() else {
                    self?.scheduleRehide()
                    return
                }
                self.hideAll()
            }
        }
    }

    private func cancelRehide() {
        rehideTimer?.invalidate()
        rehideTimer = nil
    }

    private func installEventMonitors() {
        removeEventMonitors()
        let defaults = UserDefaults.standard
        let hover = defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowOnHover)
        let emptyClick = defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowOnEmptyClick)
        if hover || emptyClick {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.isRunning else { return }
                    if event.type == .mouseMoved, hover {
                        if self.pointerIsInsideMenuBar() {
                            if !self.hiddenSectionShown { self.show(.hidden) }
                        } else if self.hiddenSectionShown {
                            self.scheduleRehide()
                        }
                    } else if event.type == .leftMouseDown, emptyClick,
                              self.pointerIsInsideMenuBar(),
                              !self.pointerIsOverManagedItem() {
                        self.toggleHiddenSection()
                    }
                }
            }
        }
        if defaults.bool(forKey: DefaultsKey.menuBarOrganizerShowOnScroll) {
            globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.pointerIsInsideMenuBar() else { return }
                    self.scrollAccumulator += event.scrollingDeltaY + event.scrollingDeltaX
                    if abs(self.scrollAccumulator) >= 8 {
                        self.scrollAccumulator = 0
                        self.toggleHiddenSection()
                    }
                }
            }
        }
    }

    private func removeEventMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let globalScrollMonitor { NSEvent.removeMonitor(globalScrollMonitor) }
        globalMouseMonitor = nil
        globalScrollMonitor = nil
    }

    private func pointerIsInsideMenuBar() -> Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return point.y >= screen.frame.maxY - height - 2
    }

    private func pointerIsOverManagedItem() -> Bool {
        guard let point = CGEvent(source: nil)?.location else { return false }
        return provider.records().contains { $0.frame.contains(point) }
    }

    private func syncHotkeys() {
        let defaults = UserDefaults.standard
        hotkeys.sync(registrations: [
            (.toggleHidden,
             defaults.bool(forKey: DefaultsKey.menuBarOrganizerToggleShortcutEnabled),
             GlobalShortcut.saved(for: DefaultsKey.menuBarOrganizerToggleShortcut,
                                  fallback: .menuBarOrganizerToggleDefault),
             { [weak self] in self?.toggleHiddenSection() }),
            (.toggleAlwaysHidden,
             MenuBarOrganizerSupport.shouldRegisterAlwaysHiddenShortcut(
                sectionEnabled: defaults.bool(
                    forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled),
                shortcutEnabled: defaults.bool(
                    forKey: DefaultsKey.menuBarOrganizerAlwaysShortcutEnabled)),
             GlobalShortcut.saved(for: DefaultsKey.menuBarOrganizerAlwaysShortcut,
                                  fallback: .menuBarOrganizerAlwaysDefault),
             { [weak self] in self?.toggleAlwaysHiddenSection() }),
            (.search,
             defaults.bool(forKey: DefaultsKey.menuBarOrganizerSearchShortcutEnabled),
             GlobalShortcut.saved(for: DefaultsKey.menuBarOrganizerSearchShortcut,
                                  fallback: .menuBarOrganizerSearchDefault),
             { [weak self] in self?.showSearch() }),
        ])
        hotkeyRegistrationFailed = hotkeys.registrationFailed
    }

    private func loadPresets() {
        presets = MenuBarOrganizerSupport.decodePresets(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerPresets))
        namedPresets = MenuBarOrganizerSupport.decodeNamedPresets(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerNamedPresets))
    }

    private func persistPresets() {
        UserDefaults.standard.set(MenuBarOrganizerSupport.encodePresets(presets),
                                  forKey: DefaultsKey.menuBarOrganizerPresets)
    }

    private func persistNamedPresets() {
        UserDefaults.standard.set(MenuBarOrganizerSupport.encodeNamedPresets(namedPresets),
                                  forKey: DefaultsKey.menuBarOrganizerNamedPresets)
    }

    private func loadGroups() {
        groups = MenuBarOrganizerSupport.decodeGroups(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerGroups))
        customGroups = MenuBarOrganizerSupport.decodeCustomGroups(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarOrganizerCustomGroups))
    }

    private func persistGroups() {
        UserDefaults.standard.set(MenuBarOrganizerSupport.encodeGroups(groups),
                                  forKey: DefaultsKey.menuBarOrganizerGroups)
    }

    private func persistCustomGroups() {
        UserDefaults.standard.set(MenuBarOrganizerSupport.encodeCustomGroups(customGroups),
                                  forKey: DefaultsKey.menuBarOrganizerCustomGroups)
    }

    private func syncGroupStatusItems() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerGroupStatusItems)
        let references = enabled ? groupReferencesWithItems() : []
        let liveReferences = Set(references)
        for reference in groupStatusItems.keys.filter({ !liveReferences.contains($0) }) {
            groupStatusItems[reference]?.removePreservingPosition()
            groupStatusItems.removeValue(forKey: reference)
        }
        guard enabled else { return }
        for reference in references {
            let groupItems = items(inGroup: reference)
            let item = groupStatusItems[reference] ?? MenuBarGroupStatusItem(reference: reference)
            item.onLeftClick = { [weak self] in self?.showGroup(reference: reference) }
            item.onRightClick = { [weak self, weak item] in
                self?.showGroupContextMenu(reference: reference, relativeTo: item)
            }
            item.update(title: title(forGroup: reference),
                        symbolName: symbolName(forGroup: reference),
                        itemCount: groupItems.count,
                        isVisible: true)
            groupStatusItems[reference] = item
        }
    }

    private func syncSpacerItems() {
        let defaults = UserDefaults.standard
        let count = MenuBarOrganizerSupport.sanitizedSpacerCount(
            defaults.integer(forKey: DefaultsKey.menuBarOrganizerSpacerCount))
        let width = CGFloat(MenuBarOrganizerSupport.sanitizedSpacerWidth(
            defaults.integer(forKey: DefaultsKey.menuBarOrganizerSpacerWidth)))
        if spacerItems.count > count {
            for spacer in spacerItems.dropFirst(count) {
                spacer.removePreservingPosition()
            }
            spacerItems = Array(spacerItems.prefix(count))
        }
        while spacerItems.count < count {
            spacerItems.append(MenuBarSpacerItem(index: spacerItems.count, width: width))
        }
        spacerItems.forEach { $0.update(width: width) }
    }

    private func evaluateAutomationTriggers() {
        guard isRunning, editingCount == 0, automationTask?.isCancelled != false else { return }
        let defaults = UserDefaults.standard
        let battery = SystemInfo.batterySnapshot()
        let components = Calendar.current.dateComponents([.hour, .weekday], from: Date())
        let hour = components.hour ?? 0
        let weekday = components.weekday ?? 1
        let match: (String, MenuBarOrganizerPresetSlot)?
        if defaults.bool(forKey: DefaultsKey.menuBarOrganizerTriggerLowBatteryEnabled),
           MenuBarOrganizerSupport.lowBatteryTriggerMatches(
                percent: battery?.percent,
                isOnBattery: battery?.isOnBattery ?? false,
                threshold: defaults.integer(forKey: DefaultsKey.menuBarOrganizerTriggerLowBatteryThreshold)),
           let slot = MenuBarOrganizerPresetSlot(
                rawValue: defaults.string(forKey: DefaultsKey.menuBarOrganizerTriggerLowBatteryPreset) ?? "") {
            match = ("lowBattery", slot)
        } else if defaults.bool(forKey: DefaultsKey.menuBarOrganizerTriggerExternalDisplayEnabled),
                  hasExternalDisplay(),
                  let slot = MenuBarOrganizerPresetSlot(
                    rawValue: defaults.string(forKey: DefaultsKey.menuBarOrganizerTriggerExternalDisplayPreset) ?? "") {
            match = ("externalDisplay", slot)
        } else if defaults.bool(forKey: DefaultsKey.menuBarOrganizerTriggerWorkHoursEnabled),
                  MenuBarOrganizerSupport.workHoursTriggerMatches(
                    hour: hour,
                    weekday: weekday,
                    startHour: defaults.integer(forKey: DefaultsKey.menuBarOrganizerTriggerWorkHoursStart),
                    endHour: defaults.integer(forKey: DefaultsKey.menuBarOrganizerTriggerWorkHoursEnd),
                    weekdaysOnly: defaults.bool(
                        forKey: DefaultsKey.menuBarOrganizerTriggerWorkHoursWeekdaysOnly)),
                  let slot = MenuBarOrganizerPresetSlot(
                    rawValue: defaults.string(forKey: DefaultsKey.menuBarOrganizerTriggerWorkHoursPreset) ?? "") {
            match = ("workHours", slot)
        } else if defaults.bool(forKey: DefaultsKey.menuBarOrganizerTriggerChargingEnabled),
                  battery?.isCharging == true || battery?.isOnBattery == false,
                  let slot = MenuBarOrganizerPresetSlot(
                    rawValue: defaults.string(forKey: DefaultsKey.menuBarOrganizerTriggerChargingPreset) ?? "") {
            match = ("charging", slot)
        } else {
            match = nil
        }

        guard let match else {
            lastAutomationSignature = nil
            return
        }
        let signature = "\(match.0):\(match.1.rawValue)"
        guard signature != lastAutomationSignature, let preset = presets[match.1] else { return }
        lastAutomationSignature = signature
        automationTask = Task { [weak self] in
            guard let self else { return }
            await self.applyPreset(preset)
            self.automationTask = nil
        }
    }

    private func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return KeepAwakeAutomationSupport.hasExternalDisplay(
            builtInFlags: displays.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 })
    }

    private func applyGroupedItemVisibilityPreference(itemIDs: [MenuBarItemIdentity]? = nil) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAutoHideGroupedItems) else {
            groupAutoHideTask?.cancel()
            groupAutoHideTask = nil
            return
        }
        groupAutoHideTask?.cancel()
        groupAutoHideTask = Task { [weak self] in
            guard let self else { return }
            await self.hideGroupedVisibleItems(itemIDs: itemIDs)
        }
    }

    private func hideGroupedVisibleItems(itemIDs: [MenuBarItemIdentity]?) async {
        refresh(captureImages: false)
        let allGroupedIDs = MenuBarOrganizerGroupSlot.allCases.flatMap { groups[$0]?.items ?? [] }
            + customGroups.flatMap(\.items)
        let groupedIDs = Set(itemIDs ?? allGroupedIDs)
        let candidates = MenuBarOrganizerSupport.orderedItems(items, in: .visible)
            .filter { groupedIDs.contains($0.id) && $0.isMovable }
        guard !candidates.isEmpty else { return }
        suppressUndo = true
        for item in candidates {
            guard !Task.isCancelled else { break }
            await performMove(itemID: item.id, before: nil, to: .hidden)
        }
        suppressUndo = false
        undoRecord = nil
        canUndo = false
        refresh()
        scheduleRehide()
    }

    private func removeFromGroup(itemID: MenuBarItemIdentity, persists: Bool) {
        var changed = false
        var customChanged = false
        for slot in MenuBarOrganizerGroupSlot.allCases {
            guard var group = groups[slot] else { continue }
            let originalCount = group.items.count
            group.items.removeAll { $0 == itemID }
            guard group.items.count != originalCount else { continue }
            changed = true
            if group.items.isEmpty {
                groups.removeValue(forKey: slot)
                let reference = MenuBarOrganizerGroupReference.slot(slot)
                groupPanels[reference]?.close()
                groupPanels.removeValue(forKey: reference)
            } else {
                groups[slot] = MenuBarOrganizerSupport.group(slot: slot, items: group.items)
            }
        }
        for index in customGroups.indices {
            let originalCount = customGroups[index].items.count
            customGroups[index].items.removeAll { $0 == itemID }
            guard customGroups[index].items.count != originalCount else { continue }
            changed = true
            customChanged = true
            let reference = MenuBarOrganizerGroupReference.custom(customGroups[index].id)
            if customGroups[index].items.isEmpty {
                groupPanels[reference]?.close()
                groupPanels.removeValue(forKey: reference)
            }
        }
        if changed, persists {
            persistGroups()
            if customChanged { persistCustomGroups() }
            syncGroupStatusItems()
        }
    }

    private func applyPreset(_ preset: MenuBarOrganizerPreset) async {
        await applyPresetItems(
            visible: preset.visible,
            hidden: preset.hidden,
            alwaysHidden: preset.alwaysHidden)
    }

    private func applyNamedPreset(_ preset: MenuBarOrganizerNamedPreset) async {
        await applyPresetItems(
            visible: preset.visible,
            hidden: preset.hidden,
            alwaysHidden: preset.alwaysHidden)
    }

    private func applyPresetItems(visible: [MenuBarItemIdentity],
                                  hidden: [MenuBarItemIdentity],
                                  alwaysHidden: [MenuBarItemIdentity]) async {
        await restoreNotchBorrowedItems()
        if !alwaysHidden.isEmpty,
           !UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) {
            UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled)
            syncAlwaysHiddenDivider()
        }
        showInMenuBar(.alwaysHidden)
        try? await Task.sleep(for: .milliseconds(120))
        refresh(captureImages: false)
        suppressUndo = true
        for section in [MenuBarOrganizerSection.alwaysHidden, .hidden, .visible] {
            var nextID: MenuBarItemIdentity?
            let ids: [MenuBarItemIdentity]
            switch section {
            case .visible: ids = visible
            case .hidden: ids = hidden
            case .alwaysHidden: ids = alwaysHidden
            }
            for id in ids.reversed() {
                refresh(captureImages: false)
                guard items.contains(where: { $0.id == id && $0.isMovable }) else { continue }
                await performMove(itemID: id, before: nextID, to: section)
                nextID = id
            }
        }
        suppressUndo = false
        undoRecord = nil
        canUndo = false
        refresh()
        scheduleRehide()
    }

    private func loadSnapshots(records: [MenuBarOrganizerWindowRecord],
                               identities: [CGWindowID: MenuBarItemIdentity]) {
        snapshotTask?.cancel()
        let missing = records.filter {
            guard let identity = identities[$0.windowID] else { return false }
            return imageCache[identity] == nil
        }
        guard !missing.isEmpty else { return }
        snapshotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for record in missing {
                guard !Task.isCancelled,
                      let identity = identities[record.windowID],
                      let image = await provider.image(for: record.windowID)
                else { continue }
                imageCache[identity] = image
                if let index = items.firstIndex(where: { $0.id == identity }) {
                    let item = items[index]
                    items[index] = ManagedMenuBarItem(
                        id: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
                        ownerName: item.ownerName, bundleIdentifier: item.bundleIdentifier,
                        title: item.title, frame: item.frame, section: item.section,
                        isMovable: item.isMovable, isProtected: item.isProtected, image: image)
                }
            }
        }
    }

    private func showContextMenu(relativeTo item: MenuBarDividerItem?) {
        guard let button = item?.statusItem.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: hiddenSectionShown ? "Hide hidden items" : "Show hidden items",
                     action: #selector(contextToggleHidden),
                     keyEquivalent: "")
        if UserDefaults.standard.bool(forKey: DefaultsKey.menuBarOrganizerAlwaysHiddenEnabled) {
            menu.addItem(withTitle: alwaysHiddenSectionShown ? "Hide always-hidden items" : "Show always-hidden items",
                         action: #selector(contextToggleAlways),
                         keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Search menu bar items",
                     action: #selector(contextSearch),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Show secondary bar",
                     action: #selector(contextSecondary),
                     keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Menu Bar Settings…",
                     action: #selector(contextSettings),
                     keyEquivalent: "")
        for menuItem in menu.items { menuItem.target = self }
        item?.statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { item?.statusItem.menu = nil }
    }

    private func showGroupContextMenu(reference: MenuBarOrganizerGroupReference,
                                      relativeTo item: MenuBarGroupStatusItem?) {
        guard let button = item?.statusItem.button else { return }
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open \(title(forGroup: reference))",
                                action: #selector(contextOpenGroup(_:)),
                                keyEquivalent: "")
        open.representedObject = reference.id
        let groupItems = items(inGroup: reference)
        if !groupItems.isEmpty {
            menu.addItem(.separator())
            for groupItem in groupItems {
                let menuItem = menu.addItem(withTitle: groupItem.displayName,
                                            action: #selector(contextActivateGroupItem(_:)),
                                            keyEquivalent: "")
                menuItem.representedObject = groupItem.id.storageValue
            }
        }
        menu.addItem(.separator())
        let clear = menu.addItem(withTitle: "Clear group",
                                 action: #selector(contextClearGroup(_:)),
                                 keyEquivalent: "")
        clear.representedObject = reference.id
        menu.addItem(withTitle: "Menu Bar Settings…",
                     action: #selector(contextSettings),
                     keyEquivalent: "")
        for menuItem in menu.items { menuItem.target = self }
        item?.statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { item?.statusItem.menu = nil }
    }

    private func groupTitle(_ slot: MenuBarOrganizerGroupSlot) -> String {
        let text = FeatureStrings.menuBarOrganizer(L10n.shared.language)
        switch slot {
        case .cloud: return text.groupCloud
        case .audio: return text.groupAudio
        case .work: return text.groupWork
        case .custom: return text.groupCustom
        }
    }

    @objc private func contextToggleHidden() { toggleHiddenSection() }
    @objc private func contextToggleAlways() { toggleAlwaysHiddenSection() }
    @objc private func contextSearch() { showSearch() }
    @objc private func contextSecondary() { showSecondaryBar() }
    @objc private func contextOpenGroup(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let reference = MenuBarOrganizerGroupReference(storageValue: raw)
        else { return }
        showGroup(reference: reference)
    }
    @objc private func contextActivateGroupItem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let item = items.first(where: { $0.id.storageValue == raw })
        else { return }
        activate(itemID: item.id)
    }
    @objc private func contextClearGroup(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let reference = MenuBarOrganizerGroupReference(storageValue: raw)
        else { return }
        clearGroup(reference: reference)
    }
    @objc private func contextSettings() {
        SettingsRouter.shared.page = .menuBarOrganizer
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}
