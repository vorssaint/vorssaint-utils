// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Cleanup, shortcut synchronization and Homebrew completion are extracted
/// from production. Only the application scan, scheduler, hotkey backend and
/// view updates are replaced; preferences and paths belong to this fixture.
enum UninstallerCommandBarCleanupTests {
    enum Preferences { static var standard: UserDefaults! }
    enum Feature {
        case commandBar
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    struct App { let bundleID: String?; let url: URL }
    struct Entry { let uninstallAppURL: URL? }
    enum Apps {
        static var remaining: [App] = []
        static var scans = 0
        static var scannedOnMain = false
        static func installedApplications(includeSystemApplications: Bool, spotlightPaths: [String]) -> [App] {
            scans += 1
            scannedOnMain = scannedOnMain || Queue.isMain
            return remaining
        }
    }
    enum Queue {
        enum QoS { case utility }
        struct Executor {
            let isMain: Bool
            func async(execute: @escaping () -> Void) {
                Queue.pending.append((isMain, execute))
            }
        }
        static var isMain = true
        static var pending: [(Bool, () -> Void)] = []
        static var main: Executor { Executor(isMain: true) }
        static func global(qos: QoS) -> Executor { Executor(isMain: false) }
        static func step() {
            guard !pending.isEmpty else { return }
            let (onMain, work) = pending.removeFirst()
            isMain = onMain
            work()
            isMain = true
        }
        static func drain() { while !pending.isEmpty { step() } }
    }
    final class Hotkey {
        static var registrations = 0
        static var unregistrations = 0
        var onPress: (() -> Void)?
        init(id: UInt32) {}
        func unregister() { Self.unregistrations += 1 }
        func sync(enabled: Bool, shortcut: GlobalShortcut, storageKey: String) -> Bool {
            if enabled { Self.registrations += 1 }
            return true
        }
    }
    enum Takeover {
        static var cleared: Set<String> = []
        static func setTakeOver(_ key: String, _ enabled: Bool) {
            if !enabled { cleared.insert(key) }
        }
    }
    class ServiceState {
        typealias UserDefaults = Preferences
        typealias AppFeature = Feature
        typealias QuickToolHotkey = Hotkey
        typealias SystemShortcutTakeover = Takeover
        var cachedApps: [App] = []
        var uninstallSelectionEntries: [Entry] = []
        var rowHotkeys: [Hotkey] = []
        var refusedRowShortcutKeys: Set<String> = []
        var refreshes = 0
        static func spotlightApplicationPaths() -> [String] { [] }
        func runRow(withStableKey key: String) {}
        func rebuildRunningEntries() {}
        func refreshAfterPreferenceChange() { refreshes += 1 }
    }
    struct Package: Equatable { let id: String }
    enum PackageAction { case uninstall }
    struct OperationStatus {
        let action: PackageAction
        let package: Package?
        let isActive: Bool
    }
    final class PackageManager {
        static let shared = PackageManager()
        var operationStatus: OperationStatus?
    }
    struct Target { let url: URL; let bundleID: String? }
    enum Category: Equatable { case app, support }
    struct Leftover: Equatable {
        let id = UUID()
        let url: URL
        let category: Category
        let size: Int64
        var include = true
    }
    class UninstallerState {
        typealias DispatchQueue = Queue
        typealias InstalledApps = Apps
        typealias CommandBarService = Service
        typealias HomebrewPackage = Package
        typealias HomebrewManager = PackageManager
        var phase: Phase = .results
        var target: Target?
        var homebrewPackage: Package?
        var homebrewRemovedApplication = false
        var homebrewRemovalSize: Int64 = 0
        var items: [Leftover] = []
        var removals = 0
        func removeSelected() { removals += 1; phase = .removing }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.uninstall-command-bar.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        Preferences.standard = defaults
        let fm = FileManager.default
        let root = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("uninstall-command-bar-\(UUID())")
        let removed = root.appendingPathComponent("Removed.app")
        let survivor = root.appendingPathComponent("Other Copy.app")
        let other = root.appendingPathComponent("Unrelated.app")
        let bundleID = "org.vorssaint.fixture.shared"
        let sharedKey = "app.bundle.\(bundleID)"
        let otherKey = "app.bundle.org.vorssaint.fixture.other"
        let pathKey = "app.\(removed.path)"
        let service = Service.shared
        let shortcut = GlobalShortcut(keyCode: 11, modifiers: [.option, .command])
        let otherShortcut = GlobalShortcut(keyCode: 45, modifiers: [.option, .command])
        defer {
            Queue.pending = []
            service.cachedApps = []
            service.uninstallSelectionEntries = []
            service.rowHotkeys = []
            Apps.remaining = []
            PackageManager.shared.operationStatus = nil
            Preferences.standard = nil
            Feature.available = true
            defaults.removePersistentDomain(forName: domain)
            try? fm.removeItem(at: root)
        }
        func seed(shared: Bool = true) {
            PackageManager.shared.operationStatus = nil
            defaults.removePersistentDomain(forName: domain)
            var shortcuts = [otherKey: otherShortcut]
            if shared { shortcuts[sharedKey] = shortcut }
            else { shortcuts[pathKey] = shortcut }
            defaults.set(CommandBarRowShortcuts.encode(shortcuts), forKey: DefaultsKey.commandBarRowShortcuts)
            defaults.set(CommandBarPreferences.encodeAliases(
                shared ? [sharedKey: "work", otherKey: "other"] : [otherKey: "other"]),
                forKey: DefaultsKey.commandBarAliases)
            defaults.set(CommandBarPreferences.encodePins(shared ? [sharedKey, otherKey] : [otherKey]),
                         forKey: DefaultsKey.commandBarPins)
            defaults.set(CommandBarPreferences.encodeHidden(shared ? [sharedKey, otherKey] : [otherKey]),
                         forKey: DefaultsKey.commandBarHidden)
            defaults.set(CommandBarUsage.encode([
                pathKey: CommandBarUse(count: 3, lastUsed: 1),
                "app.\(survivor.path)": CommandBarUse(count: 5, lastUsed: 1),
            ]), forKey: DefaultsKey.commandBarUsage)
            service.cachedApps = [App(bundleID: bundleID, url: removed),
                                  App(bundleID: bundleID, url: survivor),
                                  App(bundleID: "org.vorssaint.fixture.other", url: other)]
            service.uninstallSelectionEntries = [Entry(uninstallAppURL: removed)]
            service.rowHotkeys = [Hotkey(id: 200)]
            service.refreshes = 0
            Apps.scans = 0
            Apps.scannedOnMain = false
            Hotkey.registrations = 0
            Hotkey.unregistrations = 0
            Takeover.cleared = []
            Feature.available = true
        }
        func sharedStatePresent() -> Bool {
            service.rowShortcuts[sharedKey] == shortcut && service.storedAliases[sharedKey] == "work"
                && service.storedPins.contains(sharedKey) && service.storedHiddenKeys.contains(sharedKey)
        }
        do {
            try fm.createDirectory(at: survivor, withIntermediateDirectories: true)
            seed()
            Apps.remaining = [App(bundleID: bundleID, url: survivor)]
            Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: bundleID)
            suite.expect(Apps.scans == 0 && sharedStatePresent(),
                         "uninstall cleanup leaves scanning and mutation off the immediate completion path")
            Queue.drain()
            suite.expect(sharedStatePresent() && Takeover.cleared.isEmpty,
                         "another installed copy retains the shared shortcut, alias, pin, hidden state and takeover")
            let usage = CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))
            suite.expect(service.cachedApps.map(\.url) == [survivor, other]
                         && service.uninstallSelectionEntries.isEmpty
                         && usage[pathKey] == nil && usage["app.\(survivor.path)"]?.count == 5,
                         "removing one copy clears only its path row and usage while retaining the other copy")
            suite.expect(Apps.scans == 1 && !Apps.scannedOnMain,
                         "shared state checks remaining applications once outside the main thread")

