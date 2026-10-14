// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Exercises production lifecycle methods with isolated preferences and no
/// status items or global shortcuts installed in the user's session.
enum MenuBarHiderRuntimeTests {
    final class Item { var visibleX: CGFloat? }
    enum NSEvent {
        static let doubleClickInterval = 0.5
        enum EventMask { case scrollWheel, mouseMoved }
        static var registrations = 0
        static var moveRegistrations = 0
        static var removals = 0
        static func addLocalMonitorForEvents(matching: EventMask,
                                            handler: @escaping (AppKit.NSEvent) -> AppKit.NSEvent?) -> Any? {
            if matching == .mouseMoved { moveRegistrations += 1 } else { registrations += 1 }
            return NSObject()
        }
        static func addGlobalMonitorForEvents(matching: EventMask,
                                              handler: @escaping (AppKit.NSEvent) -> Void) -> Any? {
            moveRegistrations += 1
            return NSObject()
        }
        static func removeMonitor(_ monitor: Any) { removals += 1 }
    }
    enum NSStatusBar {
        static let system = Bar()
        final class Bar {
            var removed = 0
            func removeStatusItem(_ item: Item) { removed += 1 }
        }
    }
    final class Hotkey {
        var registered = false
        var acceptsRegistration = true
        var unregisters = 0
        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool {
            registered = enabled && acceptsRegistration
            return !enabled || acceptsRegistration
        }
        func unregister() { registered = false; unregisters += 1 }
    }
    class Fixture {
        func syncOrganizer() {} // Advanced service owns its own lifecycle gates.
        let defaults: UserDefaults
        let hotkey = Hotkey()
        var isEnabled = false
        var isCollapsed = false
        var isConfiguring = false
        var isReorderingItems = false
        var shortcutRegistrationFailed = false
        var shortcutConflict: GlobalShortcutRole?
        var autoCollapseTimer: Timer?
        var autoCollapseGeneration: UInt64 = 0
        var recoveryHoldsExpansion = false
        var organizerHoldsExpansion = false
        static let swappedRolesKey = "menuBarHiderSeparatorRolesSwapped"
        var separatorRolesSwapped = false
        var physicalSeparatorItem: Item?
        var physicalAlwaysHiddenItem: Item?
        var separatorMeasurementGeneration: UInt64 = 0
        var separatorMeasurementPending = false
        func requestRenderedSeparatorOrder() -> Bool { false }
        func setupSeparatorDragMonitor() {}
        func removeSeparatorDragMonitor() {}
        func visibleStatusItemX(_ item: Item) -> CGFloat? { item.visibleX }
        var lastToggleClickTimestamp: TimeInterval = 0
        var didExpandFromHover = false
        var toggleItem: Item?
        var separatorItem: Item? { separatorRolesSwapped ? physicalAlwaysHiddenItem : physicalSeparatorItem }
        var alwaysHiddenItem: Item? { separatorRolesSwapped ? physicalSeparatorItem : physicalAlwaysHiddenItem }
        var hoverWatchdogActive = false
        var trackingActive = false
        var scrollMonitor: Any?
        var separatorMouseMoveMonitor: Any?
        var localSeparatorMouseMoveMonitor: Any?
        var scrollActive: Bool { scrollMonitor != nil }
        var installs = 0
        var appearances = 0
        var haptics = 0

