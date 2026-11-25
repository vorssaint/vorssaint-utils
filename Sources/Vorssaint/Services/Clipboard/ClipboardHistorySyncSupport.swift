// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Foundation

/// One history entry as the other Macs see it. Entries are matched by their
/// content, the way the local history already folds a copy it has seen into
/// the entry it had, so the same text copied on two Macs is one entry on both.
struct ClipboardHistorySyncRecord: Equatable {
    let key: String
    let kind: ClipboardHistoryEntryKind
    /// The content of a text entry; empty for an image, whose bytes travel
    /// beside the record.
    let text: String
    let copiedAt: Date
    let pinnedAt: Date?
    /// When the pin was last set or cleared by hand, so the latest change wins
    /// on every Mac. Nil when nobody changed it since syncing began.
    let pinChangedAt: Date?
    let source: String?
    let imageWidth: Int?
    let imageHeight: Int?
}

/// What one Mac has published: its entries and the deletions it knows of.
/// Only that Mac ever writes them, so iCloud never holds two versions of one
/// record to choose between: every Mac reads the others' and merges them into
/// its own history.
struct ClipboardHistorySyncDevice: Equatable {
    let device: String
    let records: [ClipboardHistorySyncRecord]
    /// Content keys that were deleted or cleared, and when.
    let deleted: [String: Date]
}

/// What this Mac lets into and out of iCloud. It is the same gate the history
/// itself applies, so nothing the history would have left out on one Mac
/// reaches another through sync.
struct ClipboardHistorySyncPolicy: Equatable {
    var includesImages: Bool
    var skipsSensitiveText: Bool
    var ignoredApps: Set<String>
}

enum ClipboardHistorySync {
    /// Bounds on what one Mac publishes. Copied files are never synced: a
    /// path names a file on one Mac's disk and means nothing on another.
    static let maxRecords = 500
    static let maxImages = 100
    static let maxTextBytes = 256 * 1_024
    static let maxTotalTextBytes = 16 * 1_024 * 1_024
    static let maxImageBytes = 8 * 1_024 * 1_024
    static let maxImageSide = 100_000
    /// How long a deletion is remembered, and how long a Mac may stay silent
    /// before its entries are ignored. Tying the two together keeps a Mac that
    /// comes back after a long time from undoing deletions nobody remembers.
    static let tombstoneLifetime: TimeInterval = 90 * 86_400
    static let maxTombstones = 5_000
    /// Stands in for an image that still has to be fetched while the merged
    /// list is trimmed; never a real file name in the image store.
    static let pendingImageFile = "pending-sync-image"

    // MARK: - Keys

    static func key(for entry: ClipboardHistoryEntry) -> String? {
        switch entry.kind {
        case .text:
            return textKey(entry.text)
        case .image:
            guard let hash = entry.imageHash, isHash(hash) else { return nil }
            return "i:" + hash
        case .files:
            return nil
        }
    }

