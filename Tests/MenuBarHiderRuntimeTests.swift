// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Exercises production lifecycle methods with isolated preferences and no
/// status items or global shortcuts installed in the user's session.
enum MenuBarHiderRuntimeTests {
    final class Item { var visibleX: CGFloat? }
    enum NSEvent {
        static let doubleClickInterval = 0.5
        enum EventMask { case scrollWheel }
        static var registrations = 0
        static func addLocalMonitorForEvents(matching: EventMask,
                                            handler: @escaping (AppKit.NSEvent) -> AppKit.NSEvent?) -> Any? {
            registrations += 1
            return NSObject()
        }
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
        let defaults: UserDefaults
        let hotkey = Hotkey()
        var isEnabled = false
        var isCollapsed = false
        var isShowingAll = false
        var isConfiguring = false
        var shortcutRegistrationFailed = false
        var shortcutConflict: GlobalShortcutRole?
        var autoCollapseTimer: Timer?
        var autoCollapseGeneration: UInt64 = 0
        var recoveryHoldsExpansion = false
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
        var didRevealInClickSequence = false
        var pendingClickTimer: Timer?
        var pendingClickGeneration: UInt64 = 0
        var didExpandFromHover = false
        var toggleItem: Item?
        var separatorItem: Item? { separatorRolesSwapped ? physicalAlwaysHiddenItem : physicalSeparatorItem }
        var alwaysHiddenItem: Item? { separatorRolesSwapped ? physicalSeparatorItem : physicalAlwaysHiddenItem }
        var hoverWatchdogActive = false
        var trackingActive = false
        var scrollMonitor: Any?
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
        func stopHoverWatchdog() { hoverWatchdogActive = false }
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
        host.showAll()
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
        suite.expect(!host.isCollapsed && host.isShowingAll && host.autoCollapseTimer == nil && host.recoveryHoldsExpansion,
                     "icon recovery reveals even always-hidden controls across preference syncs")
        let clicks = Host(defaults: defaults)
        clicks.isEnabled = true
        clicks.isCollapsed = true
        clicks.handleToggleClick(clickCount: 1, timestamp: 10, alwaysHiddenEnabled: true)
        suite.expect(clicks.isCollapsed, "first click keeps the native layout stable for the second click")
        clicks.handleToggleClick(clickCount: 1, timestamp: 10.4, alwaysHiddenEnabled: true)
        suite.expect(clicks.isShowingAll,
                     "a system-classified double click slower than 300 ms reveals always-hidden icons")
        clicks.handleToggleClick(clickCount: 3, timestamp: 10.45, alwaysHiddenEnabled: true)
        suite.expect(clicks.isShowingAll, "the tail of a reveal gesture cannot hide the recovered controls")
        clicks.handleToggleClick(clickCount: 1, timestamp: 12, alwaysHiddenEnabled: true)
        clicks.finishPendingClick(generation: clicks.pendingClickGeneration)
        suite.expect(clicks.isCollapsed, "a new single click still closes the revealed groups")
        clicks.handleToggleClick(clickCount: 1, timestamp: 14, alwaysHiddenEnabled: true)
        let staleClick = clicks.pendingClickGeneration
        clicks.revealForStatusItemRecovery()
        clicks.finishPendingClick(generation: staleClick)
        suite.expect(clicks.isShowingAll && clicks.pendingClickTimer == nil,
                     "recovery cancels a queued single click without re-hiding controls")
        clicks.collapse()
        clicks.handleToggleClick(clickCount: 1, timestamp: 16, alwaysHiddenEnabled: true)
        clicks.handleToggleClick(clickCount: 2, timestamp: 16.1, alwaysHiddenEnabled: true)
        suite.expect(clicks.isShowingAll && clicks.pendingClickTimer == nil,
                     "AppKit-classified double clicks also resolve without a delayed collapse")
        clicks.collapse()
        clicks.handleToggleClick(clickCount: 1, timestamp: 18, alwaysHiddenEnabled: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        suite.expect(!clicks.isCollapsed && !clicks.isShowingAll && clicks.pendingClickTimer == nil,
                     "a real one-shot timer performs the single click after the gesture interval")
        clicks.revealForStatusItemRecovery()
        clicks.installOrUpdateItems()
        let leftSlot = clicks.physicalSeparatorItem!
        let rightSlot = clicks.physicalAlwaysHiddenItem!
        leftSlot.visibleX = 100
        rightSlot.visibleX = 120
        clicks.repairSeparatorOrder()
        suite.expect(clicks.separatorItem === rightSlot && clicks.alwaysHiddenItem === leftSlot,
                     "crossed separators exchange roles without exchanging physical identities")
        clicks.repairSeparatorOrder()
        suite.expect(clicks.separatorRolesSwapped,
                     "repeated order repair cannot oscillate between separator roles")
        rightSlot.visibleX = nil
        clicks.repairSeparatorOrder()
        suite.expect(clicks.separatorRolesSwapped,
                     "missing on-screen geometry cannot reverse the repaired roles")
        leftSlot.visibleX = 140
        rightSlot.visibleX = 120
        clicks.repairSeparatorOrder()
        suite.expect(!clicks.separatorRolesSwapped && clicks.separatorItem === leftSlot,
                     "dragging the separators back exchanges their roles again")
        let normalPositionKey = "NSStatusItem Preferred Position \(MenuBarHiderSupport.separatorAutosaveName)"
        let permanentPositionKey = "NSStatusItem Preferred Position \(MenuBarHiderSupport.alwaysHiddenAutosaveName)"
        defaults.set(651.0, forKey: normalPositionKey)
        defaults.set(357.0, forKey: permanentPositionKey)
        clicks.isShowingAll = false
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
        suite.expect(host.isShowingAll && host.recoveryHoldsExpansion,
                     "a stale callback cannot hide the only recovery control again")
        host.isConfiguring = true
        host.endConfigurationMode()
        suite.expect(host.isShowingAll && host.autoCollapseTimer == nil,
                     "closing Settings after explicit recovery leaves every section revealed")
        for _ in 0..<10 {
            host.revealForStatusItemRecovery()
            host.syncWithPreferences()
        }
        suite.expect(host.isShowingAll && host.autoCollapseTimer == nil,
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

        let role = GlobalShortcutRole.menuBarHider
        suite.expect(role.requiredEnableKeys.contains(DefaultsKey.menuBarHiderEnabled),
                     "shortcut conflict checks use the same main enable gate as registration")
    }
}
