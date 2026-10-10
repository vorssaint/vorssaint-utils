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
    private var isShowingAll: Bool = false
    private var trackingArea: NSTrackingArea?
    private weak var trackingButton: NSStatusBarButton?
    private var scrollMonitor: Any?
    private var separatorDragMonitor: Any?
    private var localSeparatorDragMonitor: Any?
    private var separatorMeasurementPending = false
    private var separatorMeasurementGeneration: UInt64 = 0
    private var separatorMeasurementRequested = false
    private var lastObservedPlacement: [Double?]?
    private var lastScrollToggleTime: TimeInterval = 0
    private var lastToggleClickTimestamp: TimeInterval = 0
    private var didRevealInClickSequence = false
    private var pendingClickTimer: Timer?
    private var pendingClickGeneration: UInt64 = 0

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
        pendingClickTimer?.invalidate()
        removeScrollMonitor()
        removeSeparatorDragMonitor()
    }

    // MARK: - Lifecycle & Preferences Sync

    func syncWithPreferences() {
        let isAvailable = AppFeature.menuBarHider.isAvailable
        let enabled = isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderEnabled)
        isEnabled = enabled

        syncHotkey()

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
    }

    func resetSeparatorPositions() {
        guard isEnabled else { return }
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
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
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

        // 3. Always Hidden Separator Item
        if alwaysHiddenEnabled {
            if physicalAlwaysHiddenItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: CGFloat(MenuBarHiderSupport.normalAlwaysHiddenWidth))
                item.autosaveName = MenuBarHiderSupport.alwaysHiddenAutosaveName
                item.behavior = []
                item.isVisible = true
                physicalAlwaysHiddenItem = item
            }
        } else {
            separatorRolesSwapped = false
            UserDefaults.standard.removeObject(forKey: Self.swappedRolesKey)
            if let physicalAlwaysHiddenItem {
                NSStatusBar.system.removeStatusItem(physicalAlwaysHiddenItem)
                self.physicalAlwaysHiddenItem = nil
            }
        }

        // Pick the collapse state back up from the previous run, but only when
        // the items were just created: syncWithPreferences() runs on every
        // settings change and must not clobber the state on screen right now.
        if didCreateToggle {
            isCollapsed = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderCollapsed)
            isShowingAll = false
        }

        repairSeparatorOrder()
        configureItemButtons()
        updateItemAppearances()
    }

    private func setupSeparatorDragMonitor() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled) else {
            removeSeparatorDragMonitor()
            return
        }
        guard separatorDragMonitor == nil, localSeparatorDragMonitor == nil else { return }
        localSeparatorDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if event.modifierFlags.contains(.command) {
                DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
            }
            return event
        }
        separatorDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return }
            DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
        }
    }

    private func removeSeparatorDragMonitor() {
        if let separatorDragMonitor { NSEvent.removeMonitor(separatorDragMonitor) }
        separatorDragMonitor = nil
        if let localSeparatorDragMonitor { NSEvent.removeMonitor(localSeparatorDragMonitor) }
        localSeparatorDragMonitor = nil
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

    /// Without rendered geometry: remembered placement, then the status
    /// windows, which are only reliable while every section is on screen.
    private func applyFallbackSeparatorOrder() {
        if let swapped = MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: UserDefaults.standard) {
            applySeparatorOrder(swapped: swapped)
            return
        }
        guard isShowingAll, let normal = physicalSeparatorItem, let permanent = physicalAlwaysHiddenItem,
              let normalX = visibleStatusItemX(normal),
              let permanentX = visibleStatusItemX(permanent) else { return }
        applySeparatorOrder(swapped: normalX < permanentX)
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
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?.processIdentifier,
              let normalHelp = physicalSeparatorItem?.button?.toolTip,
              let permanentHelp = physicalAlwaysHiddenItem?.button?.toolTip else { return false }
        separatorMeasurementPending = true
        separatorMeasurementRequested = false
        let generation = separatorMeasurementGeneration
        let observedRoles = separatorRolesSwapped
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let positions = MenuBarHiderAccessibility.separatorPositions(
                pid: pid, normalHelp: normalHelp, permanentHelp: permanentHelp)
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
        let style = currentIconStyle
        let strings = FeatureStrings.menuBarHider(L10n.shared.language)
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // 1. Toggle button (Always on the right)
        if let toggleButton = toggleItem?.button {
            toggleButton.target = self
            toggleButton.action = #selector(toggleClicked)
            toggleButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // A symbol name the running system does not ship resolves to nil,
            // and a variable-length item with neither image nor title collapses
            // to zero width — the toggle would simply vanish. Fall back to the
            // chevron, and to a text glyph if even that is unavailable.
            let symbolName = MenuBarHiderSupport.toggleSymbolName(isCollapsed: isCollapsed, style: style)
            let fallbackName = MenuBarHiderSupport.toggleSymbolName(isCollapsed: isCollapsed, style: .chevron)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: strings.pageTitle)
                ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: strings.pageTitle)
            if let image {
                image.isTemplate = true
                toggleButton.image = image
                toggleButton.title = ""
            } else {
                toggleButton.image = nil
                toggleButton.title = isCollapsed ? "‹" : "›"
            }
            toggleButton.toolTip = MenuBarHiderSupport.toggleTooltip(
                isCollapsed: isCollapsed,
                isShowingAll: isShowingAll,
                alwaysHiddenEnabled: alwaysHiddenEnabled,
                strings: strings
            )
            setupTrackingArea()
        }

        // 2. Main separator (To the left of toggle)
        if let separatorButton = separatorItem?.button {
            separatorButton.target = self
            separatorButton.action = #selector(separatorClicked)
            separatorButton.sendAction(on: [.leftMouseUp])
            separatorButton.image = nil
            separatorButton.title = "|"
            separatorButton.alignment = .right
            separatorButton.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            separatorButton.toolTip = strings.tooltipSeparator
        }

        // 3. Always hidden separator (Leftmost)
        if let alwaysHiddenButton = alwaysHiddenItem?.button {
            alwaysHiddenButton.target = self
            alwaysHiddenButton.action = #selector(alwaysHiddenClicked)
            alwaysHiddenButton.sendAction(on: [.leftMouseUp])
            alwaysHiddenButton.image = nil
            alwaysHiddenButton.title = "‖"
            alwaysHiddenButton.alignment = .right
            alwaysHiddenButton.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
            alwaysHiddenButton.toolTip = strings.tooltipAlwaysHidden
        }
    }

    private func teardown() {
        cancelPendingClick()
        separatorMeasurementGeneration &+= 1
        separatorMeasurementPending = false
        hotkey.unregister()
        shortcutRegistrationFailed = false
        shortcutConflict = nil
        recoveryHoldsExpansion = false
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
        isShowingAll = false
        isConfiguring = false
    }

    // MARK: - Haptic Feedback

    private func triggerHapticFeedback() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderHapticFeedback) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    // MARK: - State Management

    func toggle() {
        guard isEnabled else { return }
        recoveryHoldsExpansion = false
        if isCollapsed {
            expand()
        } else {
            collapse()
        }
    }

    func expand(startTimer: Bool = true) {
        cancelPendingClick()
        guard isEnabled else { return }
        repairSeparatorOrder()
        recoveryHoldsExpansion = false
        stopHoverWatchdog()
        didExpandFromHover = false
        let wasCollapsed = isCollapsed
        isCollapsed = false
        isShowingAll = false
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
        cancelPendingClick()
        guard isEnabled else { return }
        recoveryHoldsExpansion = false
        repairSeparatorOrder()
        let wasExpanded = !isCollapsed || isShowingAll
        stopAutoCollapseTimer()
        stopHoverWatchdog()
        didExpandFromHover = false
        isCollapsed = true
        isShowingAll = false
        updateItemAppearances()
        persistCollapsedState()
        if wasExpanded {
            triggerHapticFeedback()
        }
    }

    func showAll(startTimer: Bool = true) {
        cancelPendingClick()
        guard isEnabled else { return }
        recoveryHoldsExpansion = false
        stopHoverWatchdog()
        didExpandFromHover = false
        isCollapsed = false
        isShowingAll = true
        updateItemAppearances()
        DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
        persistCollapsedState()
        triggerHapticFeedback()

        if startTimer && !isConfiguring {
            restartAutoCollapseTimerIfNeeded()
        } else {
            stopAutoCollapseTimer()
        }
    }

    func beginConfigurationMode() {
        cancelPendingClick()
        guard isEnabled else { return }
        isConfiguring = true
        stopAutoCollapseTimer()
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        if alwaysHiddenEnabled {
            showAll(startTimer: false)
        } else {
            expand(startTimer: false)
        }
    }

    func endConfigurationMode() {
        guard isConfiguring else { return }
        isConfiguring = false
        if !isCollapsed {
            restartAutoCollapseTimerIfNeeded()
        }
    }

    /// An explicit icon recovery keeps the bar open until the next deliberate
    /// toggle or configuration session, including intervening preference syncs.
    func revealForStatusItemRecovery() {
        guard isEnabled else { return }
        showAll(startTimer: false)
        recoveryHoldsExpansion = true
    }

    /// Carries the collapse state across relaunches. `isShowingAll` deliberately
    /// does not persist: revealing the always-hidden section is a momentary
    /// action, not a layout the app should come back in.
    private func persistCollapsedState() {
        UserDefaults.standard.set(isCollapsed, forKey: DefaultsKey.menuBarHiderCollapsed)
    }

    private var currentIconStyle: MenuBarHiderIconStyle {
        let raw = UserDefaults.standard.string(forKey: DefaultsKey.menuBarHiderIconStyle) ?? ""
        return MenuBarHiderIconStyle(rawValue: raw) ?? .chevron
    }

    private var currentDisplayState: MenuBarHiderSupport.DisplayState {
        if isShowingAll {
            return .showAll
        }
        return isCollapsed ? .collapsed : .expanded
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

        let state = currentDisplayState
        let width = usableMenuBarWidth
        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        toggleItem?.length = NSStatusItem.variableLength

        // Update main separator length
        if let separatorItem {
            let length = MenuBarHiderSupport.separatorLength(state: state, usableWidth: width)
            separatorItem.length = CGFloat(length)
        }

        // Update always-hidden separator length
        if let alwaysHiddenItem {
            let length = MenuBarHiderSupport.alwaysHiddenLength(state: state, usableWidth: width, isEnabled: alwaysHiddenEnabled)
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
        guard let event = NSApp.currentEvent else {
            toggle()
            return
        }

        // 1. Ignore clicks while holding Command (the user is dragging/reordering icons)
        if event.modifierFlags.contains(.command) {
            cancelPendingClick()
            DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
            return
        }

        // 2. Right-click or Control+Click -> Context Menu
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            cancelPendingClick()
            showContextMenu(from: sender)
            return
        }

        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)

        // 3. Option+Click reveals the always-hidden section outright. It stays
        //    out of the click-sequence bookkeeping below: it is a complete
        //    gesture on its own, and a plain click right after it should still
        //    collapse rather than be swallowed as a gesture tail.
        if alwaysHiddenEnabled && event.modifierFlags.contains(.option) {
            lastToggleClickTimestamp = event.timestamp
            toggleAlwaysHiddenSection()
            return
        }

        // Keep the native item in place until the gesture is resolved.
        handleToggleClick(clickCount: event.clickCount, timestamp: event.timestamp,
                          alwaysHiddenEnabled: alwaysHiddenEnabled)
    }

    private func handleToggleClick(clickCount: Int, timestamp: TimeInterval, alwaysHiddenEnabled: Bool) {
        guard isEnabled else { return }
        let gap = timestamp - lastToggleClickTimestamp
        lastToggleClickTimestamp = timestamp
        let withinGesture = gap <= MenuBarHiderSupport.revealGestureInterval(
            systemDoubleClickInterval: NSEvent.doubleClickInterval)

        if withinGesture && didRevealInClickSequence { return }
        // Do not require forwarded clicks to retain AppKit's clickCount.
        // A pending first click and event timestamps identify the pair.
        if alwaysHiddenEnabled, withinGesture, gap >= 0, pendingClickTimer != nil {
            cancelPendingClick()
            didRevealInClickSequence = true
            showAll()
            return
        }
        cancelPendingClick()
        didRevealInClickSequence = false
        guard alwaysHiddenEnabled else {
            performSingleClickToggle()
            return
        }
        let generation = pendingClickGeneration
        let timer = Timer(timeInterval: NSEvent.doubleClickInterval, repeats: false) { [weak self] _ in
            self?.finishPendingClick(generation: generation)
        }
        pendingClickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelPendingClick() {
        pendingClickGeneration &+= 1
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
    }

    private func finishPendingClick(generation: UInt64) {
        guard generation == pendingClickGeneration, pendingClickTimer != nil, isEnabled else { return }
        cancelPendingClick()
        performSingleClickToggle()
    }

    private func performSingleClickToggle() {
        if isShowingAll {
            collapse()
        } else {
            toggle()
        }
    }

    private func toggleAlwaysHiddenSection() {
        if isShowingAll {
            collapse()
        } else {
            showAll()
        }
    }

    @objc private func separatorClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggle()
            return
        }
        if event.modifierFlags.contains(.command) {
            cancelPendingClick()
            DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
            return
        }
        toggle()
    }

    @objc private func alwaysHiddenClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleAlwaysHiddenSection()
            return
        }
        if event.modifierFlags.contains(.command) {
            cancelPendingClick()
            DispatchQueue.main.async { [weak self] in self?.repairSeparatorOrder() }
            return
        }
        toggleAlwaysHiddenSection()
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

        let alwaysHiddenEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        if alwaysHiddenEnabled {
            if isShowingAll {
                let hideAlwaysItem = NSMenuItem(title: strings.contextMenuHideAlways, action: #selector(contextMenuCollapse), keyEquivalent: "")
                hideAlwaysItem.target = self
                menu.addItem(hideAlwaysItem)
            } else {
                let showAllItem = NSMenuItem(title: strings.contextMenuShowAll, action: #selector(contextMenuShowAll), keyEquivalent: "")
                showAllItem.target = self
                menu.addItem(showAllItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: strings.contextMenuSettings, action: #selector(contextMenuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func contextMenuExpand() { expand() }
    @objc private func contextMenuCollapse() { collapse() }
    @objc private func contextMenuShowAll() { showAll() }

    @objc private func contextMenuOpenSettings() {
        SettingsRouter.shared.request(FeatureSettingsDestination(.menuBarHider))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }

    // MARK: - Auto-Collapse Timer

    private func restartAutoCollapseTimerIfNeeded() {
        stopAutoCollapseTimer()
        guard isEnabled, !isCollapsed, !isConfiguring, !recoveryHoldsExpansion else { return }

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
              !isCollapsed, !recoveryHoldsExpansion,
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
