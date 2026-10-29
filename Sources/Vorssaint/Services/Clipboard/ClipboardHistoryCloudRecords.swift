// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CloudKit
import Foundation

/// How the clipboard history lives in the user's private CloudKit database:
/// one zone, one record per entry and Mac, and one record per Mac for the
/// deletions it knows of. Each Mac writes only records named after itself.
///
/// Every value but a picture's bytes is an encrypted field: CloudKit encrypts
/// it on the Mac, with keys from the user's iCloud Keychain, before it leaves.
/// Entry record names are random, so the server holds neither the text nor
/// even the hash it is matched by. Times are stored as the seconds a Date
/// itself holds, so a date comes back exactly as it was sent and no Mac sees
/// a change that is only rounding.
enum ClipboardHistoryCloudRecords {
    static let zoneID = CKRecordZone.ID(zoneName: "ClipboardHistory", ownerName: CKCurrentUserDefaultName)
    static let entryType = "ClipboardEntry"
    static let deviceType = "ClipboardDevice"
    static let imageField = "image"
    /// Everything a merge needs. A picture is fetched on its own, and only
    /// when this Mac keeps it.
    static let mergeFields = ["key", "kind", "text", "copiedAt", "pinnedAt", "pinChangedAt", "source",
                              "imageWidth", "imageHeight", "deleted", "seenAt"]
    /// A Mac's record is written again at least this often, so the others
    /// can tell it from one that left long ago.
    static let seenInterval: TimeInterval = 86_400

    // MARK: - Names

    static func newEntryRecordName(device: String) -> String {
        device + "-" + UUID().uuidString.lowercased()
    }