        init(defaults: UserDefaults) { self.defaults = defaults }
        func installOrUpdateItems() {
            installs += 1
            toggleItem = toggleItem ?? Item()
            physicalSeparatorItem = physicalSeparatorItem ?? Item()
            physicalAlwaysHiddenItem = physicalAlwaysHiddenItem ?? Item()
            trackingActive = true
        }
        func handleScrollEvent(_ event: AppKit.NSEvent) {}
        func handleReorderingEvent(_ event: AppKit.NSEvent) {}
        func stopHoverWatchdog() { hoverWatchdogActive = false }
        func startHoverWatchdog() { hoverWatchdogActive = true }
        func removeTrackingArea() { trackingActive = false }
        func removeScrollMonitor() { scrollMonitor = nil }
        func updateItemAppearances() { appearances += 1 }
        func triggerHapticFeedback() { haptics += 1 }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.menu-bar-hider-runtime.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.setPersistentDomain(Defaults.registeredDefaults.filter { $0.key.hasPrefix("menuBarHider") },
                                     forName: domain)
        defaults.set(true, forKey: AppFeature.menuBarHider.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.menuBarHiderShortcutEnabled)
        let host = Host(defaults: defaults)
        host.syncWithPreferences()
        suite.expect(!host.hotkey.registered && host.installs == 0,
                     "a disabled but installed hider never claims its enabled shortcut")
        defaults.set(true, forKey: DefaultsKey.menuBarHiderEnabled)
        defaults.set(true, forKey: DefaultsKey.menuBarHiderScrollToToggle)
        host.syncWithPreferences()
        suite.expect(host.hotkey.registered && host.toggleItem != nil && host.scrollActive,
                     "enabling installs controls and registers the shortcut")
        let registrations = NSEvent.registrations
        host.syncWithPreferences()
        suite.expect(NSEvent.registrations == registrations,
                     "preference sync reuses the existing scroll monitor")
        defaults.set(false, forKey: DefaultsKey.menuBarHiderScrollToToggle)
        host.syncWithPreferences()
        suite.expect(!host.scrollActive && NSEvent.registrations == registrations,
                     "disabling scroll removes the monitor without creating another")
        defaults.set(true, forKey: DefaultsKey.menuBarHiderScrollToToggle)
        host.syncWithPreferences()
        suite.expect(host.scrollActive && NSEvent.registrations == registrations + 1,
                     "re-enabling scroll installs exactly one monitor")
        defaults.set(false, forKey: DefaultsKey.menuBarHiderEnabled)
        host.hoverWatchdogActive = true
        host.syncWithPreferences()
        suite.expect(!host.hotkey.registered && host.toggleItem == nil && host.separatorItem == nil
                     && host.alwaysHiddenItem == nil && !host.scrollActive && !host.trackingActive
                     && !host.hoverWatchdogActive && host.autoCollapseTimer == nil,
                     "disabling tears down the shortcut, items, timers and event monitors")
        let appearances = host.appearances
        let haptics = host.haptics
        host.toggle()
        host.expand()
        host.collapse()
        host.prepareForOrganizerOperation()
        host.beginConfigurationMode()
        host.resetSeparatorPositions()
        host.revealForStatusItemRecovery()
        suite.expect(host.appearances == appearances && host.haptics == haptics && !host.isConfiguring,
                     "disabled entry points cannot change state, recreate items or emit haptics")
        defaults.set(true, forKey: DefaultsKey.menuBarHiderEnabled)
        host.syncWithPreferences()
        defaults.set(false, forKey: AppFeature.menuBarHider.availabilityKey)
        host.syncWithPreferences()
        suite.expect(!host.hotkey.registered && !host.isEnabled && host.toggleItem == nil,
                     "uninstall releases the shortcut even when saved switches stay on")
        defaults.set(true, forKey: AppFeature.menuBarHider.availabilityKey)
        host.syncWithPreferences()
        suite.expect(host.isEnabled && host.hotkey.registered,
                     "reinstall restores saved activation and shortcut preferences")

        host.resetSeparatorPositions()
        suite.expect(host.isConfiguring && host.hotkey.registered && host.toggleItem != nil,
                     "resetting placement rebuilds controls without losing the enabled shortcut")
        host.endConfigurationMode()

