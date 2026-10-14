// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production teardown/recovery bodies run against isolated hider preferences
/// and input/panel doubles, without creating status items or posting events.
enum MenuBarOrganizerLifecycleTests {
    final class MenuBarItemPreviewProvider {
        static let shared = MenuBarItemPreviewProvider()
        var stops = 0
        func stop() { stops += 1 }
    }
    enum MenuBarGlobalSpacing { static var hasSavedValues = false }
    enum MenuBarOrganizerPolicy {
        static var supportsAdvancedBackend = true
        static var conflicts: [String] = []
        static func conflictingManagers() -> [String] { conflicts }
    }
    final class Appearance {
        var enabled = false
        func sync(enabled: Bool) { self.enabled = enabled }
    }
    final class Mover {
        let input = MenuBarInputCleanup()
        func cancel() { input.finish() }
    }
    final class Panel {
        var isVisible = true
        func close() { isVisible = false }
    }
    @MainActor class Fixture {
        let appearance = Appearance()
        let mover = Mover()
        let hider: MenuBarHiderRuntimeTests.Host
        var panel: Panel?
        var generation: UInt64 = 0
        var needsIdentityRefresh = false
        var activationRecovery: (state: MenuBarHiderSupport.DisplayState, mayBeDisplaced: Bool)?
        var operationTask: Task<Void, Never>?
        var refreshTask: Task<Void, Never>?
        var refreshTimer: Timer?
        var items: [Int] = []
        var undo: Int?
        var canUndo = false
        var isBusy = false
        var isRunning = false
        var canRestoreSpacing = false
        var enabled = true
        var trusted = true
        var editorVisible = false
        func refresh() {}
        func updateRefreshTimer() {}
        init(hider: MenuBarHiderRuntimeTests.Host) { self.hider = hider }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            let domain = "com.vorssaint.tests.organizer-lifecycle.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: domain)!
            defer { defaults.removePersistentDomain(forName: domain) }
            defaults.set(true, forKey: DefaultsKey.menuBarHiderAutoCollapse)
            let hider = MenuBarHiderRuntimeTests.Host(defaults: defaults)
            hider.isEnabled = true
            let host = Host(hider: hider)
            for state: MenuBarHiderSupport.DisplayState in [.collapsed, .expanded] {
                hider.beginOrganizerOperation()
                hider.prepareForOrganizerOperation()
                host.activationRecovery = (state, false)
                host.finishActivationRecovery()
                suite.expect(hider.organizerDisplayState == state && host.activationRecovery == nil,
                             "failure before input or after verified restoration recovers the full previous display mode")
                suite.expect((hider.autoCollapseTimer != nil) == (state != .collapsed),
                             "safe recovery resumes the previous state's auto-collapse behavior")
            }
            hider.beginOrganizerOperation()
            hider.prepareForOrganizerOperation()
            host.activationRecovery = (.collapsed, true)
            var releases = 0
            host.mover.input.release = { releases += 1 }
            host.appearance.sync(enabled: true)
            host.isRunning = true
            host.isBusy = true
            host.panel = Panel()
            let panel = host.panel!
            host.stop()
            suite.expect(MenuBarItemPreviewProvider.shared.stops > 0,
                         "organizer teardown cancels previews and clears captured pixels")
            suite.expect(releases == 1 && !host.isRunning && !host.isBusy && !panel.isVisible,
                         "stop releases pending input synchronously and dismisses the organizer")
            suite.expect(!host.appearance.enabled, "explicit teardown removes decoration as well as input")
            suite.expect(!hider.isCollapsed && hider.recoveryHoldsExpansion && hider.autoCollapseTimer == nil,
                         "cancellation after a possible drag keeps recovery reachable instead of concealing a displaced item")
            host.stop()
            host.finishActivationRecovery()
            suite.expect(releases == 1 && hider.recoveryHoldsExpansion,
                         "late task cleanup is idempotent and cannot undo the recovery hold")
            host.trusted = false
            host.syncWithPreferences()
            suite.expect(host.appearance.enabled && host.isRunning,
                         "inventory and decoration remain available without an advanced switch or Accessibility")
            host.isBusy = true
            host.mover.input.release = { releases += 1 }
            host.syncWithPreferences()
            suite.expect(releases == 2 && !host.isBusy && host.isRunning,
                         "permission loss stops input synchronously while preserving read-only inventory")
            host.enabled = false
            host.syncWithPreferences()
            suite.expect(!host.appearance.enabled, "disabling the basic hider removes decoration")
            host.enabled = true
            MenuBarOrganizerPolicy.conflicts = ["Other manager"]
            host.syncWithPreferences()
            suite.expect(!host.appearance.enabled && !host.isRunning,
                         "a conflicting manager prevents input and decoration")
            MenuBarOrganizerPolicy.conflicts = []
            hider.stopAutoCollapseTimer()
        }
    }
}
