// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import Foundation

/// Owns native status items and stops background work when disabled.
final class MenuBarHiderService: NSResponder, ObservableObject {
    static let shared = MenuBarHiderService()

    @Published private(set) var isCollapsed: Bool = false
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var isConfiguring: Bool = false
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var shortcutConflict: GlobalShortcutRole?
    private var autoCollapseGeneration: UInt64 = 0
    private var recoveryHoldsExpansion = false
    private var organizerHoldsExpansion = false

    private var toggleItem: NSStatusItem?
    private var physicalSeparatorItem: NSStatusItem?
    private var physicalAlwaysHiddenItem: NSStatusItem?
    private static let swappedRolesKey = "menuBarHiderSeparatorRolesSwapped"
    private var separatorRolesSwapped = UserDefaults.standard.bool(forKey: swappedRolesKey)
    private var separatorItem: NSStatusItem? {
        separatorRolesSwapped ? physicalAlwaysHiddenItem : physicalSeparatorItem
    }
    private var alwaysHiddenItem: NSStatusItem? {
        separatorRolesSwapped ? physicalSeparatorItem : physicalAlwaysHiddenItem
    }

    private var autoCollapseTimer: Timer?
    private var hoverWatchdogTimer: Timer?
    private var didExpandFromHover = false
    private var pointerLeftToggleAt: TimeInterval?
    private let hotkey = QuickToolHotkey(id: 30)
    private var trackingArea: NSTrackingArea?
    private weak var trackingButton: NSStatusBarButton?
    private var scrollMonitor: Any?
    private var separatorDragMonitor: Any?
    private var localSeparatorDragMonitor: Any?
    private var separatorMouseMoveMonitor: Any?
    private var localSeparatorMouseMoveMonitor: Any?
    private var isReorderingItems = false
    private var separatorMeasurementPending = false
    private var separatorMeasurementGeneration: UInt64 = 0
    private var separatorMeasurementRequested = false
    private var lastObservedPlacement: [Double?]?
    private var lastScrollToggleTime: TimeInterval = 0
    private var lastToggleClickTimestamp: TimeInterval = 0

    override private init() {
        super.init()
        hotkey.onPress = { [weak self] in
            self?.toggle()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(statusItemPlacementChanged),
            name: UserDefaults.didChangeNotification, object: UserDefaults.standard
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        autoCollapseTimer?.invalidate()
        hoverWatchdogTimer?.invalidate()
        removeScrollMonitor()
        removeSeparatorDragMonitor()
    }

    // MARK: - Lifecycle & Preferences Sync

    func syncWithPreferences() {
        let isAvailable = AppFeature.menuBarHider.isAvailable
        let enabled = isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderEnabled)
        isEnabled = enabled

        syncHotkey()
        if !enabled { syncOrganizer() }

        if enabled {
            installOrUpdateItems()
            setupScrollMonitor()
            setupSeparatorDragMonitor()
            // Arm the idle timer for the state we are actually in. Installing
            // the items does not do it, so a relaunch that restores an expanded
            // bar never collapsed, and switching auto-collapse on only took
            // effect after the next manual expand.
            if !isCollapsed && !isConfiguring {
                restartAutoCollapseTimerIfNeeded()
            }
        } else {
            teardown()
        }
        if enabled { syncOrganizer() }
    }

    // Read only our own controls. WindowServer coordinates are used by the
    // advanced backend, and AppKit coordinates anchor its floating panel.
    var organizerAnchor: CGRect? { toggleItem?.button?.window?.frame }

