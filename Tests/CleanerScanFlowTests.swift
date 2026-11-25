// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production scan and cleanup run on a manual queue with temporary
/// libraries and recorded cleanup actions.
enum CleanerScanFlowTests {
    typealias Item = CleanerEligibilityTests.Item
    enum CleanupAction: Equatable {
        case bootout(URL), trash(URL), finderConsent(String), finder([URL]), emptyTrash
    }
    struct FixtureTrash {
        static let `default` = FixtureTrash()
        func trashItem(at url: URL, resultingItemURL _: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
            guard Scanner.perform(.trash(url)) else { throw CocoaError(.fileWriteNoPermission) }
        }
    }
    enum AppleScriptRunner {
        static func consentToAutomate(bundleID: String) -> Bool {
            Scanner.perform(.finderConsent(bundleID))
        }
    }
    enum Queue {
        enum QoS { case userInitiated }
        static var pending: [() -> Void] = []
        static var main: Queue.Type { Self.self }
        static func global(qos: QoS) -> Queue.Type { Self.self }
        static func async(execute: @escaping () -> Void) { pending.append(execute) }
        static func drain() {
            while !pending.isEmpty { pending.removeFirst()() }
        }
    }
    class ScannerState {
        typealias DispatchQueue = Queue
        var phase: Phase = .idle
        var items: [Item] = []
        var scanningCategory: CleanerSupport.Category?
        var scanToken = UUID()
        var scanCancellation: CleanerSupport.ScanCancellation?
        static var scanned: [CleanerSupport.Category] = []
        static var onScan: ((CleanerSupport.Category) -> Void)?
        static var fixtureApps: Set<String>?
        static var fixturePlugins: Set<String>?
        static var appReads = 0
        static var pluginReads = 0
        static var actions: [CleanupAction] = []
        static var onAction: ((CleanupAction) -> Bool)?
        @discardableResult
        static func perform(_ action: CleanupAction) -> Bool {
            actions.append(action)
            return onAction?(action) ?? true
        }
        static func mayRemove(_ item: Item, installedApps: () -> Set<String>, audioPluginIDs: Set<String>) -> Bool {
            CleanerEligibilityTests.canRemove(item, installed: installedApps(), audioPluginIDs: audioPluginIDs)
        }
        static func bootoutUserAgent(_ url: URL) { perform(.bootout(url)) }
        static func trashViaFinder(_ urls: [URL]) { perform(.finder(urls)) }
        static func emptyTrash() -> Bool { perform(.emptyTrash) }
        static func record(_ category: CleanerSupport.Category) -> [Item] {
            guard fixtureApps == nil else { return [] }
            scanned.append(category)
            onScan?(category)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            return [Item(url: url, category: category, detail: "")]
        }
        static func installedBundleIDs() -> Set<String> {
            appReads += 1
            return fixtureApps ?? []
        }
        static func installedAudioPluginBundleIDs() -> Set<String> {
            pluginReads += 1
            if let fixturePlugins { return fixturePlugins }
            return fixtureApps == nil ? [] : CleanerEligibilityTests.installedAudioPluginBundleIDs()
        }
        static func scanLeftovers(installedApps: Set<String>, audioPluginIDs: Set<String>) -> [Item] {
            if fixtureApps != nil {
                return CleanerEligibilityTests.scanLeftovers(installedApps: installedApps, audioPluginIDs: audioPluginIDs)
            }
            return record(.leftovers)
        }
        static func scanOrphanedLaunchPlists(installed: Set<String>) -> [Item] {
            if fixtureApps != nil { return CleanerEligibilityTests.scanOrphanedLaunchPlists(installed: installed) }
            return record(.loginItems)
        }
        static func scanCaches(excluding: Set<String>, audioPluginIDs: Set<String>) -> [Item] {
            if fixtureApps != nil {
                return CleanerEligibilityTests.scanCaches(excluding: excluding, audioPluginIDs: audioPluginIDs)
            }
            return record(.caches)
        }
        static func scanLogs(excluding: Set<String>) -> [Item] {
            if fixtureApps != nil {
                return CleanerEligibilityTests.scanLogs(excluding: excluding)
            }
            return record(.logs)
        }
        static func scanDeveloperJunk() -> [Item] { record(.developer) }
        static func scanTrash() -> [Item] { record(.trash) }
        static func scanDeviceBackups() -> [Item] { record(.deviceBackups) }
        static func screenshotSearch() -> (folders: [URL], days: Int)? { ([], 30) }
        static func scanScreenshots(in folders: [URL], days: Int) -> [Item] { record(.screenshots) }
    }

