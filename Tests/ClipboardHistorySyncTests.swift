// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CloudKit
import Foundation

/// iCloud sync of the clipboard history, played out between simulated Macs:
/// each one a history, a pin clock, a set of deletions and a device id, all of
/// them reading and writing CloudKit records, built and read by the
/// production code, in one shared zone held in memory.
enum ClipboardHistorySyncTests {
    static let textOnly = ClipboardHistorySyncPolicy(includesImages: false, skipsSensitiveText: false,
                                                     ignoredApps: [])
    static let withImages = ClipboardHistorySyncPolicy(includesImages: true, skipsSensitiveText: false,
                                                       ignoredApps: [])

    /// The private database zone, as the change feed would hand it to each
    /// Mac: every record by name.
    final class Zone {
        var records: [String: CKRecord] = [:]
        let files: URL

        init(files: URL) { self.files = files }

        var entries: [String: (device: String, record: ClipboardHistorySyncRecord)] {
            records.compactMapValues { ClipboardHistoryCloudRecords.syncRecord(from: $0) }
        }

        var states: [String: ClipboardHistoryCloudRecords.DeviceState] {
            Dictionary(records.values.compactMap { ClipboardHistoryCloudRecords.deviceState(from: $0) },
                       uniquingKeysWith: { first, _ in first })
        }

        /// The picture an entry record carries, the way CloudKit hands it
        /// back: a file to read.
        func image(_ hash: String) -> Data? {
            guard let record = records.values.first(where: {
                ClipboardHistoryCloudRecords.syncRecord(from: $0)?.record.key == "i:" + hash
            }), let url = (record[ClipboardHistoryCloudRecords.imageField] as? CKAsset)?.fileURL,
                  let data = try? Data(contentsOf: url), ClipboardHistorySync.sha256Hex(data) == hash
            else { return nil }
            return data
        }
    }

    /// One Mac: what its history holds and what it remembers for sync. It
    /// publishes and merges through the production functions.
    final class Mac {
        let device: String
        var entries: [ClipboardHistoryEntry] = []
        var deleted: [String: Date] = [:]
        var pinChanges: [String: Date] = [:]
        var policy: ClipboardHistorySyncPolicy
        let zone: Zone
        /// The image store of this Mac: stored name to bytes.
        var images: [String: Data] = [:]

        init(_ name: String, zone: Zone, policy: ClipboardHistorySyncPolicy = textOnly) {
            device = ClipboardHistorySync.deviceIdentifier(hardware: name, user: "tester", bundle: "com.example")
            self.zone = zone
            self.policy = policy
        }

        func copy(_ text: String, at date: Date, source: String? = nil) {
            entries.removeAll { $0.kind == .text && $0.text == text }
            var entry = ClipboardHistoryEntry(text: text, copiedAt: date)
            entry.sourceBundleID = source
            let firstRecent = entries.firstIndex { !$0.isPinned } ?? entries.endIndex
            entries.insert(entry, at: firstRecent)
        }

        func copyImage(_ data: Data, at date: Date) {
            let name = UUID().uuidString + ".png"
            images[name] = data
            let entry = ClipboardHistoryEntry(text: "", copiedAt: date, kind: .image, imageFile: name,
                                              imageHash: ClipboardHistorySync.sha256Hex(data),
                                              imageWidth: 2, imageHeight: 1)
            let firstRecent = entries.firstIndex { !$0.isPinned } ?? entries.endIndex
            entries.insert(entry, at: firstRecent)
        }

        func delete(_ text: String, at date: Date) {
            let removed = entries.filter { $0.text == text }
            entries.removeAll { $0.text == text }
            for key in ClipboardHistorySync.deletedKeys(for: removed, policy: policy) { deleted[key] = date }
        }

        func pin(_ text: String, _ pinned: Bool, at date: Date) {
            guard let index = entries.firstIndex(where: { $0.text == text }) else { return }
            var entry = entries.remove(at: index)
            entry.pinnedAt = pinned ? date : nil
            if !pinned { entry.copiedAt = date }
            entries.insert(entry, at: pinned ? 0 : (entries.firstIndex { !$0.isPinned } ?? entries.endIndex))
            if let key = ClipboardHistorySync.key(for: entry) { pinChanges[key] = date }
        }

        /// What the service sends: its own record, then the plan.
        @discardableResult
        func publish(at now: Date) -> ClipboardHistoryCloudRecords.Plan {
            let records = ClipboardHistorySync.records(for: entries, policy: policy, pinChanges: pinChanges) {
                entry in entry.imageFile.flatMap { self.images[$0]?.count }
            }
            let published = zone.entries.filter { $0.value.device == device }
                .map { (recordName: $0.key, record: $0.value.record) }
            let plan = ClipboardHistoryCloudRecords.plan(desired: records, published: published) {
                ClipboardHistoryCloudRecords.newEntryRecordName(device: device)
            }
            let state = ClipboardHistoryCloudRecords.DeviceState(deleted: deleted, seenAt: now)
            if let record = ClipboardHistoryCloudRecords.deviceRecord(device: device, state: state) {
                zone.records[record.recordID.recordName] = record
            }
            for item in plan.save {
                var file: URL?
                if let hash = ClipboardHistorySync.imageHash(fromKey: item.record.key),
                   let data = entries.first(where: { $0.imageHash == hash })?.imageFile.flatMap({ images[$0] }) {
                    let url = zone.files.appendingPathComponent(UUID().uuidString + ".png")
                    try? data.write(to: url)
                    file = url
                }
                zone.records[item.recordName] = ClipboardHistoryCloudRecords.entryRecord(item.record,
                                                                                         recordName: item.recordName,
                                                                                         image: file)
            }
            for name in plan.delete { zone.records[name] = nil }
            return plan
        }