    static func textKey(_ text: String) -> String {
        "t:" + sha256Hex(Data(text.utf8))
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func isValidKey(_ key: String) -> Bool {
        (key.hasPrefix("t:") || key.hasPrefix("i:")) && isHash(String(key.dropFirst(2)))
    }

    /// The image hash a key names.
    static func imageHash(fromKey key: String) -> String? {
        guard key.hasPrefix("i:"), isValidKey(key) else { return nil }
        return String(key.dropFirst(2))
    }

    static func kind(ofKey key: String) -> ClipboardHistoryEntryKind? {
        guard isValidKey(key) else { return nil }
        return key.hasPrefix("t:") ? .text : .image
    }

    /// A Mac's name in iCloud: a hash, so its records say nothing about the
    /// machine. The bundle keeps a developer build from writing the same
    /// records as the release build beside it.
    static func deviceIdentifier(hardware: String, user: String, bundle: String) -> String {
        String(sha256Hex(Data("\(hardware)\n\(user)\n\(bundle)".utf8)).prefix(32))
    }

    static func isValidDevice(_ device: String) -> Bool {
        (1...64).contains(device.utf8.count)
            && device.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    // MARK: - The gate

    static func allows(kind: ClipboardHistoryEntryKind, text: String, source: String?,
                       policy: ClipboardHistorySyncPolicy) -> Bool {
        switch kind {
        case .files:
            return false
        case .image:
            guard policy.includesImages else { return false }
        case .text:
            if policy.skipsSensitiveText, ClipboardHistorySensitiveText.looksSensitive(text) { return false }
        }
        if let source, policy.ignoredApps.contains(source) { return false }
        return true
    }

    static func allows(_ entry: ClipboardHistoryEntry, policy: ClipboardHistorySyncPolicy) -> Bool {
        allows(kind: entry.kind, text: entry.text, source: entry.sourceBundleID, policy: policy)
    }

    static func allows(_ record: ClipboardHistorySyncRecord, policy: ClipboardHistorySyncPolicy) -> Bool {
        allows(kind: record.kind, text: record.text, source: record.source, policy: policy)
    }

    /// The keys a deletion leaves behind. Only an entry this Mac would have
    /// published gets one, so even the hash of something the history kept
    /// private never leaves the Mac.
    static func deletedKeys(for removed: [ClipboardHistoryEntry], policy: ClipboardHistorySyncPolicy) -> [String] {
        removed.compactMap { allows($0, policy: policy) ? key(for: $0) : nil }
    }

    // MARK: - Publishing

    /// This Mac's records: pinned entries first, then the recent ones in the
    /// order the history shows them, inside the bounds above.
    static func records(for entries: [ClipboardHistoryEntry],
                        policy: ClipboardHistorySyncPolicy,
                        pinChanges: [String: Date],
                        imageBytes: (ClipboardHistoryEntry) -> Int?) -> [ClipboardHistorySyncRecord] {
        var result: [ClipboardHistorySyncRecord] = []
        var seen: Set<String> = []
        var images = 0
        var textBytes = 0
        for entry in entries.filter(\.isPinned) + entries.filter({ !$0.isPinned }) {
            guard result.count < maxRecords else { break }
            guard allows(entry, policy: policy), let key = key(for: entry), !seen.contains(key) else { continue }
            switch entry.kind {
            case .text:
                let bytes = entry.text.utf8.count
                guard bytes <= maxTextBytes, textBytes + bytes <= maxTotalTextBytes,
                      !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                textBytes += bytes
            case .image:
                guard images < maxImages, let size = imageBytes(entry), size > 0, size <= maxImageBytes
                else { continue }
                images += 1
            case .files:
                continue
            }
            seen.insert(key)
            result.append(ClipboardHistorySyncRecord(
                key: key,
                kind: entry.kind,
                text: entry.kind == .text ? entry.text : "",
                copiedAt: entry.copiedAt,
                pinnedAt: entry.pinnedAt,
                pinChangedAt: pinChanges[key],
                source: entry.sourceBundleID,
                imageWidth: entry.kind == .image ? entry.imageWidth : nil,
                imageHeight: entry.kind == .image ? entry.imageHeight : nil))
        }
        return result
    }

    // MARK: - Reading

    /// The deletions one Mac lists, as stored beside its entries. Exact
    /// seconds keep a deletion and the copy it follows comparable on every Mac.
    static func encodedDeleted(_ deleted: [String: Date]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(deleted.mapValues(\.timeIntervalSinceReferenceDate))
    }

    static func decodedDeleted(_ data: Data) -> [String: Date] {
        guard data.count <= maxDeletedBytes,
              let raw = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        var deleted: [String: Date] = [:]
        for (key, seconds) in raw where isValidKey(key) && seconds.isFinite {
            deleted[key] = Date(timeIntervalSinceReferenceDate: seconds)
        }
        return deleted
    }

    /// Room for every remembered deletion, under CloudKit's record size.
    static let maxDeletedBytes = 900 * 1_024

    /// Another Mac's entry, checked before it is trusted: the private
    /// database holds only what this user's devices wrote, but a record that
    /// does not look like what this version writes is still left out.
    static func isValid(_ record: ClipboardHistorySyncRecord) -> Bool {
        guard kind(ofKey: record.key) == record.kind else { return false }
        if let source = record.source,
           source.isEmpty || source.utf8.count > 255 { return false }
        switch record.kind {
        case .text:
            return record.text.utf8.count <= maxTextBytes
                && !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && textKey(record.text) == record.key
        case .image:
            let sides = [record.imageWidth, record.imageHeight].compactMap { $0 }
            return record.text.isEmpty && sides.allSatisfy { (1...maxImageSide).contains($0) }
        case .files:
            return false
        }
    }

    /// A Mac that has not been seen for as long as deletions are remembered
    /// no longer counts: its entries could otherwise return after their
    /// deletion was forgotten.
    static func isStale(seen: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(seen) > tombstoneLifetime
    }

    static func prunedTombstones(_ tombstones: [String: Date], now: Date = Date()) -> [String: Date] {
        let cutoff = now.addingTimeInterval(-tombstoneLifetime)
        let fresh = tombstones.filter { isValidKey($0.key) && $0.value >= cutoff }
        guard fresh.count > maxTombstones else { return fresh }
        let newest = fresh.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(maxTombstones)
        return Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
    }

    /// Pin clocks only matter while the entry exists or its last change could
    /// still meet an older copy elsewhere.
    static func prunedPinChanges(_ changes: [String: Date], keeping keys: Set<String>,
                                 now: Date = Date()) -> [String: Date] {
        let cutoff = now.addingTimeInterval(-tombstoneLifetime)
        return changes.filter { isValidKey($0.key) && (keys.contains($0.key) || $0.value >= cutoff) }
    }

    /// Later of two dictionaries' dates per key.
    static func latest(_ lhs: [String: Date], _ rhs: [String: Date]) -> [String: Date] {
        lhs.merging(rhs) { max($0, $1) }
    }

    // MARK: - Merging

    struct Merge: Equatable {
        var entries: [ClipboardHistoryEntry]
        /// Every deletion seen, this Mac's and the others', passed on so a
        /// deletion survives the Mac it was made on leaving sync.
        var tombstones: [String: Date]
        var pinChanges: [String: Date]
    }

    /// The best copy of one key across the other Macs.
    private struct Remote {
        var record: ClipboardHistorySyncRecord
        var copiedAt: Date
        var pinnedAt: Date?
        var pinClock: Date?

        var activity: Date { max(copiedAt, pinClock ?? .distantPast) }
    }

    /// Merges what the other Macs published into the local history.
    ///
    /// The latest action on a key wins: a deletion removes the entry when it
    /// happened after its last copy and pin change anywhere, and a copy made
    /// after the deletion brings it back. A re-copy moves the entry up, and a
    /// pin change made later than this Mac's own replaces it. Dates from other
    /// Macs are capped at `now`, so a Mac with its clock far ahead cannot keep
    /// an entry on top, or a deletion in force, for ever. Entries this Mac
    /// does not sync, and `protectedIDs` (an entry open in the editor), are
    /// left as they are. `imageFile` names the local file for an image this
    /// Mac does not have yet; the service passes `pendingImageFile` first and
    /// fetches only what survives the local limits.
    static func merge(local: [ClipboardHistoryEntry],
                      remotes: [ClipboardHistorySyncDevice],
                      tombstones own: [String: Date],
                      pinChanges: [String: Date],
                      policy: ClipboardHistorySyncPolicy,
                      protectedIDs: Set<UUID> = [],
                      now: Date = Date(),
                      imageFile: (String) -> String?) -> Merge {
        func capped(_ date: Date) -> Date { min(date, now) }
        var tombstones = own.mapValues(capped)
        var best: [String: Remote] = [:]
        for mac in remotes {
            for (key, date) in mac.deleted {
                tombstones[key] = max(tombstones[key] ?? .distantPast, capped(date))
            }
            for record in mac.records where allows(record, policy: policy) {
                let copiedAt = capped(record.copiedAt)
                let pinnedAt = record.pinnedAt.map(capped)
                let pinClock = (record.pinChangedAt ?? record.pinnedAt).map(capped)
                guard var remote = best[record.key] else {
                    best[record.key] = Remote(record: record, copiedAt: copiedAt,
                                              pinnedAt: pinnedAt, pinClock: pinClock)
                    continue
                }
                if copiedAt > remote.copiedAt {
                    remote.record = record
                    remote.copiedAt = copiedAt
                }
                if let pinClock, pinClock > (remote.pinClock ?? .distantPast)
                    || (pinClock == remote.pinClock && pinnedAt != nil) {
                    remote.pinnedAt = pinnedAt
                    remote.pinClock = pinClock
                }
                best[record.key] = remote
            }
        }

        var clocks = pinChanges
        var seen: Set<String> = []
        var pinned: [ClipboardHistoryEntry] = []
        var recent: [ClipboardHistoryEntry] = []
        var newlyPinned: [(key: String, entry: ClipboardHistoryEntry)] = []
        var movedRecent: [(key: String, entry: ClipboardHistoryEntry)] = []

        for entry in local {
            // An entry this Mac keeps to itself still holds its content's
            // place, so the same content from elsewhere never doubles it.
            let key = key(for: entry)
            let first = key.map { seen.insert($0).inserted } ?? false
            guard let key, first, allows(entry, policy: policy), !protectedIDs.contains(entry.id) else {
                if entry.isPinned { pinned.append(entry) } else { recent.append(entry) }
                continue
            }
            let localClock = clocks[key] ?? entry.pinnedAt
            let remote = best[key]
            let activity = max(entry.copiedAt, localClock ?? .distantPast, remote?.activity ?? .distantPast)
            if let deletedAt = tombstones[key], deletedAt >= activity { continue }
            var updated = entry
            if let remote {
                if remote.copiedAt > entry.copiedAt { updated.copiedAt = remote.copiedAt }
                if let remoteClock = remote.pinClock, remoteClock > (localClock ?? .distantPast) {
                    updated.pinnedAt = remote.pinnedAt
                    clocks[key] = remoteClock
                }
            }
            if updated.isPinned {
                if entry.isPinned { pinned.append(updated) } else { newlyPinned.append((key, updated)) }
            } else if entry.isPinned || updated.copiedAt != entry.copiedAt {
                movedRecent.append((key, updated))
            } else {
                recent.append(updated)
            }
        }

        for (key, remote) in best where !seen.contains(key) {
            if let deletedAt = tombstones[key], deletedAt >= remote.activity { continue }
            let record = remote.record
            var entry: ClipboardHistoryEntry
            switch record.kind {
            case .text:
                entry = ClipboardHistoryEntry(text: record.text, copiedAt: remote.copiedAt, pinnedAt: remote.pinnedAt)
            case .image:
                guard let hash = imageHash(fromKey: key), let name = imageFile(hash) else { continue }
                entry = ClipboardHistoryEntry(text: "", copiedAt: remote.copiedAt, pinnedAt: remote.pinnedAt,
                                              kind: .image, imageFile: name, imageHash: hash,
                                              imageWidth: record.imageWidth, imageHeight: record.imageHeight)
            case .files:
                continue
            }
            entry.sourceBundleID = record.source
            if let clock = remote.pinClock { clocks[key] = max(clocks[key] ?? .distantPast, clock) }
            if entry.isPinned { newlyPinned.append((key, entry)) } else { movedRecent.append((key, entry)) }
        }

        // The key breaks ties, so every Mac settles on the same order.
        func newer(_ lhs: Date, _ rhs: Date, _ lhsKey: String, _ rhsKey: String) -> Bool {
            lhs == rhs ? lhsKey < rhsKey : lhs > rhs
        }
        // A pin made elsewhere lands on top, as it does on the Mac that made it.
        newlyPinned.sort {
            newer($0.entry.pinnedAt ?? .distantPast, $1.entry.pinnedAt ?? .distantPast, $0.key, $1.key)
        }
        // Copies from elsewhere slot in by when they were copied, which keeps
        // the local order, hand-made moves included, for everything else.
        for (_, entry) in movedRecent.sorted(by: { newer($0.entry.copiedAt, $1.entry.copiedAt, $0.key, $1.key) }) {
            let index = recent.firstIndex { $0.copiedAt < entry.copiedAt } ?? recent.endIndex
            recent.insert(entry, at: index)
        }
        let entries = newlyPinned.map(\.entry) + pinned + recent
        let keys = Set(entries.compactMap { key(for: $0) })
        return Merge(entries: entries,
                     tombstones: prunedTombstones(tombstones, now: now),
                     pinChanges: prunedPinChanges(clocks, keeping: keys, now: now))
    }

    /// Swaps the stand-in for each fetched image's stored file name and drops
    /// the images that could not be fetched yet; the next merge asks again.
    static func resolvingImages(_ entries: [ClipboardHistoryEntry],
                                stored: [String: String]) -> [ClipboardHistoryEntry] {
        entries.compactMap { entry in
            guard entry.kind == .image, entry.imageFile == pendingImageFile else { return entry }
            guard let hash = entry.imageHash, let name = stored[hash] else { return nil }
            var resolved = ClipboardHistoryEntry(id: entry.id, text: "", copiedAt: entry.copiedAt,
                                                 pinnedAt: entry.pinnedAt, kind: .image, imageFile: name,
                                                 imageHash: hash, imageWidth: entry.imageWidth,
                                                 imageHeight: entry.imageHeight)
            resolved.sourceBundleID = entry.sourceBundleID
            return resolved
        }
    }

    /// Hashes of the images the merged history still waits for.
    static func pendingImageHashes(_ entries: [ClipboardHistoryEntry]) -> [String] {
        entries.compactMap { $0.kind == .image && $0.imageFile == pendingImageFile ? $0.imageHash : nil }
    }
}