            seed()
            Apps.remaining = []
            Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: bundleID)
            Queue.drain()
            suite.expect(!service.hasStoredApplicationState(bundleID: bundleID)
                         && service.rowShortcuts[otherKey] == otherShortcut
                         && service.storedAliases[otherKey] == "other"
                         && service.storedPins == [otherKey] && service.storedHiddenKeys == [otherKey],
                         "the last copy releases all shared preferences without removing another app's choices")
            suite.expect(Takeover.cleared == [CommandBarRowShortcuts.takeOverKey(for: sharedKey)]
                         && Hotkey.unregistrations == 1 && Hotkey.registrations == 1,
                         "cleanup releases the removed takeover and resynchronizes the remaining shortcut")

            seed()
            defaults.set(CommandBarRowShortcuts.encode([otherKey: otherShortcut]),
                         forKey: DefaultsKey.commandBarRowShortcuts)
            Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: bundleID)
            Queue.drain()
            suite.expect(Apps.scans == 1 && service.storedAliases[sharedKey] == nil,
                         "aliases, pins and hidden rows also get the last-copy check without an app shortcut")

            for id in [bundleID, nil] as [String?] {
                seed(shared: false)
                Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: id)
                Queue.drain()
                suite.expect(Apps.scans == 0 && service.rowShortcuts[pathKey] == nil,
                             "path-only preferences, with or without a bundle ID, need no installed-app scan")
            }

            seed()
            Feature.available = false
            Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: bundleID)
            Queue.drain()
            suite.expect(!service.hasStoredApplicationState(bundleID: bundleID)
                         && Hotkey.registrations == 0 && Hotkey.unregistrations == 1,
                         "disabled Command Bar still forgets removed-app state without registering a hotkey")

            seed()
            try fm.createDirectory(at: removed, withIntermediateDirectories: true)
            Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: bundleID)
            Queue.drain()
            suite.expect(sharedStatePresent() && Apps.scans == 0 && service.refreshes == 0,
                         "a failed or cancelled removal with the bundle still present changes no state")
            try fm.removeItem(at: removed)
            Uninstaller.removeCommandBarState(ofRemovedAppAt: removed, bundleID: bundleID)
            Queue.step()
            try fm.createDirectory(at: removed, withIntermediateDirectories: true)
            Queue.drain()
            suite.expect(sharedStatePresent() && service.refreshes == 0,
                         "a reinstall at the removed path while the scan is pending preserves its preferences")
            try fm.removeItem(at: removed)

            seed()
            let package = Package(id: "fixture")
            func brewRemoval(leftovers: Bool = false) -> Uninstaller {
                // @Published delivers completion before the stored status
                // stops reporting the operation as active.
                PackageManager.shared.operationStatus = OperationStatus(
                    action: .uninstall, package: package, isActive: true)
                let uninstaller = Uninstaller()
                uninstaller.target = Target(url: removed, bundleID: bundleID)
                uninstaller.homebrewPackage = package
                uninstaller.items = [Leftover(url: removed, category: .app, size: 12)]
                if leftovers {
                    uninstaller.items.append(Leftover(url: root.appendingPathComponent("Support"),
                                                      category: .support, size: 3))
                }
                return uninstaller
            }
            let brew = brewRemoval()
            suite.expect(brew.isRemovingWithHomebrew && brew.isRemoving,
                         "Homebrew completion begins while its stored status still blocks selection changes")
            brew.finishRemovalAfterHomebrew(package: package)
            Queue.drain()
            suite.expect(brew.phase == .done(freed: 12, failed: [])
                         && !service.hasStoredApplicationState(bundleID: bundleID) && Apps.scans == 1,
                         "Homebrew completion without leftovers runs the same last-copy cleanup once")
            seed()
            Apps.remaining = [App(bundleID: bundleID, url: survivor)]
            let duplicateBrew = brewRemoval()
            duplicateBrew.finishRemovalAfterHomebrew(package: package)
            Queue.drain()
            suite.expect(sharedStatePresent() && Apps.scans == 1,
                         "Homebrew removal also preserves preferences shared with another installed copy")
            let leftovers = brewRemoval(leftovers: true)
            leftovers.finishRemovalAfterHomebrew(package: package)
            suite.expect(leftovers.removals == 1 && leftovers.phase == .removing
                         && Queue.pending.isEmpty,
                         "Homebrew with leftovers defers cleanup to the ordinary removal completion")
            try fm.createDirectory(at: removed, withIntermediateDirectories: true)
            let incompleteBrew = brewRemoval()
            incompleteBrew.finishRemovalAfterHomebrew(package: package)
            suite.expect(incompleteBrew.removals == 1 && incompleteBrew.homebrewRemovalSize == 0
                         && sharedStatePresent() && Queue.pending.isEmpty,
                         "a Homebrew success that leaves the app asks for its removal before cleaning preferences")
        } catch {
            suite.expect(false, "uninstall command bar cleanup fixture failed: \(error)")
        }
    }
}