        /// What the service does: merge with stand-ins, trim, fetch the
        /// pictures that survive, store them, resolve.
        func pull(now: Date, limit: Int = 50) {
            let remotes = ClipboardHistoryCloudRecords.devices(entries: zone.entries, states: zone.states,
                                                               excluding: device, now: now)
            let merge = ClipboardHistorySync.merge(local: entries, remotes: remotes, tombstones: deleted,
                                                   pinChanges: pinChanges, policy: policy, now: now) { _ in
                ClipboardHistorySync.pendingImageFile
            }
            let trimmed = ClipboardHistoryEditing.retainedEntries(merge.entries, recentLimit: limit, now: now)
            var stored: [String: String] = [:]
            for hash in ClipboardHistorySync.pendingImageHashes(trimmed) {
                guard let data = zone.image(hash) else { continue }
                let name = UUID().uuidString + ".png"
                images[name] = data
                stored[hash] = name
            }
            entries = ClipboardHistoryEditing.retainedEntries(
                ClipboardHistorySync.resolvingImages(merge.entries, stored: stored), recentLimit: limit, now: now)
            deleted = ClipboardHistorySync.latest(deleted, merge.tombstones)
            pinChanges = ClipboardHistorySync.latest(pinChanges, merge.pinChanges)
        }

        var texts: [String] { entries.map { $0.kind == .text ? $0.text : "image:" + ($0.imageHash ?? "") } }
    }

    static func run(_ suite: TestSuite) {
        suite.run("clipboard sync") {
            keysAndGate(suite)
            publishing(suite)
            reading(suite)
            merging(suite)
            twoMacs(suite)
            cloudRecords(suite)
            statusDisplay(suite)
            strings(suite)
        }
    }

    private static func temporaryZone() -> (Zone, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-clipboard-sync-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return (Zone(files: base), base)
    }