    @MainActor func organizerGeometry() async -> (hidden: CGRect, always: CGRect?, excluded: Set<CGWindowID>)? {
        guard isEnabled, MenuBarOrganizerPolicy.supportsAdvancedBackend else { return nil }
        func windowID(_ item: NSStatusItem?) -> CGWindowID? {
            item?.button?.window.flatMap { MenuBarHiderSupport.statusWindowID($0.windowNumber) }
        }
        let maximumSpacerWidth = (NSScreen.screens.map { $0.frame.width }.max()
            ?? MenuBarHiderSupport.fallbackUsableWidth) + MenuBarHiderSupport.expansionMargin
        let ids = [windowID(toggleItem), windowID(physicalSeparatorItem), windowID(physicalAlwaysHiddenItem)]
        if let hiddenID = windowID(separatorItem), let alwaysID = windowID(alwaysHiddenItem),
           let hidden = MenuBarWindowServerBridge.frame(of: hiddenID),
           let always = MenuBarWindowServerBridge.frame(of: alwaysID),
           MenuBarOrganizerPolicy.validSpacerFrame(hidden, maximumWidth: maximumSpacerWidth),
           MenuBarOrganizerPolicy.validSpacerFrame(always, maximumWidth: maximumSpacerWidth) {
            return (hidden, always, Set(ids.compactMap { $0 }))
        }
        // System-hosted status items can have placeholder NSWindow numbers.
        // Resolve our labelled controls through AX instead of using cached frames.
        guard AXIsProcessTrusted(),
              let normalHelp = separatorItem?.button?.toolTip,
              let permanentHelp = alwaysHiddenItem?.button?.toolTip else { return nil }
        let pids = MenuBarHiderAccessibility.hostPIDs(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            runningPIDs: { NSRunningApplication.runningApplications(withBundleIdentifier: $0).map(\.processIdentifier) })
        let expectedGeneration = separatorMeasurementGeneration
        let expectedRoles = separatorRolesSwapped
        let positions = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: MenuBarHiderAccessibility.separatorPositions(
                    pids: pids, normalHelp: normalHelp, permanentHelp: permanentHelp))
            }
        }
        guard isEnabled, !Task.isCancelled, expectedGeneration == separatorMeasurementGeneration,
              expectedRoles == separatorRolesSwapped, let positions,
              MenuBarOrganizerPolicy.validSpacerFrame(positions.normal, maximumWidth: maximumSpacerWidth),
              MenuBarOrganizerPolicy.validSpacerFrame(positions.permanent, maximumWidth: maximumSpacerWidth) else { return nil }
        var excluded = Set(ids.compactMap { $0 })
        for id in MenuBarWindowServerBridge.menuBarWindowIDs() ?? [] {
            guard let frame = MenuBarWindowServerBridge.frame(of: id) else { continue }
            if frame == positions.normal || frame == positions.permanent { excluded.insert(id) }
        }
        return (positions.normal, positions.permanent, excluded)
    }

    func resumeAfterOrganizerOperation() {
        guard isEnabled, !isConfiguring else { return }
        restartAutoCollapseTimerIfNeeded()
    }

    private func syncOrganizer() {
        if Thread.isMainThread {
            MainActor.assumeIsolated { MenuBarOrganizerService.shared.syncWithPreferences() }
        } else {
            DispatchQueue.main.async { MenuBarOrganizerService.shared.syncWithPreferences() }
        }
    }

    func beginOrganizerOperation() {
        organizerHoldsExpansion = true
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
    }

    func endOrganizerOperation(resume: Bool) {
        organizerHoldsExpansion = false
        if resume { resumeAfterOrganizerOperation() }
    }

    var organizerDisplayState: MenuBarHiderSupport.DisplayState {
        isCollapsed ? .collapsed : .expanded
    }

    func restoreAfterOrganizerActivation(_ state: MenuBarHiderSupport.DisplayState) {
        endOrganizerOperation(resume: false)
        guard isEnabled, !isConfiguring else { return }
        switch state {
        case .collapsed: collapse()
        case .expanded: expand()
        }
    }

    func resetSeparatorPositions() {
        guard isEnabled, !organizerHoldsExpansion else { return }
        teardown()
        separatorRolesSwapped = false
        UserDefaults.standard.removeObject(forKey: Self.swappedRolesKey)
        syncHotkey()
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(MenuBarHiderSupport.toggleAutosaveName)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(MenuBarHiderSupport.separatorAutosaveName)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(MenuBarHiderSupport.alwaysHiddenAutosaveName)")
        UserDefaults.standard.synchronize()
        installOrUpdateItems()
        setupScrollMonitor()
        setupSeparatorDragMonitor()
        beginConfigurationMode()
        triggerHapticFeedback()
    }

    private func syncHotkey() {
        let enabled = isEnabled && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.menuBarHiderShortcut,
                                            fallback: .menuBarHiderDefault)
        // Keep saved combinations, including the former default. A conflict
        // must be resolved explicitly in Settings rather than rewriting a
        // shortcut that may have been chosen deliberately.
        shortcutConflict = enabled ? GlobalShortcutRole.conflict(
            for: shortcut, excluding: .menuBarHider, includeInactive: true) : nil
        shortcutRegistrationFailed = !hotkey.sync(
            enabled: enabled && shortcutConflict == nil,
            shortcut: shortcut, storageKey: DefaultsKey.menuBarHiderShortcut)
    }

    private func installOrUpdateItems() {
        var didCreateToggle = false

        // 1. Toggle Item
        if toggleItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = MenuBarHiderSupport.toggleAutosaveName
            item.behavior = []
            item.isVisible = true
            toggleItem = item
            didCreateToggle = true
        }

        // 2. Main Separator Item
        if physicalSeparatorItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: CGFloat(MenuBarHiderSupport.normalSeparatorWidth))
            item.autosaveName = MenuBarHiderSupport.separatorAutosaveName
            item.behavior = []
            item.isVisible = true
            physicalSeparatorItem = item
        }

        // The third category is always present, including with legacy preferences.
        if physicalAlwaysHiddenItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: CGFloat(MenuBarHiderSupport.normalAlwaysHiddenWidth))
            item.autosaveName = MenuBarHiderSupport.alwaysHiddenAutosaveName
            item.behavior = []
            item.isVisible = true
            physicalAlwaysHiddenItem = item
        }

        // Pick the collapse state back up from the previous run, but only when
        // the items were just created: syncWithPreferences() runs on every
        // settings change and must not clobber the state on screen right now.
        if didCreateToggle {
            isCollapsed = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderCollapsed)
        }

        repairSeparatorOrder()
        configureItemButtons()
        updateItemAppearances()
    }

    private func setupSeparatorDragMonitor() {
        guard isEnabled else {
            removeSeparatorDragMonitor()
            return
        }
        guard separatorDragMonitor == nil, localSeparatorDragMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .leftMouseUp]
        localSeparatorDragMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleReorderingEvent(event)
            return event
        }
        separatorDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleReorderingEvent(event)
        }
        syncSeparatorMouseMoveMonitor(commandHeld: NSEvent.modifierFlags.contains(.command))
    }

    private func syncSeparatorMouseMoveMonitor(commandHeld: Bool) {
        guard isEnabled, commandHeld else {
            if let separatorMouseMoveMonitor { NSEvent.removeMonitor(separatorMouseMoveMonitor) }
            if let localSeparatorMouseMoveMonitor { NSEvent.removeMonitor(localSeparatorMouseMoveMonitor) }
            separatorMouseMoveMonitor = nil
            localSeparatorMouseMoveMonitor = nil
            return
        }
        guard separatorMouseMoveMonitor == nil, localSeparatorMouseMoveMonitor == nil else { return }
        localSeparatorMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleReorderingEvent(event)
            return event
        }
        separatorMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleReorderingEvent(event)
        }
    }

    private func handleReorderingEvent(_ event: NSEvent) {
        let commandHeld = event.modifierFlags.contains(.command)
        syncSeparatorMouseMoveMonitor(commandHeld: commandHeld)
        guard commandHeld else { setReorderingItems(false); return }
        let onMenuBar = MenuBarHiderSupport.pointerIsOnMenuBar(
            NSEvent.mouseLocation, screenFrames: NSScreen.screens.map(\.frame),
            barHeight: NSStatusBar.system.thickness)
        // Compact before mouse-down, never resize the item under an active drag.
        // Once started, keep this layout until Command is released.
        setReorderingItems(commandHeld && (onMenuBar || isReorderingItems))
        if event.type == .leftMouseUp, commandHeld {
            DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
        }
    }

    private func setReorderingItems(_ active: Bool) {
        guard isEnabled, active != isReorderingItems else { return }
        isReorderingItems = active
        if active {
            stopAutoCollapseTimer()
            stopHoverWatchdog()
        }
        updateItemAppearances()
        if !active {
            repairSeparatorOrder()
            if !isConfiguring {
                restartAutoCollapseTimerIfNeeded()
                if didExpandFromHover && !isCollapsed { startHoverWatchdog() }
            }
        }
    }

    private func removeSeparatorDragMonitor() {
        syncSeparatorMouseMoveMonitor(commandHeld: false)
        if let separatorDragMonitor { NSEvent.removeMonitor(separatorDragMonitor) }
        separatorDragMonitor = nil
        if let localSeparatorDragMonitor { NSEvent.removeMonitor(localSeparatorDragMonitor) }
        localSeparatorDragMonitor = nil
        isReorderingItems = false
    }

    @objc private func statusItemPlacementChanged() {
        // Preference notifications may arrive outside the main thread. Do not
        // touch AppKit there, and do not install an idle polling timer.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Every preference write in the app lands here, including timers
            // that persist state. Measure only when hider placement moved.
            let placement = MenuBarHiderSupport.placementSnapshot(in: UserDefaults.standard)
            guard placement != self.lastObservedPlacement else { return }
            self.lastObservedPlacement = placement
            self.repairSeparatorOrder()
        }
    }

    private func repairSeparatorOrder() {
        guard isEnabled, physicalSeparatorItem != nil, physicalAlwaysHiddenItem != nil else { return }
        // Saved positions can be stale on MenuBarAgent systems. Read the
        // rendered controls first instead of treating remembered placement as
        // proof that their current order is correct.
        if requestRenderedSeparatorOrder() { return }
        applyFallbackSeparatorOrder()
    }

    /// Widened spacer windows are not reliable evidence of placement.
    /// Use remembered ordering when rendered geometry cannot establish it.
    private func applyFallbackSeparatorOrder() {
        if let swapped = MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: UserDefaults.standard) {
            applySeparatorOrder(swapped: swapped)
            return
        }
    }

    private func applySeparatorOrder(swapped: Bool) {
        guard isEnabled, physicalSeparatorItem != nil, physicalAlwaysHiddenItem != nil,
              swapped != separatorRolesSwapped else { return }
        separatorRolesSwapped = swapped
        UserDefaults.standard.set(swapped, forKey: Self.swappedRolesKey)
        updateItemAppearances()
    }

    private func requestRenderedSeparatorOrder() -> Bool {
        if separatorMeasurementPending {
            // A drag can land while the previous read is in flight. Read again
            // afterwards rather than trusting geometry from before the drop.
            separatorMeasurementRequested = true
            return true
        }
        #if VORSSAINT_DEVELOPMENT
        NSLog("MenuBarHider geometry trusted=%@ normal=%@ permanent=%@",
              AXIsProcessTrusted() ? "yes" : "no",
              String(describing: physicalSeparatorItem?.button?.accessibilityFrame()),
              String(describing: physicalAlwaysHiddenItem?.button?.accessibilityFrame()))
        #endif
        guard AXIsProcessTrusted(),
              let normalHelp = physicalSeparatorItem?.button?.toolTip,
              let permanentHelp = physicalAlwaysHiddenItem?.button?.toolTip else { return false }
        let pids = MenuBarHiderAccessibility.hostPIDs(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            runningPIDs: { bundleID in
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
            })
        separatorMeasurementPending = true
        separatorMeasurementRequested = false
        let generation = separatorMeasurementGeneration
        let observedRoles = separatorRolesSwapped
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let positions = MenuBarHiderAccessibility.separatorPositions(
                pids: pids, normalHelp: normalHelp, permanentHelp: permanentHelp)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.separatorMeasurementGeneration else { return }
                self.separatorMeasurementPending = false
                if self.separatorMeasurementRequested {
                    self.repairSeparatorOrder()
                    return
                }
                guard observedRoles == self.separatorRolesSwapped else { return }
                #if VORSSAINT_DEVELOPMENT
                NSLog("MenuBarHider geometry measured=%@", String(describing: positions))
                #endif
                if let positions {
                    // Found but expanded: leave the roles alone rather than
                    // guess, or the next layout pass would undo this one.
                    if let swapped = MenuBarHiderSupport.renderedSeparatorRolesSwapped(
                        normal: positions.normal, permanent: positions.permanent) {
                        self.applySeparatorOrder(swapped: swapped)
                    }
                } else {
                    self.applyFallbackSeparatorOrder()
                }
            }
        }
        return true
    }

    private func visibleStatusItemX(_ item: NSStatusItem) -> CGFloat? {
        guard let window = item.button?.window,
              let windowID = MenuBarHiderSupport.statusWindowID(window.windowNumber),
              let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
              let entry = info.first(where: { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }),
              entry[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              rect.width > 0 else { return nil }
        // Window-server bounds, never cached NSWindow.frame coordinates.
        return rect.midX
    }

    private func configureItemButtons() {
        let strings = FeatureStrings.menuBarHider(L10n.shared.language)
        if let button = toggleItem?.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let image = NSImage(systemSymbolName: "circle", accessibilityDescription: strings.pageTitle)
            image?.isTemplate = true
            button.image = image
            button.title = image == nil ? "○" : ""
            button.toolTip = MenuBarHiderSupport.toggleTooltip(isCollapsed: isCollapsed, strings: strings)
            button.setAccessibilityLabel(button.toolTip)
            setupTrackingArea()
        }
        // Native spacer items do the concealment; the circle is the only control.
        for (item, label) in [(separatorItem, strings.diagramHidden),
                              (alwaysHiddenItem, strings.diagramAlwaysHidden)] {
            item?.button?.target = nil
            item?.button?.action = nil
            item?.button?.image = nil
            item?.button?.title = ""
            item?.button?.toolTip = "\(strings.pageTitle) — \(label)"
        }
    }

    private func teardown() {
        separatorMeasurementGeneration &+= 1
        separatorMeasurementPending = false
        hotkey.unregister()
        shortcutRegistrationFailed = false
        shortcutConflict = nil
        recoveryHoldsExpansion = false
        organizerHoldsExpansion = false
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
        removeTrackingArea()
        removeScrollMonitor()
        removeSeparatorDragMonitor()
        if let toggleItem {
            NSStatusBar.system.removeStatusItem(toggleItem)
            self.toggleItem = nil
        }
        if let physicalSeparatorItem {
            NSStatusBar.system.removeStatusItem(physicalSeparatorItem)
            self.physicalSeparatorItem = nil
        }
        if let physicalAlwaysHiddenItem {
            NSStatusBar.system.removeStatusItem(physicalAlwaysHiddenItem)
            self.physicalAlwaysHiddenItem = nil
        }
        isCollapsed = false
        isConfiguring = false
    }

    // MARK: - Haptic Feedback

    private func triggerHapticFeedback() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderHapticFeedback) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    // MARK: - State Management

    func toggle() {
        guard isEnabled, !organizerHoldsExpansion else { return }
        recoveryHoldsExpansion = false
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func expand(startTimer: Bool = true) {
        guard isEnabled, !organizerHoldsExpansion else { return }
        repairSeparatorOrder()
        recoveryHoldsExpansion = false
        stopHoverWatchdog()
        didExpandFromHover = false
        let wasCollapsed = isCollapsed
        isCollapsed = false
        updateItemAppearances()
        persistCollapsedState()
        if wasCollapsed {
            triggerHapticFeedback()
        }

        if startTimer && !isConfiguring {
            restartAutoCollapseTimerIfNeeded()
        } else {
            stopAutoCollapseTimer()
        }
    }

    func collapse() {
        guard isEnabled, !organizerHoldsExpansion else { return }
        recoveryHoldsExpansion = false
        repairSeparatorOrder()
        let wasExpanded = !isCollapsed
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
        isCollapsed = true
        updateItemAppearances()
        persistCollapsedState()
        if wasExpanded {
            triggerHapticFeedback()
        }
    }

    func prepareForOrganizerOperation() {
        guard isEnabled else { return }
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
        isCollapsed = false
        updateItemAppearances()
        persistCollapsedState()
    }

    func beginConfigurationMode() {
        guard isEnabled else { return }
        // Editing never reveals either category or changes the saved display mode.
        isConfiguring = true
        recoveryHoldsExpansion = false
        stopAutoCollapseTimer()
    }

    func endConfigurationMode() {
        guard isConfiguring else { return }
        isConfiguring = false
        if !isCollapsed {
            restartAutoCollapseTimerIfNeeded()
        }
    }

    /// Keep Hidden reachable after failed input. Always Hidden stays concealed.
    func revealForStatusItemRecovery() {
        guard isEnabled else { return }
        prepareForOrganizerOperation()
        recoveryHoldsExpansion = true
    }

    /// Carries the normal hidden section’s display state across relaunches.
    private func persistCollapsedState() {
        UserDefaults.standard.set(isCollapsed, forKey: DefaultsKey.menuBarHiderCollapsed)
    }


    private var currentDisplayState: MenuBarHiderSupport.DisplayState {
        isCollapsed ? .collapsed : .expanded
    }

    /// Width of the menu bar strip the status items actually occupy. On a
    /// notched Mac that is the area left of the notch, which is far narrower
    /// than the screen; sizing the separators off `frame.width` there asks for
    /// an item many times wider than the bar it lives in.
    private var usableMenuBarWidth: Double {
        guard let screen = toggleItem?.button?.window?.screen ?? NSScreen.main else {
            return MenuBarHiderSupport.fallbackUsableWidth
        }
        if let leftOfNotch = screen.auxiliaryTopLeftArea {
            return Double(leftOfNotch.width)
        }
        return Double(screen.frame.width)
    }

    private func updateItemAppearances() {
        configureItemButtons()

        let state: MenuBarHiderSupport.DisplayState = isReorderingItems ? .expanded : currentDisplayState
        let width = usableMenuBarWidth

        toggleItem?.length = NSStatusItem.variableLength

        // Update main separator length
        if let separatorItem {
            let length = MenuBarHiderSupport.separatorLength(state: state, usableWidth: width)
            separatorItem.length = CGFloat(length)
        }

        // Update always-hidden separator length
        if let alwaysHiddenItem {
            let length = MenuBarHiderSupport.alwaysHiddenLength(state: state, usableWidth: width, isEnabled: true)
            alwaysHiddenItem.length = CGFloat(length)
        }
    }

    @objc private func screenParametersChanged() {
        guard isEnabled else { return }
        updateItemAppearances()
    }

    // MARK: - Tracking Area & Hover

    private func setupTrackingArea() {
        guard let button = toggleItem?.button else { return }
        // Rebuilding this on every appearance update tore the area down with the
        // cursor inside it and installed a fresh one, which AppKit does not
        // consider entered — so the matching mouseExited never arrived and a
        // hover-expanded bar stayed open. The area tracks `inVisibleRect`, so it
        // follows the button through length changes on its own.
        if trackingArea != nil, trackingButton === button { return }
        removeTrackingArea()
        let area = NSTrackingArea(rect: button.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        button.addTrackingArea(area)
        trackingArea = area
        trackingButton = button
    }

    private func removeTrackingArea() {
        // Remove the area from the button that received it, even if AppKit
        // has replaced the current status button during layout.
        if let trackingArea, let trackingButton {
            trackingButton.removeTrackingArea(trackingArea)
        }
        trackingArea = nil
        trackingButton = nil
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else { return }
        // Deliberately does not stop the watchdog: re-entering a bar that hover
        // already opened would otherwise leave it with nothing watching, and it
        // would never close again. The watchdog clears its own timestamp when it
        // sees the pointer back inside.
        let expandOnHover = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderExpandOnHover)
        if expandOnHover, isCollapsed {
            expand(startTimer: true)
            // Set after expanding: expand() clears the flag so that a bar opened
            // any other way is not closed by the cursor wandering off.
            didExpandFromHover = true
            startHoverWatchdog()
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard isEnabled else { return }
        guard !isCollapsed, !isConfiguring else { return }
        if didExpandFromHover { return }
        restartAutoCollapseTimerIfNeeded()
    }

    /// Watches where the pointer actually is while the bar is open on hover.
    ///
    /// Opening on hover has to close on leave, and mouseExited alone cannot
    /// carry that: expanding changes the status item lengths, and AppKit is free
    /// to rebuild the item windows underneath, so the exit event for the button
    /// the cursor started on may never arrive. Asking for the pointer position
    /// does not depend on any of that. It runs only while a hover-opened bar is
    /// showing and stops the moment it closes.
    private func startHoverWatchdog() {
        stopHoverWatchdog()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.collapseIfPointerLeftToggle()
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        hoverWatchdogTimer = timer
    }

    private func collapseIfPointerLeftToggle() {
        guard isEnabled, didExpandFromHover, !isConfiguring, !isCollapsed else {
            stopHoverWatchdog()
            return
        }
        // Keep icons usable while the pointer travels from the toggle to an
        // item. Screen bounds describe the menu-bar band; no status window
        // origin is consulted after macOS slides or rebuilds the items.
        if MenuBarHiderSupport.pointerIsOnMenuBar(
            NSEvent.mouseLocation, screenFrames: NSScreen.screens.map(\.frame),
            barHeight: NSStatusBar.system.thickness) {
            pointerLeftToggleAt = nil
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let leftAt = pointerLeftToggleAt else {
            pointerLeftToggleAt = now
            return
        }
        // Grace period so brushing past on the way somewhere else does not
        // snap the bar shut.
        if now - leftAt >= MenuBarHiderSupport.hoverCollapseDelay {
            stopHoverWatchdog()
            collapse()
        }
    }

    private func stopHoverWatchdog() {
        hoverWatchdogTimer?.invalidate()
        hoverWatchdogTimer = nil
        pointerLeftToggleAt = nil
    }

    // MARK: - Scroll to Toggle

    private func setupScrollMonitor() {
        guard isEnabled, UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderScrollToToggle) else {
            removeScrollMonitor()
            return
        }
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScrollEvent(event)
            return event
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        let scrollToToggle = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderScrollToToggle)
        guard scrollToToggle else { return }
        guard let button = toggleItem?.button, let window = button.window,
              event.window === window,
              button.bounds.contains(button.convert(event.locationInWindow, from: nil))
        else { return }

        let delta = abs(event.scrollingDeltaY) > 0 ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(delta) > 1.5 else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastScrollToggleTime > 0.35 else { return }
        lastScrollToggleTime = now

        DispatchQueue.main.async { [weak self, weak button] in
            guard let self, let button, self.toggleItem?.button === button,
                  self.isEnabled, !self.isConfiguring,
                  UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderScrollToToggle)
            else { return }
            if delta > 0 {
                if self.isCollapsed {
                    self.expand()
                }
            } else {
                if !self.isCollapsed {
                    self.collapse()
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { toggle(); return }
        if event.modifierFlags.contains(.command) { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(from: sender)
            return
        }
        // Option-click follows the same action; no gesture reveals Always Hidden.
        handleToggleClick(clickCount: event.clickCount, timestamp: event.timestamp)
    }

    private func handleToggleClick(clickCount: Int, timestamp: TimeInterval) {
        guard isEnabled else { return }
        let previous = lastToggleClickTimestamp
        lastToggleClickTimestamp = timestamp
        let gap = timestamp - previous
        guard clickCount <= 1,
              previous == 0 || gap < 0 || gap > NSEvent.doubleClickInterval else { return }
        toggle()
    }









    private func showContextMenu(from sender: NSStatusBarButton) {
        let strings = FeatureStrings.menuBarHider(L10n.shared.language)
        let menu = NSMenu()

        if isCollapsed {
            let expandItem = NSMenuItem(title: strings.contextMenuExpand, action: #selector(contextMenuExpand), keyEquivalent: "")
            expandItem.target = self
            menu.addItem(expandItem)
        } else {
            let collapseItem = NSMenuItem(title: strings.contextMenuCollapse, action: #selector(contextMenuCollapse), keyEquivalent: "")
            collapseItem.target = self
            menu.addItem(collapseItem)
        }

        if MenuBarOrganizerPolicy.supportsAdvancedBackend {
            let advanced = FeatureStrings.menuBarOrganizer(L10n.shared.language)
            let drawer = NSMenuItem(title: advanced.drawer, action: #selector(contextMenuDrawer), keyEquivalent: "")
            drawer.target = self
            menu.addItem(drawer)
            let search = NSMenuItem(title: advanced.search, action: #selector(contextMenuSearch), keyEquivalent: "")
            search.target = self
            menu.addItem(search)
        }
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: strings.contextMenuSettings, action: #selector(contextMenuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func contextMenuDrawer() {
        Task { @MainActor in MenuBarOrganizerService.shared.showDrawer() }
    }
    @objc private func contextMenuSearch() {
        Task { @MainActor in MenuBarOrganizerService.shared.showDrawer(search: true) }
    }

    @objc private func contextMenuExpand() { expand() }
    @objc private func contextMenuCollapse() { collapse() }

    @objc private func contextMenuOpenSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.menuBarHider))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    // MARK: - Auto-Collapse Timer

    private func restartAutoCollapseTimerIfNeeded() {
        stopAutoCollapseTimer()
        guard isEnabled, !isCollapsed, !isConfiguring, !recoveryHoldsExpansion, !organizerHoldsExpansion, !isReorderingItems else { return }

        let autoCollapse = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAutoCollapse)
        guard autoCollapse else { return }

        let delaySeconds = MenuBarHiderSupport.sanitizeAutoCollapseDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.menuBarHiderAutoCollapseDelay))

        let generation = autoCollapseGeneration
        let timer = Timer(timeInterval: Double(delaySeconds), repeats: false) { [weak self] _ in
            self?.autoCollapseIfCurrent(generation: generation)
        }
        timer.tolerance = min(0.5, Double(delaySeconds) * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        autoCollapseTimer = timer
    }

    private func autoCollapseIfCurrent(generation: UInt64) {
        guard generation == autoCollapseGeneration, isEnabled, !isConfiguring,
              !isCollapsed, !recoveryHoldsExpansion, !organizerHoldsExpansion, !isReorderingItems,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAutoCollapse)
        else { return }
        collapse()
    }

    private func stopAutoCollapseTimer() {
        autoCollapseGeneration &+= 1
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }
}
