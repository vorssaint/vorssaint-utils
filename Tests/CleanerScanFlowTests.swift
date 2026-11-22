// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production scan and reset run against recorded category scans and a
/// manual queue. No file system locations are read.
enum CleanerScanFlowTests {
    struct Item {
        let url: URL
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
        static func record(_ category: CleanerSupport.Category) -> [Item] {
            scanned.append(category)
            onScan?(category)
            return [Item(url: URL(fileURLWithPath: "/fixture/\(category.rawValue)"))]
        }
        static var leftoverOwners: Set<String> = []
        static var cachePluginIDs: Set<String> = []
        static func installedBundleIDs() -> Set<String> { ["com.fixture.editor"] }
        static func installedAudioPluginBundleIDs() -> Set<String> { ["com.fixture.synth"] }
        static func scanLeftovers(installed: Set<String>) -> [Item] {
            leftoverOwners = installed
            return record(.leftovers)
        }
        static func scanOrphanedLaunchPlists(installed: Set<String>) -> [Item] { record(.loginItems) }
        static func scanCaches(excluding: Set<String>, audioPluginIDs: Set<String>) -> [Item] {
            cachePluginIDs = audioPluginIDs
            return record(.caches)
        }
        static func scanLogs(excluding: Set<String>) -> [Item] { record(.logs) }
        static func scanDeveloperJunk() -> [Item] { record(.developer) }
        static func scanTrash() -> [Item] { record(.trash) }
        static func scanDeviceBackups() -> [Item] { record(.deviceBackups) }
        static func screenshotSearch() -> (folders: [URL], days: Int)? { ([], 30) }
        static func scanScreenshots(in folders: [URL], days: Int) -> [Item] { record(.screenshots) }
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
        Scanner.leftoverOwners = []
        Scanner.cachePluginIDs = []
        cleaner.scan(attended: false)
        Queue.drain()
        suite.expect(Scanner.scanned == all.filter { $0 != .screenshots } && cleaner.phase == .results,
                     "an unattended scan never reads the screenshot folders")
        suite.expect(Scanner.leftoverOwners == ["com.fixture.editor", "com.fixture.synth"]
                     && Scanner.cachePluginIDs == ["com.fixture.synth"],
                     "scheduled scans protect plugin caches and keep ordinary app caches eligible")
    }
}