        let oldShortcut = GlobalShortcut.recentCapturesDefault
        defaults.set(oldShortcut.storageValue, forKey: DefaultsKey.menuBarHiderShortcut)
        defaults.set(true, forKey: AppFeature.screenshot.availabilityKey)
        host.syncWithPreferences()
        suite.expect(host.shortcutConflict == .recentCaptures && !host.hotkey.registered,
                     "the stored former default cannot steal the recent-captures shortcut")
        suite.expect(defaults.string(forKey: DefaultsKey.menuBarHiderShortcut) == oldShortcut.storageValue,
                     "conflict reporting preserves the user's saved combination")
        defaults.set(GlobalShortcut.menuBarHiderDefault.storageValue, forKey: DefaultsKey.menuBarHiderShortcut)
        host.syncWithPreferences()
        suite.expect(host.shortcutConflict == nil && host.hotkey.registered,
                     "assigning a free combination resolves a saved conflict")
        host.hotkey.acceptsRegistration = false
        host.syncWithPreferences()
        suite.expect(host.shortcutRegistrationFailed && !host.hotkey.registered,
                     "a macOS registration refusal is exposed to Settings")
        host.hotkey.acceptsRegistration = true

        defaults.set(true, forKey: DefaultsKey.menuBarHiderAutoCollapse)
        host.expand()
        let firstGeneration = host.autoCollapseGeneration
        suite.expect(host.autoCollapseTimer != nil, "expansion arms the configured timer")
        host.beginConfigurationMode()
        host.autoCollapseIfCurrent(generation: firstGeneration)
        suite.expect(host.isConfiguring && !host.isCollapsed && host.autoCollapseTimer == nil,
                     "an expired callback cannot collapse after configuration starts")
        host.syncWithPreferences()
        suite.expect(host.autoCollapseTimer == nil, "preference sync cannot arm a timer while configuring")
        host.endConfigurationMode()
        let nextGeneration = host.autoCollapseGeneration
        suite.expect(host.autoCollapseTimer != nil, "leaving configuration resumes automatic collapse")
        host.autoCollapseIfCurrent(generation: firstGeneration)
        suite.expect(!host.isCollapsed, "a replaced timer cannot close a newer expansion")
        host.autoCollapseIfCurrent(generation: nextGeneration)
        suite.expect(host.isCollapsed && host.autoCollapseTimer == nil,
                     "the current timer collapses an active expanded hider")

