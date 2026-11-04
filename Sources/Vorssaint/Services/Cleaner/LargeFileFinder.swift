// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import Foundation

/// Finds big files in the home folder and moves the ones you tick to the
/// Trash. Nothing starts selected: these are your own files, not leftovers.
final class LargeFileFinder: ObservableObject {
    static let shared = LargeFileFinder()

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: Int)
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let size: Int64
        let lastOpened: Date?
        /// Content modification date at scan time. With the size it proves,
        /// right before removal, that the file is still the one that was listed.
        let modified: Date?
        var details = Details()
        var include = false

        var name: String { url.lastPathComponent }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    /// What helps a person decide: what the file is, which app opens it, where
    /// it came from and when it was added. All of it is read, never guessed.
    struct Details: Equatable {
        var kind: String?
        var opensWith: String?
        var downloadedFrom: String?
        var added: Date?
        var safety: LargeFileSupport.Safety = .check
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [Item] = []
    private var cancellation: CleanerSupport.ScanCancellation?

    private init() {}

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }

    func setInclude(_ include: Bool, for id: UUID) {
        guard phase == .results, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    /// Ticks or clears everything. Files in cloud folders, code projects or
    /// virtual machine folders are never ticked this way, as in the
    /// duplicates tab; they can still be ticked one by one.
    func selectAll(_ include: Bool) {
        guard phase == .results else { return }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        for index in items.indices {
            let risky = DuplicateFileSupport.placement(of: items[index].url, home: home).risk != nil
            items[index].include = include && !risky
        }
    }

    func reset() {
        guard phase != .removing else { return }
        cancellation?.cancel()
        cancellation = nil
        items = []
        phase = .idle
    }

    func scan(minimumSize: Int64, olderThanDays: Int) {
        guard phase != .scanning, phase != .removing else { return }
        let cancel = CleanerSupport.ScanCancellation()
        cancellation = cancel
        items = []
        phase = .scanning
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.walk(home: home, minimumSize: minimumSize,
                                  olderThanDays: olderThanDays, cancel: cancel)
            DispatchQueue.main.async {
                // A reset or a newer scan replaced this one: drop its result.
                guard self.cancellation === cancel, !cancel.isCancelled else { return }
                self.items = found
                self.cancellation = nil
                self.phase = .results
            }
        }
    }

    func trashSelected() {
        guard phase == .results else { return }
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty else { return }
        phase = .removing
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0
            var failed = 0
            for item in chosen {
                guard LargeFileSupport.mayRemoveResolved(item.url, home: home),
                      Self.isPlainFile(item.url), Self.matchesScan(item) else { failed += 1; continue }
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                    freed += item.size
                } catch {
                    failed += 1
                }
            }
            DispatchQueue.main.async {
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
            }
        }
    }

    // MARK: - Walk

    /// Whether the file still has the size and date it had when it was listed,
    /// so a file replaced since the scan is never removed on an old listing.
    private static func matchesScan(_ item: Item) -> Bool {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                         .contentModificationDateKey]
        guard let values = try? item.url.resourceValues(forKeys: keys) else { return false }
        let size = (values.totalFileAllocatedSize ?? values.fileAllocatedSize).map(Int64.init)
        return DuplicateFileSupport.unchanged(scannedSize: item.size, scannedModified: item.modified,
                                              currentSize: size, currentModified: values.contentModificationDate)
    }

    private static func isPlainFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values?.isRegularFile == true && values?.isSymbolicLink != true
    }

    private static func walk(home: URL, minimumSize: Int64, olderThanDays: Int,
                             cancel: CleanerSupport.ScanCancellation) -> [Item] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentAccessDateKey, .contentModificationDateKey,
                                      .fileResourceIdentifierKey, .volumeIdentifierKey]
        guard let walker = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants, .skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }
        var found: [Item] = []
        // Hard links to one file are listed once, so sizes are not counted twice.
        var seen = Set<DuplicateFileSupport.FileIdentity>()
        for case let url as URL in walker {
            if cancel.isCancelled { return [] }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            if values.isDirectory == true {
                if LargeFileSupport.shouldSkipDirectory(url, home: home) { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minimumSize else { continue }
            if let identity = DuplicateFileSupport.identity(of: values), !seen.insert(identity).inserted {
                continue
            }
            found.append(Item(url: url, size: size, lastOpened: values.contentAccessDate,
                              modified: values.contentModificationDate))
        }
        // The age filter and the date shown must come from the same place, so
        // the filter runs here on the dates Spotlight reports (falling back to
        // the access time). Only the largest candidates are looked up.
        let now = Date()
        let candidates = found.sorted { $0.size > $1.size }.prefix(candidateCap).compactMap { item -> Item? in
            if cancel.isCancelled { return nil }
            let used = spotlightLastUsed(item.url) ?? item.lastOpened
            guard LargeFileSupport.qualifies(size: item.size, lastOpened: used, minimumSize: minimumSize,
                                             olderThanDays: olderThanDays, now: now) else { return nil }
            return Item(url: item.url, size: item.size, lastOpened: used, modified: item.modified)
        }
        if cancel.isCancelled { return [] }
        // Only the capped top of the list is looked at in detail.
        return LargeFileSupport.ranked(candidates) { $0.size }.map { enrich($0) }
    }

    /// How many of the largest files are checked against the age filter.
    private static let candidateCap = 10_000

    private static func spotlightLastUsed(_ url: URL) -> Date? {
        guard let mdItem = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
    }

    /// Adds the details and prefers Spotlight's last used date, which is the
    /// last time the file was actually opened, over the raw access time.
    private static func enrich(_ item: Item) -> Item {
        var details = Details()
        details.safety = LargeFileSupport.safety(of: item.url)
        details.kind = (try? item.url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?
            .localizedTypeDescription
        if let app = NSWorkspace.shared.urlForApplication(toOpen: item.url) {
            details.opensWith = FileManager.default.displayName(atPath: app.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        if let mdItem = MDItemCreateWithURL(nil, item.url as CFURL) {
            details.downloadedFrom = LargeFileSupport.sourceHost(
                from: MDItemCopyAttribute(mdItem, kMDItemWhereFroms) as? [String])
            details.added = MDItemCopyAttribute(mdItem, kMDItemDateAdded) as? Date
        }
        var enriched = Item(url: item.url, size: item.size, lastOpened: item.lastOpened,
                            modified: item.modified)
        enriched.details = details
        return enriched
    }
}
