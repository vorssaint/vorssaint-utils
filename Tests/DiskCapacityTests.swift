// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs the production volume reader, sampler and alert selector with scripted
/// Foundation resource values. No disks are mounted and no notifications are sent.
enum DiskCapacityTests {
    struct ResourceValues {
        var volumeName: String? = "External"
        var volumeLocalizedName: String?
        var volumeTotalCapacity: Int? = 1_000_000_000_000
        var volumeAvailableCapacity: Int? = 900_000_000_000
        var volumeAvailableCapacityForImportantUsage: Int64?
        var volumeIsInternal: Bool? = false
        var volumeIsReadOnly: Bool? = false
        var volumeIsRemovable: Bool? = true
        var volumeIsEjectable: Bool? = true
        var volumeIsLocal: Bool? = true
        var volumeUUIDString: String? = "external-volume"
    }

    struct URL {
        var path = "/Volumes/External"
        var values = ResourceValues()
        var lastPathComponent: String { (path as NSString).lastPathComponent }

        func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> ResourceValues {
            if keys.contains(.volumeAvailableCapacityForImportantUsageKey) {
                Fixture.importantReads.append(path)
            }
            return values
        }
    }

    struct FileManager {
        static let `default` = FileManager()
        func mountedVolumeURLs(includingResourceValuesForKeys keys: [URLResourceKey],
                               options: Foundation.FileManager.VolumeEnumerationOptions) -> [URL]? {
            Fixture.volumes
        }
    }

    struct SystemSnapshot { var disk: DiskReading? }

    class Fixture {
        static var volumes: [URL] = []
        static var importantReads: [String] = []
        static var metadataReads = 0
        static let metadataRefreshInterval: TimeInterval = 30
        static let backgroundMetadataRefreshInterval: TimeInterval = 3600
        var metadataCache: [String: (metadata: Sampler.DiskMetadata, updatedAt: TimeInterval, isFull: Bool)] = [:]

        static func diskutilInfo(for path: String) -> Sampler.DiskMetadata {
            metadataReads += 1
            return Sampler.DiskMetadata()
        }
        static func statfsIdentity(for path: String) -> (bsdName: String?, fileSystemType: String?) {
            ("disk4s1", path == "/" ? "apfs" : "exfat")
        }
        static func readCounters() -> [String: DiskIOCounters] { [:] }
        func ratesAndTotals(for diskID: String, counters: DiskIOCounters, now: TimeInterval)
            -> (readBytesPerSec: Double?, writeBytesPerSec: Double?, totalRead: UInt64?, totalWritten: UInt64?) {
            (nil, nil, nil, nil)
        }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.disk-capacity"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer {
            defaults.removePersistentDomain(forName: domain)
            Fixture.volumes = []
            Fixture.importantReads = []
            Fixture.metadataReads = 0
        }
        defaults.set(10, forKey: DefaultsKey.monitorAlertDiskFreePercent)
        let sampler = Sampler()
        let alerts = Alerts()
        var external = URL()
        var now: TimeInterval = 0

        func sample(_ volumes: [URL]) -> DiskReading {
            Fixture.volumes = volumes
            now += 1
            return sampler.sample(now: now, refreshMetadata: false)
        }
        func lowDisk(_ reading: DiskReading) -> String? {
            alerts.lowDisk(from: SystemSnapshot(disk: reading), defaults: defaults)?.name
        }

        // The purge estimate must not replace a larger, current free count.
        let importantValues: [Int64?] = [1_000_000_000, 0, nil]
        for important in importantValues {
            external.values.volumeAvailableCapacityForImportantUsage = important
            let reading = sample([external])
            suite.expect(reading.devices.first?.freeBytes == 900_000_000_000,
                         "an external volume keeps its 900 GB free when the important-use value is smaller or absent")
            suite.expect(reading.devices.first?.usedBytes == 100_000_000_000,
                         "the external volume reports physical used space consistently")
            suite.expect(lowDisk(reading) == nil,
                         "a nearly empty exFAT reading does not trigger the low-space alert")
        }
        suite.expect(Fixture.metadataReads == 1,
                     "repeated samples reuse identity metadata while reading capacity again")

