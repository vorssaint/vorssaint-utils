// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Runs the production visibility and refresh callbacks without changing the
/// real menu bar, Accessibility permissions, or the user's saved preferences.
enum MenuBarOrganizerLifecycleTests {
    final class MenuBarNativeVisibility {
        enum Failure: Error { case activation, applicationLocation }
        var error: Error?
        var deferred = false
        var completion: ((Error?) -> Void)?
        var plans: [Set<String>] = []
        var releases = 0
        func release() { releases += 1 }
        func apply(hiddenBundles: Set<String>, menuBarOwners: [NSRunningApplication],
                   completion: @escaping (Error?) -> Void) {
            plans.append(hiddenBundles)
            if deferred { self.completion = completion }
            else { completion(error) }
        }
    }
    struct Item: Equatable { let id: String; let bundleID: String }
    final class StatusItem { var button: Int? = 1 }
    final class HiddenBar {
        var items: [Item] = []
        var message: String?
        var presentations = 0
        func show(items: [Item], anchor: Int?, message: String?, needsAccessibility: Bool,
                  activate: @escaping (Item) -> Void, menu: (Item) -> NSMenu) {
            self.items = items
            self.message = message
            presentations += 1
        }
    }
    final class DispatchWorkItem {
        var cancelled = false
        let action: () -> Void
        init(block: @escaping () -> Void) { action = block }
        func cancel() { cancelled = true }
        func perform() { if !cancelled { action() } }
    }
    enum DispatchQueue {
        static let main = Queue()
        final class Queue {
            var jobs: [DispatchWorkItem] = []
            func asyncAfter(deadline: DispatchTime, execute item: DispatchWorkItem) { jobs.append(item) }
            func drain() {
                let pending = jobs
                jobs = []
                pending.forEach { $0.perform() }
            }
        }
    }
    class Fixture {
        var isEnabled = true
        var toggleItem: StatusItem? = StatusItem()
        var usesNativeVisibility = true
        var accessibilityAvailable = true
        var visibility = MenuBarOrganizerVisibility()
        var requestedVisibility = MenuBarOrganizerVisibility()
        var rules = MenuBarOrganizerRules(storage: ["hidden": "hidden", "always": "alwaysHidden"])
        var failure: MenuBarNativeVisibility.Failure?
        var isUpdating = false
        var clockInteractionActive = false
        var clockRestore: DispatchWorkItem?
        var refreshCompletions: [() -> Void] = []
        var temporaryBundle: String?
        let nativeVisibility = MenuBarNativeVisibility()
        var applications: [NSRunningApplication] = []
        var presentedSection: MenuBarOrganizerSection?
        var items = [Item(id: "hidden-icon", bundleID: "hidden"), Item(id: "always-icon", bundleID: "always")]
        var legacySections: [String: MenuBarOrganizerSection] = [:]
        var lastAnchor: Int?
        let hiddenBar = HiddenBar()
        var failureMessage: String { "Visibility failed: \(String(describing: failure))" }
        func section(for bundle: String) -> MenuBarOrganizerSection { rules.section(for: bundle) }
        func cancelActivation(restoringLegacyState: Bool) {}
        func closeHiddenBar() { presentedSection = nil }
        func refreshApplications(completion: (() -> Void)? = nil) { completion?() }
        func activateItem(_ item: Item) {}
        func itemMenu(_ item: Item) -> NSMenu { NSMenu() }
        func updateSections() {}
        init() { requestedVisibility.toggleHidden() }
    }