    static func scanFixture(installedApps: Set<String>, attended: Bool = false) -> [Item] {
        Scanner.fixtureApps = installedApps
        defer { Scanner.fixtureApps = nil }
        let cleaner = Scanner()
        cleaner.scan(attended: attended)
        Queue.drain()
        return cleaner.items
    }

    static func cleanFixture(_ item: Item, installedApps: Set<String>) -> (Phase, [CleanupAction]) {
        let result = cleanFixture([item], installedApps: installedApps)
        return (result.phase, result.actions)
    }

    private static func cleanFixture(_ items: [Item], installedApps: Set<String> = [],
                                     onAction: ((CleanupAction) -> Bool)? = nil)
        -> (phase: Phase, actions: [CleanupAction], appReads: Int, pluginReads: Int) {
        Scanner.fixtureApps = installedApps
        Scanner.appReads = 0
        Scanner.pluginReads = 0
        Scanner.onAction = onAction
        defer {
            Scanner.fixtureApps = nil
            Scanner.fixturePlugins = nil
            Scanner.actions = []
            Scanner.onAction = nil
        }
        let cleaner = Scanner()
        cleaner.items = items
        cleaner.cleanSelected(escalate: true)
        Queue.drain()
        return (cleaner.phase, Scanner.actions, Scanner.appReads, Scanner.pluginReads)
    }

    private static func checkCleanupInventories(_ suite: TestSuite) throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("vorssaint-inventory-\(UUID().uuidString)", isDirectory: true)
        let home = sandbox.appendingPathComponent("user", isDirectory: true)
        CleanerEligibilityTests.fixtureRoot = home
        defer {
            CleanerEligibilityTests.fixtureRoot = nil
            try? fm.removeItem(at: sandbox)
        }
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        try fm.createDirectory(at: agents, withIntermediateDirectories: true)
        try fm.createDirectory(at: preferences, withIntermediateDirectories: true)
        let missing = home.appendingPathComponent("missing").path
        let orphanLabel = "org.orphan.helper"
        let labels = ["app.editor.helper", "audio.synth.helper", orphanLabel]
        for label in labels {
            try PropertyListSerialization.data(fromPropertyList: ["Label": label, "Program": missing],
                                               format: .xml, options: 0)
                .write(to: agents.appendingPathComponent(label + ".plist"))
            try Data([1]).write(to: preferences.appendingPathComponent(label + ".plist"))
        }
        let found = scanFixture(installedApps: [])
        let items = found.filter { $0.category == .loginItems }
        guard Set(items.map(\.detail)) == Set(labels),
              let orphan = items.first(where: { $0.detail == orphanLabel }) else {
            suite.expect(false, "all three unowned agents must be selectable before cleanup")
            return
        }
        let ordinary = cleanFixture(items)
        let directMoves = items.map { CleanupAction.trash($0.url) }
        let total = items.reduce(Int64(0)) { $0 + $1.size }
        suite.expect(ordinary.actions == directMoves && ordinary.phase == .done(freed: total, failed: 0)
                     && ordinary.appReads == 1 && ordinary.pluginReads == 1,
                     "the direct Trash pass shares each inventory across all selected login items")