    private static func keysAndGate(_ suite: TestSuite) {
        let text = ClipboardHistoryEntry(text: "Hello")
        suite.expect(ClipboardHistorySync.key(for: text) == ClipboardHistorySync.textKey("Hello")
                     && ClipboardHistorySync.key(for: ClipboardHistoryEntry(text: "Hello", copiedAt: .distantPast))
                     == ClipboardHistorySync.key(for: text),
                     "the same text has the same key on every Mac, whenever it was copied")
        suite.expect(ClipboardHistorySync.key(for: ClipboardHistoryEntry(text: "Hello ")) != ClipboardHistorySync.key(for: text),
                     "different text has a different key")
        let hash = ClipboardHistorySync.sha256Hex(Data([1, 2, 3]))
        let image = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "a.png", imageHash: hash)
        suite.expect(ClipboardHistorySync.key(for: image) == "i:" + hash
                     && ClipboardHistorySync.imageHash(fromKey: "i:" + hash) == hash,
                     "an image is keyed by the hash of its bytes, which is also its file name")
        let files = ClipboardHistoryEntry(text: "", kind: .files, filePaths: ["/Users/me/report.pdf"])
        suite.expect(ClipboardHistorySync.key(for: files) == nil
                     && !ClipboardHistorySync.allows(files, policy: withImages),
                     "copied files never sync: a path only means something on one Mac")
        suite.expect(ClipboardHistorySync.key(for: ClipboardHistoryEntry(text: "", kind: .image, imageFile: "a.png",
                                                                         imageHash: "../../etc"))
                     == nil && ClipboardHistorySync.imageHash(fromKey: "i:../x") == nil,
                     "a hash that is not one never becomes a key or a file name")
        suite.expect(!ClipboardHistorySync.allows(image, policy: textOnly)
                     && ClipboardHistorySync.allows(image, policy: withImages),
                     "images sync only when the user chose text and images")
        let secret = ClipboardHistoryEntry(text: "export API_KEY=abc123")
        let strict = ClipboardHistorySyncPolicy(includesImages: false, skipsSensitiveText: true, ignoredApps: [])
        suite.expect(!ClipboardHistorySync.allows(secret, policy: strict)
                     && ClipboardHistorySync.allows(secret, policy: textOnly),
                     "the sensitive text filter also keeps entries saved before it was on from syncing")
        var fromIgnored = ClipboardHistoryEntry(text: "From the password app")
        fromIgnored.sourceBundleID = "com.example.vault"
        let ignoring = ClipboardHistorySyncPolicy(includesImages: false, skipsSensitiveText: false,
                                                  ignoredApps: ["com.example.vault"])
        suite.expect(!ClipboardHistorySync.allows(fromIgnored, policy: ignoring),
                     "an entry from an app added to the ignore list later stays on this Mac")
        suite.expect(ClipboardHistorySync.deletedKeys(for: [secret, text, files], policy: strict)
                     == [ClipboardHistorySync.textKey("Hello")],
                     "deleting something that never synced publishes not even its hash")
        let a = ClipboardHistorySync.deviceIdentifier(hardware: "HW-1", user: "me", bundle: "com.vorssaint.utils")
        suite.expect(a == ClipboardHistorySync.deviceIdentifier(hardware: "HW-1", user: "me", bundle: "com.vorssaint.utils")
                     && a != ClipboardHistorySync.deviceIdentifier(hardware: "HW-2", user: "me", bundle: "com.vorssaint.utils")
                     && a != ClipboardHistorySync.deviceIdentifier(hardware: "HW-1", user: "me",
                                                                   bundle: "com.vorssaint.utils.developer")
                     && ClipboardHistorySync.isValidDevice(a) && !a.contains("HW"),
                     "each Mac, account and app build writes its own file, named without revealing the Mac")
    }

    private static func publishing(_ suite: TestSuite) {
        let now = Date()
        var pinned = ClipboardHistoryEntry(text: "Pinned", copiedAt: now.addingTimeInterval(-50))
        pinned.pinnedAt = now.addingTimeInterval(-40)
        let recent = ClipboardHistoryEntry(text: "Recent", copiedAt: now)
        let huge = ClipboardHistoryEntry(text: String(repeating: "x", count: ClipboardHistorySync.maxTextBytes + 1))
        let blank = ClipboardHistoryEntry(text: "   ")
        let small = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "small.png",
                                          imageHash: ClipboardHistorySync.sha256Hex(Data([1])))
        let big = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "big.png",
                                        imageHash: ClipboardHistorySync.sha256Hex(Data([2])))
        let gone = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "gone.png",
                                         imageHash: ClipboardHistorySync.sha256Hex(Data([3])))
        let sizes = ["small.png": 10, "big.png": ClipboardHistorySync.maxImageBytes + 1]
        let records = ClipboardHistorySync.records(for: [recent, pinned, huge, blank, small, big, gone],
                                                   policy: withImages,
                                                   pinChanges: [ClipboardHistorySync.textKey("Pinned"): now]) {
            $0.imageFile.flatMap { sizes[$0] }
        }
        suite.expect(records.map(\.key) == [ClipboardHistorySync.textKey("Pinned"), ClipboardHistorySync.textKey("Recent"),
                                            "i:" + small.imageHash!],
                     "pinned entries go first, and text or pictures too large to sync, or gone, stay here")
        suite.expect(records[0].pinnedAt == pinned.pinnedAt && records[0].pinChangedAt == now
                     && records[1].pinChangedAt == nil && records[2].text.isEmpty,
                     "a record carries its pin and when the pin last changed")
        let many = (0..<(ClipboardHistorySync.maxRecords + 20)).map { ClipboardHistoryEntry(text: "Item \($0)") }
        let capped = ClipboardHistorySync.records(for: many, policy: textOnly, pinChanges: [:]) { _ in nil }
        suite.expect(capped.count == ClipboardHistorySync.maxRecords && capped.first?.text == "Item 0",
                     "an unlimited history publishes only its newest entries")
        let pictures = (0..<(ClipboardHistorySync.maxImages + 5)).map { index in
            ClipboardHistoryEntry(text: "", kind: .image, imageFile: "\(index).png",
                                  imageHash: ClipboardHistorySync.sha256Hex(Data("\(index)".utf8)))
        }
        suite.expect(ClipboardHistorySync.records(for: pictures, policy: withImages, pinChanges: [:]) { _ in 100 }.count
                     == ClipboardHistorySync.maxImages,
                     "the number of synced pictures is bounded")
    }

    private static func reading(_ suite: TestSuite) {
        let device = ClipboardHistorySync.deviceIdentifier(hardware: "A", user: "u", bundle: "b")
        let good = ClipboardHistorySyncRecord(key: ClipboardHistorySync.textKey("Fine"), kind: .text, text: "Fine",
                                              copiedAt: Date().addingTimeInterval(-0.123_456_789),
                                              pinnedAt: Date().addingTimeInterval(-1_234.567_891_234),
                                              pinChangedAt: nil, source: "com.apple.Safari",
                                              imageWidth: nil, imageHeight: nil)
        let name = ClipboardHistoryCloudRecords.newEntryRecordName(device: device)
        let record = ClipboardHistoryCloudRecords.entryRecord(good, recordName: name)
        let back = ClipboardHistoryCloudRecords.syncRecord(from: record)
        suite.expect(back?.device == device && back?.record == good,
                     "an entry reads back exactly, its times to the last digit, so nothing is sent again for no change")
        suite.expect(record.recordType == ClipboardHistoryCloudRecords.entryType
                     && record.recordID.zoneID == ClipboardHistoryCloudRecords.zoneID
                     && name.hasPrefix(device + "-") && !name.contains(String(good.key.dropFirst(2)).prefix(16)),
                     "an entry record is named after its Mac and a random part, never its content")
        suite.expect(Set(record.allKeys()) == Set(record.encryptedValues.allKeys())
                     && record["text"] == nil && record["key"] == nil && record["source"] == nil,
                     "every value of an entry is an encrypted field, so the server sees no text and no hash")
        let picture = ClipboardHistorySyncRecord(key: "i:" + ClipboardHistorySync.sha256Hex(Data([1])), kind: .image,
                                                 text: "", copiedAt: Date(timeIntervalSince1970: 5), pinnedAt: nil,
                                                 pinChangedAt: nil, source: nil, imageWidth: 30, imageHeight: 20)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sync-test-\(UUID().uuidString).png")
        try? Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let pictureRecord = ClipboardHistoryCloudRecords.entryRecord(picture, recordName: name, image: file)
        suite.expect(ClipboardHistoryCloudRecords.syncRecord(from: pictureRecord)?.record == picture
                     && (pictureRecord[ClipboardHistoryCloudRecords.imageField] as? CKAsset)?.fileURL == file
                     && Set(pictureRecord.allKeys()).subtracting(pictureRecord.encryptedValues.allKeys())
                     == [ClipboardHistoryCloudRecords.imageField],
                     "a picture travels as the one field that is not encrypted, an asset")

        func edited(_ change: (CKRecord) -> Void, recordName: String = name) -> CKRecord {
            let copy = ClipboardHistoryCloudRecords.entryRecord(good, recordName: recordName)
            change(copy)
            return copy
        }
        suite.expect(ClipboardHistoryCloudRecords.syncRecord(from: edited { $0.encryptedValues["text"] = "Changed" }) == nil,
                     "an entry whose text does not match its key is dropped")
        suite.expect(ClipboardHistoryCloudRecords.syncRecord(from: edited { $0.encryptedValues["kind"] = "rich" }) == nil
                     && ClipboardHistoryCloudRecords.syncRecord(from: edited { $0.encryptedValues["kind"] = "files" }) == nil,
                     "a kind this version does not know, or copied files, is never taken")
        suite.expect(ClipboardHistoryCloudRecords.syncRecord(from: edited({ _ in }, recordName: "device-" + device)) == nil
                     && ClipboardHistoryCloudRecords.syncRecord(from: edited({ _ in }, recordName: "nobody")) == nil,
                     "an entry not named after a Mac is not read")
        suite.expect(ClipboardHistoryCloudRecords.syncRecord(from: edited { $0.encryptedValues["copiedAt"] = Double.nan }) == nil,
                     "an entry with an impossible time is not read")

        let deleted = [ClipboardHistorySync.textKey("Old"): Date().addingTimeInterval(-900.123_456_789)]
        let state = ClipboardHistoryCloudRecords.DeviceState(deleted: deleted, seenAt: Date())
        let deviceRecord = ClipboardHistoryCloudRecords.deviceRecord(device: device, state: state)!
        let readState = ClipboardHistoryCloudRecords.deviceState(from: deviceRecord)
        suite.expect(readState?.device == device && readState?.state == state
                     && deviceRecord["deleted"] == nil && deviceRecord["seenAt"] == nil,
                     "a Mac's deletions read back exactly, and encrypted")
        let messy = Data("{\"t:not-a-hash\":1,\"\(ClipboardHistorySync.textKey("x"))\":2}".utf8)
        suite.expect(ClipboardHistorySync.decodedDeleted(messy) == [ClipboardHistorySync.textKey("x"): Date(timeIntervalSinceReferenceDate: 2)]
                     && ClipboardHistorySync.decodedDeleted(Data("nonsense".utf8)).isEmpty
                     && ClipboardHistorySync.decodedDeleted(Data(count: ClipboardHistorySync.maxDeletedBytes + 1)).isEmpty,
                     "deletions that do not look like ours are dropped")
        var many: [String: Date] = [:]
        for index in 0..<ClipboardHistorySync.maxTombstones {
            many[ClipboardHistorySync.textKey("\(index)")] = Date(timeIntervalSince1970: 1_700_000_000.123_456 + Double(index))
        }
        suite.expect((ClipboardHistorySync.encodedDeleted(many)?.count ?? .max) <= ClipboardHistorySync.maxDeletedBytes,
                     "every remembered deletion fits one record")

        let now = Date()
        suite.expect(ClipboardHistorySync.isStale(seen: now.addingTimeInterval(-ClipboardHistorySync.tombstoneLifetime - 1),
                                                  now: now)
                     && !ClipboardHistorySync.isStale(seen: now.addingTimeInterval(-86_400), now: now),
                     "a Mac silent for longer than deletions are remembered no longer counts")
        var tombstones: [String: Date] = [:]
        for index in 0..<(ClipboardHistorySync.maxTombstones + 10) {
            tombstones[ClipboardHistorySync.textKey("\(index)")] = now.addingTimeInterval(-Double(index))
        }
        tombstones[ClipboardHistorySync.textKey("ancient")] = now.addingTimeInterval(-ClipboardHistorySync.tombstoneLifetime - 5)
        tombstones["t:not-a-hash"] = now
        let pruned = ClipboardHistorySync.prunedTombstones(tombstones, now: now)
        suite.expect(pruned.count == ClipboardHistorySync.maxTombstones
                     && pruned[ClipboardHistorySync.textKey("0")] != nil
                     && pruned[ClipboardHistorySync.textKey("ancient")] == nil && pruned["t:not-a-hash"] == nil,
                     "deletions are remembered for a bounded time and number, newest first")
    }

    private static func merging(_ suite: TestSuite) {
        let now = Date()
        let device = ClipboardHistorySync.deviceIdentifier(hardware: "remote", user: "u", bundle: "b")
        func record(_ text: String, _ copiedAt: Date, pinnedAt: Date? = nil, pinChangedAt: Date? = nil,
                    source: String? = nil) -> ClipboardHistorySyncRecord {
            ClipboardHistorySyncRecord(key: ClipboardHistorySync.textKey(text), kind: .text, text: text,
                                       copiedAt: copiedAt, pinnedAt: pinnedAt, pinChangedAt: pinChangedAt,
                                       source: source, imageWidth: nil, imageHeight: nil)
        }
        func merge(_ local: [ClipboardHistoryEntry], _ records: [ClipboardHistorySyncRecord],
                   deleted: [String: Date] = [:], own: [String: Date] = [:], pins: [String: Date] = [:],
                   policy: ClipboardHistorySyncPolicy = textOnly, protected: Set<UUID> = [])
            -> ClipboardHistorySync.Merge {
            ClipboardHistorySync.merge(local: local,
                                       remotes: [ClipboardHistorySyncDevice(device: device, records: records,
                                                                            deleted: deleted)],
                                       tombstones: own, pinChanges: pins, policy: policy,
                                       protectedIDs: protected, now: now) { _ in ClipboardHistorySync.pendingImageFile }
        }
        let older = ClipboardHistoryEntry(text: "Older", copiedAt: now.addingTimeInterval(-300))
        let newer = ClipboardHistoryEntry(text: "Newer", copiedAt: now.addingTimeInterval(-100))
        let arrived = merge([newer, older], [record("Middle", now.addingTimeInterval(-200), source: "com.apple.Notes")])
        suite.expect(arrived.entries.map(\.text) == ["Newer", "Middle", "Older"],
                     "a copy from elsewhere slots in by its copy time, found \(arrived.entries.map(\.text))")
        suite.expect(arrived.entries[1].sourceBundleID == "com.apple.Notes"
                     && arrived.entries[1].copiedAt == now.addingTimeInterval(-200),
                     "it keeps the app and the time it was copied")
        // A manual move put the older entry first; that order stays.
        let moved = merge([older, newer], [record("Fresh", now.addingTimeInterval(-50))])
        suite.expect(moved.entries.map(\.text) == ["Fresh", "Older", "Newer"],
                     "the order the user gave the other entries by hand stays, found \(moved.entries.map(\.text))")
        let recopied = merge([newer, older], [record("Older", now.addingTimeInterval(-10))])
        suite.expect(recopied.entries.map(\.text) == ["Older", "Newer"] && recopied.entries[0].id == older.id,
                     "copying the same text on another Mac moves the existing entry up instead of adding one")
        let stale = merge([newer, older], [record("Older", now.addingTimeInterval(-1_000))])
        suite.expect(stale.entries == [newer, older], "an older copy elsewhere changes nothing")

        let deletedAfter = merge([newer, older], [], deleted: [ClipboardHistorySync.textKey("Older"): now.addingTimeInterval(-50)])
        suite.expect(deletedAfter.entries.map(\.text) == ["Newer"],
                     "a deletion made after the last copy removes the entry")
        let copiedAfter = merge([newer], [record("Older", now.addingTimeInterval(-20))],
                                own: [ClipboardHistorySync.textKey("Older"): now.addingTimeInterval(-50)])
        suite.expect(copiedAfter.entries.map(\.text) == ["Older", "Newer"],
                     "copying it again after the deletion brings it back")
        let deletedBefore = merge([newer], [record("Older", now.addingTimeInterval(-300))],
                                  own: [ClipboardHistorySync.textKey("Older"): now.addingTimeInterval(-50)])
        suite.expect(deletedBefore.entries.map(\.text) == ["Newer"],
                     "a Mac that still holds a deleted entry cannot bring it back")
        suite.expect(deletedAfter.tombstones[ClipboardHistorySync.textKey("Older")] != nil,
                     "deletions from other Macs are passed on, so they outlive the Mac that made them")

        let farFuture = now.addingTimeInterval(365 * 86_400)
        let skewed = merge([], [record("Skewed", farFuture)])
        suite.expect(skewed.entries.first?.copiedAt == now,
                     "a Mac with its clock far ahead cannot pin an entry to the top for ever")
        let deletedFromFuture = merge([newer], [], deleted: [ClipboardHistorySync.textKey("Newer"): farFuture])
        suite.expect(deletedFromFuture.tombstones[ClipboardHistorySync.textKey("Newer")] == now
                     && deletedFromFuture.entries.isEmpty,
                     "nor keep a deletion in force past any later copy")

        let pinnedElsewhere = merge([newer, older], [record("Older", older.copiedAt, pinnedAt: now.addingTimeInterval(-5),
                                                            pinChangedAt: now.addingTimeInterval(-5))])
        suite.expect(pinnedElsewhere.entries.map(\.text) == ["Older", "Newer"]
                     && pinnedElsewhere.entries[0].isPinned
                     && pinnedElsewhere.pinChanges[ClipboardHistorySync.textKey("Older")] == now.addingTimeInterval(-5),
                     "a pin made on another Mac pins the entry here, on top")
        var pinnedHere = older
        pinnedHere.pinnedAt = now.addingTimeInterval(-60)
        let unpinnedLater = merge([pinnedHere, newer], [record("Older", now.addingTimeInterval(-4), pinnedAt: nil,
                                                               pinChangedAt: now.addingTimeInterval(-4))],
                                  pins: [ClipboardHistorySync.textKey("Older"): now.addingTimeInterval(-60)])
        suite.expect(unpinnedLater.entries.map(\.text) == ["Older", "Newer"] && !unpinnedLater.entries[0].isPinned,
                     "a later unpin elsewhere unpins it here, as the newest recent entry")
        let unpinnedEarlier = merge([pinnedHere, newer], [record("Older", older.copiedAt, pinnedAt: nil,
                                                                 pinChangedAt: now.addingTimeInterval(-90))],
                                    pins: [ClipboardHistorySync.textKey("Older"): now.addingTimeInterval(-60)])
        suite.expect(unpinnedEarlier.entries[0].isPinned, "an older unpin loses to a newer pin")
        let untouched = merge([newer, older], [record("Older", older.copiedAt)])
        suite.expect(untouched.entries == [newer, older], "nobody changed the pin, so each Mac keeps its own")
        let pinnedAfterClear = merge([], [record("Kept", now.addingTimeInterval(-100), pinnedAt: now.addingTimeInterval(-5),
                                                 pinChangedAt: now.addingTimeInterval(-5))],
                                     own: [ClipboardHistorySync.textKey("Kept"): now.addingTimeInterval(-30)])
        suite.expect(pinnedAfterClear.entries.map(\.text) == ["Kept"],
                     "an entry pinned elsewhere after this Mac cleared it is kept")

        let strict = ClipboardHistorySyncPolicy(includesImages: false, skipsSensitiveText: true,
                                                ignoredApps: ["com.example.vault"])
        let filtered = merge([], [record("password=hunter2", now), record("From vault", now, source: "com.example.vault"),
                                  record("Plain", now)], policy: strict)
        suite.expect(filtered.entries.map(\.text) == ["Plain"],
                     "what this Mac's history would skip is not taken from another Mac either")
        var keptHere = ClipboardHistoryEntry(text: "Same words", copiedAt: now.addingTimeInterval(-500))
        keptHere.sourceBundleID = "com.example.vault"
        let doubled = merge([keptHere], [record("Same words", now, source: "com.apple.Safari")], policy: strict)
        suite.expect(doubled.entries == [keptHere],
                     "an entry kept off sync still stands for its content, so the same text from elsewhere never doubles it")
        let imageRecord = ClipboardHistorySyncRecord(key: "i:" + ClipboardHistorySync.sha256Hex(Data([9])), kind: .image,
                                                     text: "", copiedAt: now, pinnedAt: nil, pinChangedAt: nil,
                                                     source: nil, imageWidth: 3, imageHeight: 4)
        suite.expect(merge([], [imageRecord]).entries.isEmpty, "a text only Mac does not take pictures")
        let pending = merge([], [imageRecord], policy: withImages)
        suite.expect(ClipboardHistorySync.pendingImageHashes(pending.entries) == [ClipboardHistorySync.sha256Hex(Data([9]))]
                     && pending.entries[0].imageWidth == 3,
                     "a picture this Mac lacks waits for its bytes")
        let resolved = ClipboardHistorySync.resolvingImages(pending.entries + [newer],
                                                            stored: [ClipboardHistorySync.sha256Hex(Data([9])): "stored.png"])
        suite.expect(resolved.map(\.imageFile) == ["stored.png", nil] && resolved[0].id == pending.entries[0].id,
                     "a fetched picture takes its stored file name")
        suite.expect(ClipboardHistorySync.resolvingImages(pending.entries + [newer], stored: [:]) == [newer],
                     "a picture still on its way is left out until the next look")
        let localPicture = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "mine.png",
                                                 imageHash: ClipboardHistorySync.sha256Hex(Data([5])))
        let pictureDeleted = merge([localPicture], [], deleted: ["i:" + ClipboardHistorySync.sha256Hex(Data([5])): now])
        suite.expect(pictureDeleted.entries == [localPicture],
                     "a text only Mac keeps its own pictures when another Mac deletes them")
        let files = ClipboardHistoryEntry(text: "", kind: .files, filePaths: ["/tmp/a"])
        suite.expect(merge([files, newer], [], policy: withImages).entries == [files, newer],
                     "entries that never sync are left where they are")
        let editing = merge([newer], [], deleted: [ClipboardHistorySync.textKey("Newer"): now], protected: [newer.id])
        suite.expect(editing.entries == [newer], "an entry open in the editor is not taken away mid-edit")
        let tie = merge([], [record("b", now.addingTimeInterval(-1)), record("a", now.addingTimeInterval(-1))])
        let tieAgain = merge([], [record("a", now.addingTimeInterval(-1)), record("b", now.addingTimeInterval(-1))])
        suite.expect(tie.entries.map(\.text) == tieAgain.entries.map(\.text),
                     "entries copied at the same moment settle in the same order on every Mac")
    }

    /// Two Macs and a third that arrives later, sharing one zone.
    private static func twoMacs(_ suite: TestSuite) {
        let (zone, base) = temporaryZone()
        defer { try? FileManager.default.removeItem(at: base) }
        let start = Date().addingTimeInterval(-3_600)
        func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
        let a = Mac("MacBook", zone: zone, policy: withImages)
        let b = Mac("iMac", zone: zone, policy: withImages)

        a.copy("Meeting at 10", at: at(1), source: "com.apple.mail")
        a.copy("Shopping list", at: at(2))
        suite.expect(a.publish(at: at(2)).save.count == 2, "a Mac sends its entries")
        suite.expect(a.publish(at: at(2)) == ClipboardHistoryCloudRecords.Plan(save: [], delete: []),
                     "and nothing again when nothing changed")
        b.pull(now: at(3))
        suite.expect(b.texts == ["Shopping list", "Meeting at 10"],
                     "entries copied on one Mac show up on the other, found \(b.texts)")
        suite.expect(b.entries.last?.sourceBundleID == "com.apple.mail", "with the app they came from")

        b.copy("From the iMac", at: at(4))
        b.publish(at: at(4))
        a.pull(now: at(5))
        suite.expect(a.texts == ["From the iMac", "Shopping list", "Meeting at 10"],
                     "and the other way round, found \(a.texts)")
        a.publish(at: at(5))
        suite.expect(Set(zone.entries.values.map(\.device)) == [a.device, b.device]
                     && zone.entries.values.filter { $0.device == b.device }.count == 3,
                     "each Mac writes only records of its own")

        a.delete("Shopping list", at: at(6))
        let afterDelete = a.publish(at: at(6))
        suite.expect(afterDelete.save.isEmpty && afterDelete.delete.count == 1,
                     "a deletion takes the Mac's own record of the entry out of iCloud")
        b.pull(now: at(7))
        suite.expect(b.texts == ["From the iMac", "Meeting at 10"],
                     "deleting on one Mac deletes on the other, found \(b.texts)")
        b.publish(at: at(7))
        a.pull(now: at(8))
        suite.expect(a.texts == ["From the iMac", "Meeting at 10"],
                     "the other Mac's older copy does not bring it back")
        suite.expect(!zone.entries.values.contains { $0.record.key == ClipboardHistorySync.textKey("Shopping list") },
                     "once every Mac followed the deletion, the text is gone from iCloud")

        b.pin("Meeting at 10", true, at: at(9))
        b.publish(at: at(9))
        a.pull(now: at(10))
        suite.expect(a.entries.first?.text == "Meeting at 10" && a.entries.first?.isPinned == true,
                     "a pin made on one Mac pins on the other")
        for text in b.entries.filter({ !$0.isPinned }).map(\.text) { b.delete(text, at: at(11)) }
        b.publish(at: at(11))
        a.pull(now: at(12))
        suite.expect(a.texts == ["Meeting at 10"], "clearing history on one Mac clears it on the other, found \(a.texts)")

        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4])
        a.copyImage(png, at: at(13))
        a.publish(at: at(13))
        let hash = ClipboardHistorySync.sha256Hex(png)
        suite.expect(zone.image(hash) == png, "a picture travels with its entry")
        b.policy = textOnly
        b.pull(now: at(14))
        suite.expect(!b.texts.contains("image:" + hash), "a text only Mac leaves the picture out")
        b.policy = withImages
        b.pull(now: at(15))
        let picture = b.entries.first { $0.kind == .image }
        suite.expect(picture?.imageHash == hash && picture.flatMap { $0.imageFile.flatMap { b.images[$0] } } == png,
                     "a Mac syncing images stores the picture locally, found \(b.texts)")

        // A third Mac whose limit is smaller takes only what fits.
        let c = Mac("Mac mini", zone: zone)
        for index in 0..<5 { c.copy("Mini \(index)", at: at(16 + Double(index))) }
        c.publish(at: at(21))
        a.pull(now: at(30), limit: 3)
        suite.expect(a.entries.filter { !$0.isPinned }.count == 3,
                     "the local limit still applies to what arrives, found \(a.texts)")

        // C stops syncing: its records go, and the others keep what they got.
        for (name, entry) in zone.entries where entry.device == c.device { zone.records[name] = nil }
        zone.records[ClipboardHistoryCloudRecords.deviceRecordID(c.device).recordName] = nil
        a.pull(now: at(31), limit: 3)
        suite.expect(a.entries.filter { !$0.isPinned }.count == 3,
                     "a Mac that stops syncing leaves the others' histories alone")

        // A Mac silent for longer than deletions are remembered is ignored.
        let d = Mac("Old Mac", zone: zone)
        d.copy("From long ago", at: at(1))
        d.publish(at: at(1).addingTimeInterval(-ClipboardHistorySync.tombstoneLifetime - 10))
        a.pull(now: at(32), limit: 10)
        suite.expect(!a.texts.contains("From long ago"), "a Mac gone for months does not bring entries back")
    }

    private static func cloudRecords(_ suite: TestSuite) {
        let now = Date()
        func record(_ text: String, _ seconds: Double = 0) -> ClipboardHistorySyncRecord {
            ClipboardHistorySyncRecord(key: ClipboardHistorySync.textKey(text), kind: .text, text: text,
                                       copiedAt: now.addingTimeInterval(seconds), pinnedAt: nil, pinChangedAt: nil,
                                       source: nil, imageWidth: nil, imageHeight: nil)
        }
        var names = 0
        func newName() -> String {
            names += 1
            return "new\(names)"
        }
        let plan = ClipboardHistoryCloudRecords.plan(
            desired: [record("same"), record("changed", 5), record("new")],
            published: [(recordName: "r1", record: record("same")), (recordName: "r2", record: record("changed")),
                        (recordName: "r3", record: record("gone")), (recordName: "r4", record: record("same"))],
            newName: newName)
        suite.expect(plan.save.map(\.recordName) == ["r2", "new1"] && plan.save.map(\.record.text) == ["changed", "new"]
                     && plan.delete == ["r3", "r4"],
                     "only what changed is sent, under the name it already has, and a duplicate left by an interrupted write goes")

        let own = "aaaa", other = "bbbb", silent = "cccc", unknown = "dddd"
        let entries: [String: (device: String, record: ClipboardHistorySyncRecord)] = [
            "aaaa-1": (own, record("mine")), "bbbb-1": (other, record("theirs")),
            "cccc-1": (silent, record("old")), "dddd-1": (unknown, record("stray")),
        ]
        let states: [String: ClipboardHistoryCloudRecords.DeviceState] = [
            own: .init(deleted: [:], seenAt: now), other: .init(deleted: [:], seenAt: now),
            silent: .init(deleted: [:], seenAt: now.addingTimeInterval(-ClipboardHistorySync.tombstoneLifetime - 1)),
        ]
        let devices = ClipboardHistoryCloudRecords.devices(entries: entries, states: states, excluding: own, now: now)
        suite.expect(devices.map(\.device) == [other] && devices[0].records.map(\.text) == ["theirs"],
                     "the merge sees the other Macs that are known and recent, never this one")
        typealias Cost = ClipboardHistoryCloudRecords.WriteCost
        let small = Cost(bytes: 100, asset: false), picture = Cost(bytes: 0, asset: true)
        let megabyte = 1_024 * 1_024
        suite.expect(ClipboardHistoryCloudRecords.batchCount(Array(repeating: small, count: 150)) == 100
                     && ClipboardHistoryCloudRecords.batchCount([Cost(bytes: megabyte + megabyte / 2, asset: false),
                                                                 Cost(bytes: megabyte, asset: false)]) == 1
                     && ClipboardHistoryCloudRecords.batchCount([Cost(bytes: 3 * megabyte, asset: false), small]) == 1
                     && ClipboardHistoryCloudRecords.batchCount(Array(repeating: picture, count: 10)) == 8
                     && ClipboardHistoryCloudRecords.batchCount([]) == 0,
                     "writes go in requests bounded by count, size and pictures, never empty while work waits")
        suite.expect(ClipboardHistoryCloudRecords.device(ofEntryRecordName: "device-" + own) == nil
                     && ClipboardHistoryCloudRecords.device(ofDeviceRecordName: "device-" + own) == own
                     && ClipboardHistoryCloudRecords.device(ofEntryRecordName: own + "-x") == own,
                     "a Mac's own record and its entries are told apart by name")
    }

    /// The history window's status line, for every state sync can be in.
    private static func statusDisplay(_ suite: TestSuite) {
        let now = Date()
        let english = FeatureStrings.clipboardSync(.enUS)
        func shown(_ status: ClipboardHistorySyncStatus, syncing: Bool = false, at moment: Date = now,
                   language: AppLanguage = .enUS) -> ClipboardSyncStatusDisplay {
            ClipboardSyncStatusDisplay(status: status, syncing: syncing, now: moment, language: language)
        }
        suite.expect(!ClipboardSyncStatusDisplay.isShown(.off) && ClipboardSyncStatusDisplay.isShown(.checking)
                     && ClipboardSyncStatusDisplay.isShown(.synced(at: now, otherMacs: 0)),
                     "the window shows sync only while it is on")
        let fresh = shown(.synced(at: now.addingTimeInterval(-20), otherMacs: 2))
        suite.expect(fresh.text == "Synced just now · Other Macs: 2" && fresh.tone == .normal
                     && fresh.symbol == "checkmark.icloud",
                     "a sync under a minute old reads as just now, with the other Macs, found \(fresh.text)")
        suite.expect(shown(.synced(at: now.addingTimeInterval(30), otherMacs: 1)).text.hasPrefix("Synced just now"),
                     "a sync a changed clock puts ahead still reads as just now")
        let synced = Date(timeIntervalSince1970: 1_800_000_000)
        let twoMinutes = shown(.synced(at: synced, otherMacs: 1), at: synced.addingTimeInterval(125))
        let fiveMinutes = shown(.synced(at: synced, otherMacs: 1), at: synced.addingTimeInterval(305))
        suite.expect(twoMinutes.text.hasPrefix("Synced ") && !twoMinutes.text.hasPrefix("Synced just now")
                     && twoMinutes.text.contains("2") && twoMinutes.text.hasSuffix(" · Other Macs: 1")
                     && fiveMinutes.text.contains("5") && twoMinutes.text != fiveMinutes.text,
                     "an older sync says how long ago, and the line moves on while the window stays open, found \(twoMinutes.text) then \(fiveMinutes.text)")
        for status in [ClipboardHistorySyncStatus.checking, .noAccount, .unavailable, .storageFull,
                       .synced(at: now, otherMacs: 3)] {
            let busy = shown(status, syncing: true)
            suite.expect(busy.text == english.statusSyncing && busy.tone == .busy
                         && busy.symbol == "arrow.clockwise.icloud",
                         "while a round talks to iCloud the line says so, whatever came before (\(status))")
        }
        let checking = shown(.checking)
        let signedOut = shown(.noAccount)
        let unavailable = shown(.unavailable)
        let full = shown(.storageFull)
        suite.expect(checking.text == "Checking…" && checking.tone == .busy
                     && signedOut.text == "Not signed in to iCloud" && signedOut.tone == .warning
                     && signedOut.symbol == "icloud.slash"
                     && unavailable.text == "Can’t reach iCloud" && unavailable.tone == .warning
                     && full.text == "iCloud storage is full" && full.tone == .warning,
                     "each state has its own short line")
        suite.expect(fresh.help == english.statusHelp && signedOut.help.hasPrefix(english.noAccount)
                     && signedOut.help.hasSuffix(english.statusHelp) && full.help.hasPrefix(english.storageFull)
                     && unavailable.help.hasPrefix(english.unavailable),
                     "the tooltip says when it syncs, and what to do when it cannot")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.clipboardSync(language)
            let old = shown(.synced(at: synced, otherMacs: 4), at: synced.addingTimeInterval(3 * 3_600), language: language)
            suite.expect(old.text.contains("3") && old.text.contains("4")
                         && !old.text.contains("%") && old.text != strings.statusJustNow,
                         "the status line takes its time and count in \(language.rawValue), found \(old.text)")
        }
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.clipboardSync(language)
            let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
            suite.expect(values.count == 23 && values.allSatisfy { !$0.isEmpty },
                         "every sync string is translated (\(language.rawValue))")
            suite.expect(values.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") && !$0.contains("'") },
                         "sync strings use no long dashes and curly apostrophes (\(language.rawValue))")
            suite.expect(String(format: text.syncedFormat, "10:00").contains("10:00")
                         && String(format: text.otherMacsFormat, 2).contains("2"),
                         "the status formats take their values (\(language.rawValue))")
            suite.expect(text.caption.contains("iCloud") && text.privacyNote.contains("iCloud"),
                         "the captions say where the history goes (\(language.rawValue))")
        }
    }
}
