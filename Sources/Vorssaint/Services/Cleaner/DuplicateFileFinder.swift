// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// Finds identical files in the home folder and moves extra copies to the
/// Trash. One copy of each file always stays: the finder refuses to tick the
/// last copy, and checks again at removal time.
final class DuplicateFileFinder: ObservableObject {
    static let shared = DuplicateFileFinder()

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
        let modified: Date?
        var include = false

        var name: String { url.lastPathComponent }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    struct Group: Identifiable, Equatable {
        let id = UUID()
        let size: Int64
        var items: [Item]
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var groups: [Group] = []
    private var cancellation: CleanerSupport.ScanCancellation?

    private init() {}

    var selectedCount: Int { groups.reduce(0) { $0 + $1.items.filter(\.include).count } }
    var selectedSize: Int64 {
        groups.reduce(0) { $0 + Int64($1.items.filter(\.include).count) * $1.size }
    }

    /// Ticks or clears one copy. Ticking is refused when it would leave the
    /// group with nothing unticked.
    func setInclude(_ include: Bool, for id: UUID) {
        guard phase == .results else { return }
        for g in groups.indices {
            guard let i = groups[g].items.firstIndex(where: { $0.id == id }) else { continue }
            if include {
                let ticked = groups[g].items.filter(\.include).count
                guard !groups[g].items[i].include,
                      DuplicateFileSupport.mayTick(tickedCount: ticked, groupCount: groups[g].items.count)
                else { return }
            }
            groups[g].items[i].include = include
            return
        }
    }

    /// Ticks every copy except the one that stays by default (the oldest), or
    /// clears everything.
    func selectExtras(_ select: Bool) {
        guard phase == .results else { return }
        for g in groups.indices {
            let keep = DuplicateFileSupport.defaultKeepIndex(modified: groups[g].items.map(\.modified))
            for i in groups[g].items.indices {
                groups[g].items[i].include = select && i != keep
            }
        }
    }

    func reset() {
        guard phase != .removing else { return }
        cancellation?.cancel()
        cancellation = nil
        groups = []
        phase = .idle
    }

    func scan(minimumSize: Int64) {
        guard phase != .scanning, phase != .removing else { return }
        let cancel = CleanerSupport.ScanCancellation()
        cancellation = cancel
        groups = []
        phase = .scanning
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.findGroups(home: home, minimumSize: minimumSize, cancel: cancel)
            DispatchQueue.main.async {
                guard self.cancellation === cancel, !cancel.isCancelled else { return }
                self.groups = found
                self.cancellation = nil
                self.phase = .results
            }
        }
    }

    func trashSelected() {
        guard phase == .results, selectedCount > 0 else { return }
        let snapshot = groups
        phase = .removing
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: Int64 = 0
            var failed = 0
            for group in snapshot {
                let chosen = group.items.filter(\.include)
                let kept = group.items.filter { !$0.include }
                // Never remove copies of a group unless a kept copy is still
                // on disk exactly as scanned.
                guard !chosen.isEmpty,
                      kept.contains(where: { Self.matchesScan($0, size: group.size) }) else {
                    failed += chosen.count
                    continue
                }
                for item in chosen {
                    guard LargeFileSupport.mayRemove(item.url, home: home),
                          Self.matchesScan(item, size: group.size) else { failed += 1; continue }
                    do {
                        try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                        freed += group.size
                    } catch {
                        failed += 1
                    }
                }
            }
            DispatchQueue.main.async {
                self.groups = []
                self.phase = .done(freed: freed, failed: failed)
            }
        }
    }

    // MARK: - Scan

    private static func matchesScan(_ item: Item, size: Int64) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                                         .contentModificationDateKey]
        guard let values = try? item.url.resourceValues(forKeys: keys),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return DuplicateFileSupport.unchanged(
            scannedSize: size, scannedModified: item.modified,
            currentSize: values.fileSize.map(Int64.init), currentModified: values.contentModificationDate)
    }

    private struct Candidate {
        let url: URL
        let size: Int64
        let modified: Date?
    }

    private static func findGroups(home: URL, minimumSize: Int64,
                                   cancel: CleanerSupport.ScanCancellation) -> [Group] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        guard let walker = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return [] }

        // Step 1: bucket by exact size. Hard links to the same data are one
        // file, not a duplicate, so each file identity is counted once.
        var bySize: [Int64: [Candidate]] = [:]
        var seen = Set<AnyHashable>()
        for case let url as URL in walker {
            if cancel.isCancelled { return [] }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            if values.isDirectory == true {
                if LargeFileSupport.shouldSkipDirectory(url, home: home) { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, let size = values.fileSize.map(Int64.init),
                  size >= minimumSize else { continue }
            if let identity = values.fileResourceIdentifier as? AnyHashable, !seen.insert(identity).inserted {
                continue
            }
            bySize[size, default: []].append(Candidate(url: url, size: size, modified: values.contentModificationDate))
        }

        // Step 2: within a size bucket, compare the first 64 KB, then the
        // whole file only for copies that still match.
        var groups: [Group] = []
        for (size, bucket) in bySize where bucket.count > 1 {
            var byPartial: [String: [Candidate]] = [:]
            for candidate in bucket {
                if cancel.isCancelled { return [] }
                guard let digest = digest(of: candidate.url, limit: DuplicateFileSupport.partialReadBytes,
                                          cancel: cancel) else { continue }
                byPartial[digest, default: []].append(candidate)
            }
            for (_, partialMatches) in byPartial where partialMatches.count > 1 {
                var byFull: [String: [Candidate]] = [:]
                for candidate in partialMatches {
                    if cancel.isCancelled { return [] }
                    guard let digest = digest(of: candidate.url, limit: nil, cancel: cancel) else { continue }
                    byFull[digest, default: []].append(candidate)
                }
                for (_, same) in byFull where same.count > 1 {
                    let ordered = same.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
                    groups.append(Group(size: size, items: ordered.map { Item(url: $0.url, modified: $0.modified) }))
                }
            }
        }
        return DuplicateFileSupport.ranked(groups, size: { $0.size }, copies: { $0.items.count })
    }

    /// SHA-256 of the first `limit` bytes, or of the whole file when `limit`
    /// is nil. Returns nil if the file cannot be read.
    private static func digest(of url: URL, limit: Int?,
                               cancel: CleanerSupport.ScanCancellation) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if cancel.isCancelled { return nil }
            let chunk = (try? handle.read(upToCount: min(1 << 20, remaining))) ?? nil
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