    /// The Mac an entry record belongs to, read from its name.
    static func device(ofEntryRecordName name: String) -> String? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        let device = String(name[..<dash])
        return ClipboardHistorySync.isValidDevice(device) ? device : nil
    }

    static func deviceRecordID(_ device: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "device-" + device, zoneID: zoneID)
    }

    static func device(ofDeviceRecordName name: String) -> String? {
        guard name.hasPrefix("device-") else { return nil }
        let device = String(name.dropFirst("device-".count))
        return ClipboardHistorySync.isValidDevice(device) ? device : nil
    }

    // MARK: - Entries

    static func entryRecord(_ record: ClipboardHistorySyncRecord, recordName: String,
                            image: URL? = nil) -> CKRecord {
        let ckRecord = CKRecord(recordType: entryType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
        let values = ckRecord.encryptedValues
        values["key"] = record.key
        values["kind"] = record.kind.rawValue
        values["text"] = record.text
        values["copiedAt"] = record.copiedAt.timeIntervalSinceReferenceDate
        values["pinnedAt"] = record.pinnedAt?.timeIntervalSinceReferenceDate
        values["pinChangedAt"] = record.pinChangedAt?.timeIntervalSinceReferenceDate
        values["source"] = record.source
        values["imageWidth"] = record.imageWidth
        values["imageHeight"] = record.imageHeight
        if let image { ckRecord[imageField] = CKAsset(fileURL: image) }
        return ckRecord
    }

    /// The entry a record holds and the Mac that wrote it, or nil when it is
    /// not one this version can trust.
    static func syncRecord(from ckRecord: CKRecord) -> (device: String, record: ClipboardHistorySyncRecord)? {
        guard ckRecord.recordType == entryType,
              let device = device(ofEntryRecordName: ckRecord.recordID.recordName) else { return nil }
        let values = ckRecord.encryptedValues
        func date(_ field: String) -> Date? {
            (values[field] as? Double).flatMap { $0.isFinite ? Date(timeIntervalSinceReferenceDate: $0) : nil }
        }
        guard let key = values["key"] as? String,
              let kind = (values["kind"] as? String).flatMap(ClipboardHistoryEntryKind.init(rawValue:)),
              let copiedAt = date("copiedAt")
        else { return nil }
        let record = ClipboardHistorySyncRecord(key: key, kind: kind, text: values["text"] as? String ?? "",
                                                copiedAt: copiedAt, pinnedAt: date("pinnedAt"),
                                                pinChangedAt: date("pinChangedAt"),
                                                source: values["source"] as? String,
                                                imageWidth: values["imageWidth"] as? Int,
                                                imageHeight: values["imageHeight"] as? Int)
        return ClipboardHistorySync.isValid(record) ? (device, record) : nil
    }

    // MARK: - Macs

    struct DeviceState: Equatable {
        var deleted: [String: Date]
        var seenAt: Date
    }

    static func deviceRecord(device: String, state: DeviceState) -> CKRecord? {
        guard let deleted = ClipboardHistorySync.encodedDeleted(state.deleted),
              deleted.count <= ClipboardHistorySync.maxDeletedBytes else { return nil }
        let ckRecord = CKRecord(recordType: deviceType, recordID: deviceRecordID(device))
        ckRecord.encryptedValues["deleted"] = deleted
        ckRecord.encryptedValues["seenAt"] = state.seenAt.timeIntervalSinceReferenceDate
        return ckRecord
    }

    static func deviceState(from ckRecord: CKRecord) -> (device: String, state: DeviceState)? {
        guard ckRecord.recordType == deviceType,
              let device = device(ofDeviceRecordName: ckRecord.recordID.recordName),
              let seconds = ckRecord.encryptedValues["seenAt"] as? Double, seconds.isFinite
        else { return nil }
        let deleted = (ckRecord.encryptedValues["deleted"] as? Data).map(ClipboardHistorySync.decodedDeleted) ?? [:]
        return (device, DeviceState(deleted: deleted, seenAt: Date(timeIntervalSinceReferenceDate: seconds)))
    }

    // MARK: - What the others published

    /// The other Macs as the merge sees them. A Mac is known by its own
    /// record; without one, or silent for longer than deletions are
    /// remembered, its entries are left out.
    static func devices(entries: [String: (device: String, record: ClipboardHistorySyncRecord)],
                        states: [String: DeviceState], excluding own: String,
                        now: Date = Date()) -> [ClipboardHistorySyncDevice] {
        var records: [String: [ClipboardHistorySyncRecord]] = [:]
        for (_, entry) in entries.sorted(by: { $0.key < $1.key }) where entry.device != own {
            records[entry.device, default: []].append(entry.record)
        }
        return states.keys.sorted().compactMap { device in
            guard device != own, let state = states[device],
                  !ClipboardHistorySync.isStale(seen: state.seenAt, now: now) else { return nil }
            return ClipboardHistorySyncDevice(device: device,
                                              records: Array((records[device] ?? []).prefix(ClipboardHistorySync.maxRecords)),
                                              deleted: state.deleted)
        }
    }

    // MARK: - Publishing

    /// Writes go in groups well under CloudKit's limits for one request: a
    /// few hundred records and a few megabytes, pictures uploaded a handful
    /// at a time.
    static let maxBatchRecords = 100
    static let maxBatchBytes = 2 * 1_024 * 1_024
    static let maxBatchAssets = 8

    struct WriteCost: Equatable {
        var bytes: Int
        var asset: Bool
    }

    /// How many of the waiting writes go in the next request: at least one,
    /// so even a record past a bound alone still goes out.
    static func batchCount(_ costs: [WriteCost]) -> Int {
        var bytes = 0, assets = 0, count = 0
        for cost in costs {
            if count > 0, count == maxBatchRecords || bytes + cost.bytes > maxBatchBytes
                || (cost.asset && assets == maxBatchAssets) { break }
            bytes += cost.bytes
            if cost.asset { assets += 1 }
            count += 1
        }
        return count
    }

    struct Plan: Equatable {
        /// Entries to write, under the name the record already has or a new one.
        var save: [(recordName: String, record: ClipboardHistorySyncRecord)]
        var delete: [String]

        static func == (lhs: Plan, rhs: Plan) -> Bool {
            lhs.delete == rhs.delete && lhs.save.map(\.recordName) == rhs.save.map(\.recordName)
                && lhs.save.map(\.record) == rhs.save.map(\.record)
        }
    }

    /// What this Mac has to send so the server holds exactly `desired` for
    /// it: what is new or changed, and the records of entries it no longer
    /// has. A second record for the same entry, left by an interrupted
    /// write, goes too.
    static func plan(desired: [ClipboardHistorySyncRecord],
                     published: [(recordName: String, record: ClipboardHistorySyncRecord)],
                     newName: () -> String) -> Plan {
        var current: [String: (recordName: String, record: ClipboardHistorySyncRecord)] = [:]
        var delete: [String] = []
        for item in published.sorted(by: { $0.recordName < $1.recordName }) {
            if current[item.record.key] == nil {
                current[item.record.key] = item
            } else {
                delete.append(item.recordName)
            }
        }
        var save: [(recordName: String, record: ClipboardHistorySyncRecord)] = []
        var wanted: Set<String> = []
        for record in desired {
            wanted.insert(record.key)
            if let existing = current[record.key] {
                if existing.record != record { save.append((existing.recordName, record)) }
            } else {
                save.append((newName(), record))
            }
        }
        for (key, item) in current where !wanted.contains(key) {
            delete.append(item.recordName)
        }
        return Plan(save: save, delete: delete.sorted())
    }
}