        host.revealForStatusItemRecovery()
        host.syncWithPreferences()
        suite.expect(!host.isCollapsed && host.autoCollapseTimer == nil && host.recoveryHoldsExpansion,
                     "recovery holds only Hidden icons expanded across preference syncs")
        let clicks = Host(defaults: defaults)
        clicks.isEnabled = true
        clicks.isCollapsed = true
        clicks.handleToggleClick(clickCount: 1, timestamp: 10)
        suite.expect(!clicks.isCollapsed, "the circle responds to a single click immediately")
        clicks.handleToggleClick(clickCount: 2, timestamp: 10.1)
        clicks.handleToggleClick(clickCount: 3, timestamp: 10.2)
        suite.expect(!clicks.isCollapsed, "double- and triple-click tails cannot trigger another action")
        clicks.handleToggleClick(clickCount: 1, timestamp: 11)
        suite.expect(clicks.isCollapsed, "a later click conceals the normal hidden group")
        clicks.handleToggleClick(clickCount: 1, timestamp: 11.1)
        suite.expect(clicks.isCollapsed, "forwarded double-click tails with clickCount one are ignored")
        clicks.beginConfigurationMode()
        suite.expect(clicks.isCollapsed, "opening Settings preserves the collapsed display mode")
        clicks.endConfigurationMode()
        clicks.expand()
        clicks.beginConfigurationMode()
        suite.expect(!clicks.isCollapsed, "opening Settings preserves the expanded display mode")
        clicks.endConfigurationMode()
        let moves = NSEvent.moveRegistrations
        clicks.syncSeparatorMouseMoveMonitor(commandHeld: false)
        suite.expect(NSEvent.moveRegistrations == moves, "idle hider does not subscribe to mouse motion")
        clicks.syncSeparatorMouseMoveMonitor(commandHeld: true)
        clicks.syncSeparatorMouseMoveMonitor(commandHeld: true)
        suite.expect(NSEvent.moveRegistrations == moves + 2,
                     "holding Command arms exactly one local and one global mouse monitor")
        let removed = NSEvent.removals
        clicks.syncSeparatorMouseMoveMonitor(commandHeld: false)
        suite.expect(NSEvent.removals == removed + 2 && clicks.separatorMouseMoveMonitor == nil
                     && clicks.localSeparatorMouseMoveMonitor == nil,
                     "releasing Command removes both motion monitors")
        clicks.isEnabled = false
        clicks.syncSeparatorMouseMoveMonitor(commandHeld: true)
        suite.expect(NSEvent.moveRegistrations == moves + 2, "disabled hider cannot arm motion monitoring")
        clicks.isEnabled = true
        clicks.installOrUpdateItems()
        let leftSlot = clicks.physicalSeparatorItem!
        let rightSlot = clicks.physicalAlwaysHiddenItem!
        let normalPositionKey = "NSStatusItem Preferred Position \(MenuBarHiderSupport.separatorAutosaveName)"
        let permanentPositionKey = "NSStatusItem Preferred Position \(MenuBarHiderSupport.alwaysHiddenAutosaveName)"
        defaults.set(651.0, forKey: normalPositionKey)
        defaults.set(357.0, forKey: permanentPositionKey)
        leftSlot.visibleX = nil
        rightSlot.visibleX = nil
        clicks.repairSeparatorOrder()
        suite.expect(clicks.separatorRolesSwapped && clicks.separatorItem === rightSlot,
                     "remembered crossed placement repairs roles while the permanent section is hidden")
        let repairedAppearances = clicks.appearances
        clicks.repairSeparatorOrder()
        suite.expect(clicks.appearances == repairedAppearances,
                     "role persistence notification cannot create a repair loop")
        defaults.set(250.0, forKey: normalPositionKey)
        clicks.repairSeparatorOrder()
        suite.expect(!clicks.separatorRolesSwapped && clicks.separatorItem === leftSlot,
                     "a second drag restores roles without requiring Show All")
        defaults.removeObject(forKey: normalPositionKey)
        defaults.removeObject(forKey: permanentPositionKey)
        clicks.autoCollapseTimer?.invalidate()
        host.autoCollapseIfCurrent(generation: nextGeneration)
        suite.expect(!host.isCollapsed && host.recoveryHoldsExpansion,
                     "a stale callback cannot hide the only recovery control again")
        host.isConfiguring = true
        host.endConfigurationMode()
        suite.expect(!host.isCollapsed && host.autoCollapseTimer == nil,
                     "closing Settings after explicit recovery leaves only normal hidden items revealed")
        for _ in 0..<10 {
            host.revealForStatusItemRecovery()
            host.syncWithPreferences()
        }
        suite.expect(!host.isCollapsed && host.autoCollapseTimer == nil,
                     "repeated recovery never starts a reveal-collapse timer loop")
        host.beginConfigurationMode()
        host.endConfigurationMode()
        suite.expect(!host.recoveryHoldsExpansion && host.autoCollapseTimer != nil,
                     "a deliberate configuration session resumes automatic collapse after recovery")
        let pendingGeneration = host.autoCollapseGeneration
        defaults.set(false, forKey: DefaultsKey.menuBarHiderEnabled)
        host.syncWithPreferences()
        host.autoCollapseIfCurrent(generation: pendingGeneration)
        suite.expect(!host.isEnabled && !host.isCollapsed,
                     "an expired callback has no effect after disabling")