        func installOwners() {
            Scanner.fixtureApps = ["app.editor"]
            Scanner.fixturePlugins = ["audio.synth"]
        }
        let trash = Item(url: home.appendingPathComponent(".Trash"), category: .trash, size: 64,
                         detail: "", recommended: true)
        let afterEmpty = cleanFixture([trash] + items) { action in
            if action == .emptyTrash { installOwners() }
            return true
        }
        suite.expect(afterEmpty.actions == [.emptyTrash, .trash(orphan.url)]
                     && afterEmpty.phase == .done(freed: trash.size + orphan.size, failed: 2),
                     "owners installed while the Trash is being emptied protect their agents from the first move")

        let refusedAgents = cleanFixture(items) { _ in false }
        suite.expect(refusedAgents.actions == directMoves && refusedAgents.phase == .done(freed: 0, failed: items.count),
                     "failed login item moves count as failures without asking Finder for consent")

        var leftovers = found.filter { $0.category == .leftovers }
        guard Set(leftovers.map(\.detail)) == Set(labels),
              let unownedPreference = leftovers.first(where: { $0.detail == orphanLabel }) else {
            suite.expect(false, "all three unowned preferences must be available for review")
            return
        }
        for index in leftovers.indices { leftovers[index].include = true }
        let mixed = [orphan] + leftovers
        let consent = CleanupAction.finderConsent("com.apple.finder")
        let afterConsent = cleanFixture(mixed) { action in
            if case .trash = action { return false }
            if action == consent { installOwners() }
            return true
        }
        let mixedMoves = mixed.map { CleanupAction.trash($0.url) }
        suite.expect(afterConsent.actions == mixedMoves + [consent, .finder([unownedPreference.url])]
                     && afterConsent.phase == .done(freed: 0, failed: mixed.count)
                     && afterConsent.appReads == 2 && afterConsent.pluginReads == 2,
                     "Finder receives only the still-unowned preference after consent, leaving the login item in place")
    }

    static func run(_ suite: TestSuite) {
        let cleaner = Scanner.shared
        let all = CleanerSupport.Category.allCases
        defer {
            Queue.pending = []
            Scanner.onScan = nil
            Scanner.scanned = []
            cleaner.reset()
        }

        cleaner.scan(attended: true)
        Queue.drain()
        suite.expect(Scanner.scanned == all && cleaner.phase == .results && cleaner.items.count == all.count,
                     "an uninterrupted scan visits every category and delivers its results")

        cleaner.reset()
        Scanner.scanned = []
        cleaner.scan(attended: true)
        cleaner.reset()
        Queue.drain()
        suite.expect(Scanner.scanned.isEmpty && cleaner.phase == .idle,
                     "canceling before the scan starts skips every category")

        Scanner.scanned = []
        Scanner.onScan = { if $0 == .caches { cleaner.reset() } }
        cleaner.scan(attended: true)
        Queue.drain()
        Scanner.onScan = nil
        suite.expect(Scanner.scanned == [.leftovers, .loginItems, .caches]
                     && cleaner.phase == .idle && cleaner.items.isEmpty,
                     "canceling mid-scan stops at the next category and delivers nothing")

        Scanner.scanned = []
        cleaner.scan(attended: true)
        cleaner.reset()
        cleaner.scan(attended: true)
        Queue.drain()
        suite.expect(Scanner.scanned == all && cleaner.phase == .results && cleaner.items.count == all.count,
                     "a scan started right after a cancel runs alone, without the canceled one")

        cleaner.reset()
        Scanner.scanned = []
        cleaner.scan(attended: false)
        Queue.drain()
        suite.expect(Scanner.scanned == all.filter { $0 != .screenshots } && cleaner.phase == .results,
                     "an unattended scan never reads the screenshot folders")

        do {
            try checkCleanupInventories(suite)
        } catch {
            suite.expect(false, "cleanup inventory fixture failed: \(error)")
        }
    }
}