        external.values.volumeAvailableCapacity = 0
        external.values.volumeAvailableCapacityForImportantUsage = 0
        let full = sample([external])
        suite.expect(full.devices.first?.freeBytes == 0 && lowDisk(full) == "External",
                     "a fresh zero remains full and alerts even with metadata cached from an earlier empty-disk sample")
        external.values.volumeAvailableCapacity = 1_000_000_000_000
        let empty = sample([external])
        suite.expect(empty.devices.first?.usedBytes == 0 && lowDisk(empty) == nil,
                     "a fresh zero used count stays empty instead of falling back to cached usage")

        external.values.volumeAvailableCapacity = 100_000_000_000
        external.values.volumeAvailableCapacityForImportantUsage = nil
        suite.expect(lowDisk(sample([external])) == nil, "exactly 10 percent free does not alert")
        external.values.volumeAvailableCapacity = 99_999_999_999
        suite.expect(lowDisk(sample([external])) == "External", "an external volume below 10 percent still alerts")

        var internalVolume = URL(path: "/")
        internalVolume.values.volumeName = "Internal"
        internalVolume.values.volumeIsInternal = true
        internalVolume.values.volumeIsRemovable = false
        internalVolume.values.volumeAvailableCapacity = 20_000_000_000
        internalVolume.values.volumeAvailableCapacityForImportantUsage = 200_000_000_000
        let purgeable = sample([internalVolume])
        suite.expect(purgeable.devices.first?.freeBytes == 200_000_000_000
                     && purgeable.devices.first?.usedBytes == 980_000_000_000
                     && purgeable.devices.first?.purgeableBytes == 180_000_000_000,
                     "APFS retains reclaimable space without subtracting it from physical usage")
        suite.expect(lowDisk(purgeable) == nil, "reclaimable space still prevents a premature APFS alert")

        let mixed = sample([external, internalVolume])
        suite.expect(mixed.devices.first?.name == "Internal" && lowDisk(mixed) == "External",
                     "the alert finds the low external volume even when the panel defaults to the healthy internal one")
        suite.expect(lowDisk(sample([internalVolume])) == nil,
                     "disconnecting the external volume removes it from the next sample despite cached metadata")
        suite.expect(sample([]).isEmpty, "no mounted volumes produces no cached devices")
        suite.expect(alerts.lowDisk(from: SystemSnapshot(disk: nil), defaults: defaults) == nil,
                     "a missing disk snapshot does not alert")

        external.values.volumeAvailableCapacity = nil
        external.values.volumeAvailableCapacityForImportantUsage = nil
        let unknown = sample([external])
        suite.expect(unknown.isEmpty && lowDisk(unknown) == nil,
                     "unavailable free-space readings are skipped instead of becoming full or reusing stale capacity")
        external.values.volumeAvailableCapacity = -1
        external.values.volumeAvailableCapacityForImportantUsage = -1
        suite.expect(sample([external]).isEmpty, "invalid negative capacities remain unavailable")
        external.values.volumeAvailableCapacity = nil
        external.values.volumeAvailableCapacityForImportantUsage = 50_000_000_000
        suite.expect(lowDisk(sample([external])) == "External",
                     "an important-use reading can still detect low space when the raw reading is unavailable")

        external.values.volumeAvailableCapacity = 900_000_000_000
        external.values.volumeAvailableCapacityForImportantUsage = Int64.max
        let clamped = sample([external]).devices.first
        suite.expect(clamped?.freeBytes == 1_000_000_000_000 && clamped?.purgeableBytes == 100_000_000_000,
                     "free and reclaimable space stay within the volume capacity")
        external.values.volumeIsReadOnly = true
        Fixture.importantReads = []
        let readOnly = sample([external])
        suite.expect(Fixture.importantReads.isEmpty && readOnly.devices.first?.freeBytes == 900_000_000_000,
                     "read-only volumes retain raw capacity without querying the purge service")

        external.values.volumeIsReadOnly = false
        external.values.volumeAvailableCapacity = 0
        external.values.volumeAvailableCapacityForImportantUsage = nil
        external.values.volumeTotalCapacity = 9_999_999_999
        suite.expect(lowDisk(sample([external])) == nil, "the existing 10 GB minimum volume size is preserved")
        external.values.volumeTotalCapacity = 0
        suite.expect(sample([external]).isEmpty, "a zero total is not a measurable volume")
    }
}