        defaults.set(true, forKey: DefaultsKey.menuBarHiderEnabled)
        host.syncWithPreferences()
        host.collapse()
        let savedCollapsed = defaults.bool(forKey: DefaultsKey.menuBarHiderCollapsed)
        host.setReorderingItems(true)
        suite.expect(host.isReorderingItems && host.isCollapsed,
                     "Command reordering preserves the saved collapse state")
        suite.expect(host.autoCollapseTimer == nil && !host.hoverWatchdogActive,
                     "reordering stops collapse timers so the drop targets stay stable")
        host.syncWithPreferences()
        suite.expect(host.isReorderingItems && host.autoCollapseTimer == nil,
                     "preference sync cannot resume collapse during reordering")
        host.setReorderingItems(false)
        suite.expect(!host.isReorderingItems && host.isCollapsed &&
                     defaults.bool(forKey: DefaultsKey.menuBarHiderCollapsed) == savedCollapsed,
                     "releasing Command restores the original hidden state without saving a reveal")
        host.expand()
        host.setReorderingItems(true)
        host.didExpandFromHover = true
        let dragGeneration = host.autoCollapseGeneration
        host.autoCollapseIfCurrent(generation: dragGeneration)
        suite.expect(!host.isCollapsed && host.isReorderingItems,
                     "a collapse callback cannot close the bar during reordering")
        host.setReorderingItems(false)
        suite.expect(!host.isCollapsed && host.autoCollapseTimer != nil && host.hoverWatchdogActive,
                     "an expanded bar resumes automatic and hover collapse after reordering")

        host.beginOrganizerOperation()
        host.prepareForOrganizerOperation()
        let menuGeneration = host.autoCollapseGeneration
        host.syncWithPreferences()
        host.autoCollapseIfCurrent(generation: menuGeneration)
        host.toggle()
        host.expand()
        host.collapse()
        let heldInstalls = host.installs
        host.resetSeparatorPositions()
        suite.expect(host.installs == heldInstalls, "resetting separators cannot remove a native activation anchor mid-operation")
        suite.expect(host.organizerHoldsExpansion && !host.isCollapsed
                     && host.autoCollapseTimer == nil,
                     "preference sync, manual collapse and stale timers cannot hide a native menu during activation")
        host.endOrganizerOperation(resume: true)
        suite.expect(!host.organizerHoldsExpansion && host.autoCollapseTimer != nil,
                     "finishing a native menu resumes the user's automatic collapse preference")

        defaults.set(false, forKey: DefaultsKey.menuBarHiderAutoCollapse)
        defaults.set(true, forKey: DefaultsKey.menuBarHiderAlwaysHiddenEnabled)
        for state in [MenuBarHiderSupport.DisplayState.collapsed, .expanded] {
            switch state {
            case .collapsed: host.collapse()
            case .expanded: host.expand()
            }
            let previous = host.organizerDisplayState
            host.beginOrganizerOperation()
            host.prepareForOrganizerOperation()
            host.restoreAfterOrganizerActivation(previous)
            suite.expect(host.organizerDisplayState == state && !host.organizerHoldsExpansion
                            && host.autoCollapseTimer == nil,
                         "activation restores both display modes even with auto-collapse off")
        }
        host.collapse()
        let beforeConfiguration = host.organizerDisplayState
        host.beginOrganizerOperation()
        host.prepareForOrganizerOperation()
        host.beginConfigurationMode()
        host.restoreAfterOrganizerActivation(beforeConfiguration)
        suite.expect(host.isConfiguring && !host.organizerHoldsExpansion,
                     "activation does not collapse the bar when configuration started during the operation")
        host.endConfigurationMode()
        host.beginOrganizerOperation()
        host.prepareForOrganizerOperation()
        defaults.set(false, forKey: DefaultsKey.menuBarHiderEnabled)
        host.syncWithPreferences()
        let disabledAppearances = host.appearances
        host.restoreAfterOrganizerActivation(.collapsed)
        suite.expect(!host.isEnabled && !host.organizerHoldsExpansion && host.appearances == disabledAppearances,
                     "restoration cannot recreate disabled controls")

        let role = GlobalShortcutRole.menuBarHider
        suite.expect(role.requiredEnableKeys.contains(DefaultsKey.menuBarHiderEnabled),
                     "shortcut conflict checks use the same main enable gate as registration")
    }
}