    static func run(_ suite: TestSuite) {
        do {
            let host = Host()
            host.nativeVisibility.deferred = true
            host.toggleHiddenBar(section: .hidden)
            suite.expect(host.hiddenBar.presentations == 0,
                         "opening the shelf waits for the system visibility result before presenting hidden icons")
            host.nativeVisibility.completion?(MenuBarNativeVisibility.Failure.applicationLocation)
            suite.expect(host.hiddenBar.items.isEmpty && host.hiddenBar.message == host.failureMessage,
                         "a staged app with a different registered copy explains the location failure instead of duplicating visible icons")
            host.nativeVisibility.deferred = false
            host.completeRefresh(permissionChanged: false)
            suite.expect(host.hiddenBar.items.map(\.bundleID) == ["hidden"] && host.hiddenBar.message == nil,
                         "an open failed shelf refreshes automatically once the restriction recovers")
        }
        do {
            let host = Host()
            host.nativeVisibility.deferred = true
            host.toggleHiddenBar(section: .hidden)
            host.closeHiddenBar()
            host.nativeVisibility.completion?(nil)
            suite.expect(host.hiddenBar.presentations == 0,
                         "a late visibility callback does not reopen a dismissed shelf")
        }
        do {
            let host = Host()
            host.accessibilityAvailable = false
            host.toggleHiddenBar(section: .hidden)
            suite.expect(host.hiddenBar.items.isEmpty && host.hiddenBar.message != nil,
                         "missing Accessibility shows recovery guidance instead of claiming visible icons are hidden")
            host.accessibilityAvailable = true
            host.toggleHiddenBar(section: .alwaysHidden)
            suite.expect(host.hiddenBar.items.map(\.bundleID) == ["hidden", "always"],
                         "successful Option reveal still presents both hidden sections")
        }
        do {
            let host = Host()
            host.nativeVisibility.error = MenuBarNativeVisibility.Failure.activation
            host.synchronizeVisibility()
            suite.expect(host.failure == .activation && host.visibility.hiddenShown,
                         "a failed startup safely reveals the bar and reports failure")
            suite.expect(!host.requestedVisibility.hiddenShown && !host.requestedVisibility.alwaysShown,
                         "startup failure preserves both saved hiding sections for recovery")
            host.nativeVisibility.error = nil
            host.completeRefresh(permissionChanged: false)
            suite.expect(host.nativeVisibility.plans == [["hidden", "always"], ["hidden", "always"]]
                && host.failure == nil && !host.visibility.hiddenShown,
                         "the next inventory refresh retries the same hiding plan without restarting macOS")
        }
        do {
            let host = Host()
            host.accessibilityAvailable = false
            host.synchronizeVisibility()
            suite.expect(host.nativeVisibility.plans.isEmpty && !host.requestedVisibility.hiddenShown,
                         "temporarily unavailable Accessibility retains the requested hiding plan")
            host.accessibilityAvailable = true
            host.completeRefresh(permissionChanged: true)
            suite.expect(host.nativeVisibility.plans == [["hidden", "always"]],
                         "returning permissions apply the original sections automatically")
        }
        do {
            let host = Host()
            host.clockHoverChanged(true)
            suite.expect(host.clockInteractionActive && host.nativeVisibility.releases == 1,
                         "hovering the clock releases assessment mode before the system click")
            host.completeRefresh(permissionChanged: false)
            suite.expect(host.nativeVisibility.plans.isEmpty && !host.requestedVisibility.hiddenShown,
                         "periodic refresh cannot block Notification Center again while over the clock")
            host.clockHoverChanged(false)
            suite.expect(host.clockInteractionActive, "leaving the clock allows the panel time to open")
            DispatchQueue.main.drain()
            suite.expect(!host.clockInteractionActive && host.nativeVisibility.plans == [["hidden", "always"]],
                         "after leaving the clock both hidden sections are restored")
        }
        do {
            let host = Host()
            host.clockHoverChanged(true)
            host.clockHoverChanged(false)
            host.clockHoverChanged(true)
            DispatchQueue.main.drain()
            suite.expect(host.clockInteractionActive && host.nativeVisibility.plans.isEmpty,
                         "returning to the clock cancels delayed restoration")
            host.requestedVisibility.revealAll()
            host.clockHoverChanged(false)
            DispatchQueue.main.drain()
            suite.expect(host.nativeVisibility.plans == [Set<String>()],
                         "Reveal All during a clock interaction is respected on restoration")
        }
        do {
            let host = Host()
            host.clockHoverChanged(true)
            host.clockHoverChanged(false)
            host.isEnabled = false
            DispatchQueue.main.drain()
            suite.expect(host.nativeVisibility.plans.isEmpty,
                         "disabling the organizer prevents a queued clock restoration from hiding anything")
        }
        do {
            let host = Host()
            host.refreshCompletions = [{ host.synchronizeVisibility() }]
            host.completeRefresh(permissionChanged: true)
            suite.expect(host.nativeVisibility.plans.count == 1 && host.refreshCompletions.isEmpty,
                         "startup refresh callbacks apply once rather than superseding an in-flight request")
            host.isUpdating = true
            host.completeRefresh(permissionChanged: false)
            suite.expect(host.nativeVisibility.plans.count == 1,
                         "inventory refresh leaves an existing activation time to finish")
            host.isUpdating = false
            host.temporaryBundle = "hidden"
            host.synchronizeVisibility()
            suite.expect(host.nativeVisibility.plans.last == ["always"],
                         "temporary activation reveals only its owner and preserves always-hidden apps")
        }
        do {
            let host = Host()
            host.usesNativeVisibility = false
            host.clockHoverChanged(true)
            host.completeRefresh(permissionChanged: false)
            suite.expect(!host.clockInteractionActive && host.nativeVisibility.releases == 0
                && host.nativeVisibility.plans.isEmpty,
                         "older systems do not use the assessment workaround or periodic native retries")
        }
    }
}
