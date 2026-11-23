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

    final class Delivery {
        var diskAlertGate = DiskAlertGate()
        static var now = Date(timeIntervalSince1970: 0)
        enum Notifier {
            static var requests: [(body: String, completion: (Bool) -> Void)] = []
            static func post(title: String, body: String, completion: @escaping (Bool) -> Void) {
                requests.append((body, completion))
            }
        }
    }

    static func run(_ suite: TestSuite) {
        defer {
            Fixture.volumes = []
            Fixture.importantReads = []
            Fixture.metadataReads = 0
        }
        let sampler = Sampler()
        var external = URL()
        var now: TimeInterval = 0

        func sample(_ volumes: [URL]) -> DiskReading {
            Fixture.volumes = volumes
            now += 1
            return sampler.sample(now: now, refreshMetadata: false)
        }
        func lowDisk(_ reading: DiskReading?) -> String? {
            var gate = DiskAlertGate()
            return gate.next(from: reading, threshold: 10, now: Date(timeIntervalSince1970: 0))?.name
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
        internalVolume.values.volumeUUIDString = "internal-volume"
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
        suite.expect(lowDisk(nil) == nil, "a missing disk snapshot does not alert")

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

        alertTiming(suite, sample: sample)
        alertVolumes(suite, sample: sample)
        alertDelivery(suite, sample: sample)
    }

    private static func alertTiming(_ suite: TestSuite, sample: ([URL]) -> DiskReading) {
        var disk = URL()
        let healthy = sample([disk])
        disk.values.volumeAvailableCapacity = 90_000_000_000
        let low = sample([disk])
        disk.values.volumeAvailableCapacity = 50_000_000_000
        let half = sample([disk])
        disk.values.volumeAvailableCapacity = 49_000_000_000
        let critical = sample([disk])
        var gate = DiskAlertGate()
        func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
        func next(_ reading: DiskReading?, at seconds: TimeInterval) -> DiskAlertGate.Alert? {
            gate.next(from: reading, threshold: 10, now: date(seconds))
        }

        suite.expect(next(healthy, at: 0) == nil, "a healthy volume does not spend the first alert")
        let first = next(low, at: 1)
        suite.expect(first?.name == "External" && first?.isCritical == false, "the first low reading alerts immediately")
        if let first { gate.finish(first, accepted: true, now: date(2)) }
        let sixHours: TimeInterval = 6 * 60 * 60
        suite.expect(next(low, at: sixHours + 1) == nil, "an unchanged low disk stays quiet until six hours after acceptance")
        let reminder = next(low, at: sixHours + 2)
        suite.expect(reminder?.name == "External", "the unchanged disk gets its reminder at the six-hour boundary")
        if let reminder { gate.finish(reminder, accepted: true, now: date(sixHours + 2)) }
        suite.expect(next(half, at: sixHours + 3) == nil, "exactly half the threshold does not escalate")
        let escalation = next(critical, at: sixHours + 4)
        suite.expect(escalation?.isCritical == true, "crossing below half the threshold escalates early")
        if let escalation { gate.finish(escalation, accepted: true, now: date(sixHours + 4)) }
        suite.expect(next(nil, at: sixHours + 5) == nil && next(healthy, at: sixHours + 6) == nil
                     && next(critical, at: sixHours + 7) == nil, "temporary absence or recovery does not rearm escalation")

        var oddLimit = DiskAlertGate()
        disk.values.volumeAvailableCapacity = 25_000_000_000
        let atHalf = oddLimit.next(from: sample([disk]), threshold: 5, now: date(0))
        suite.expect(atHalf?.limitPercent == 5, "exactly 2.5 percent remains an ordinary alert with a 5 percent limit")
        if let atHalf { oddLimit.finish(atHalf, accepted: true, now: date(0)) }
        disk.values.volumeAvailableCapacity = 24_000_000_000
        let belowHalf = oddLimit.next(from: sample([disk]), threshold: 5, now: date(1))
        suite.expect(belowHalf?.isCritical == true && belowHalf?.limitPercent == 2.5,
                     "crossing half of an odd limit retains the fraction in the critical notification")
    }

    private static func alertVolumes(_ suite: TestSuite, sample: ([URL]) -> DiskReading) {
        var low = URL(path: "/")
        low.values.volumeUUIDString = "internal-volume"
        low.values.volumeName = "Internal"
        low.values.volumeIsInternal = true
        low.values.volumeAvailableCapacity = 90_000_000_000
        var first = URL()
        first.values.volumeAvailableCapacity = 40_000_000_000
        var second = first
        second.path = "/Volumes/Other"
        second.values.volumeName = "Other"
        second.values.volumeUUIDString = "other-volume"
        let all = sample([low, first, second])
        var gate = DiskAlertGate()
        let now = Date(timeIntervalSince1970: 0)
        func next(_ reading: DiskReading) -> DiskAlertGate.Alert? {
            gate.next(from: reading, threshold: 10, now: now)
        }

        let critical = next(all)
        suite.expect(critical?.isCritical == true, "an eligible critical disk has priority over an earlier low disk")
        let otherCritical = next(all)
        suite.expect(otherCritical?.isCritical == true && otherCritical?.name != critical?.name,
                     "another critical volume can alert while the first request is pending")
        if let critical { gate.finish(critical, accepted: true, now: now) }
        if let otherCritical { gate.finish(otherCritical, accepted: true, now: now) }
        suite.expect(next(all)?.name == "Internal", "cooling critical volumes do not hide another low disk")

        first.path = "/Volumes/Renamed"
        first.values.volumeName = "Renamed"
        suite.expect(next(sample([first])) == nil, "the same UUID retains its cooldown across a rename and remount")
        first.values.volumeUUIDString = "replacement-volume"
        suite.expect(next(sample([first]))?.name == "Renamed", "a new UUID at the same mount path gets its own alert")

        first.values.volumeUUIDString = ""
        first.path = "/Volumes/First"
        second.values.volumeUUIDString = ""
        second.values.volumeName = first.values.volumeName
        let withoutUUIDs = sample([first, second])
        let byPath = next(withoutUUIDs)
        if let byPath { gate.finish(byPath, accepted: true, now: now) }
        suite.expect(byPath != nil && next(withoutUUIDs) != nil && next(withoutUUIDs) == nil,
                     "volumes without UUIDs use distinct mount paths even when their names match")
        first.values.volumeUUIDString = nil
        suite.expect(next(sample([first])) == nil, "a missing UUID uses the same path fallback as an empty UUID")
    }

    private static func alertDelivery(_ suite: TestSuite, sample: ([URL]) -> DiskReading) {
        let domain = "com.vorssaint.tests.disk-capacity"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(10, forKey: DefaultsKey.monitorAlertDiskFreePercent)
        let previousLocale = MetricFormat.locale
        MetricFormat.locale = Locale(identifier: "en_US")
        defer {
            defaults.removePersistentDomain(forName: domain)
            Delivery.Notifier.requests = []
            MetricFormat.locale = previousLocale
        }
        let service = Delivery()
        var disk = URL()
        disk.values.volumeAvailableCapacity = 90_000_000_000
        let low = sample([disk])
        var other = disk
        other.path = "/Volumes/Other"
        other.values.volumeUUIDString = "other-volume"
        other.values.volumeName = "Other"
        let both = sample([disk, other])
        disk.values.volumeAvailableCapacity = 40_000_000_000
        let critical = sample([disk])
        func evaluate(_ reading: DiskReading, at seconds: TimeInterval) {
            Delivery.now = Date(timeIntervalSince1970: seconds)
            service.evaluateDisk(reading, defaults: defaults, strings: .enUS)
        }

        evaluate(low, at: 0)
        evaluate(both, at: 1)
        evaluate(both, at: 2)
        let pending = Delivery.Notifier.requests
        suite.expect(pending.map { $0.body } == ["External has less than 10% free.", "Other has less than 10% free."],
                     "two volumes can post concurrently without duplicating either pending notification")
        pending.last?.completion(true)
        pending.first?.completion(false)
        evaluate(low, at: 61)
        suite.expect(Delivery.Notifier.requests.count == 2, "a refusal does not immediately post another notification")
        evaluate(low, at: 62)
        suite.expect(Delivery.Notifier.requests.count == 3, "the refused notification is retried a minute later")
        Delivery.Notifier.requests.last?.completion(true)
        evaluate(critical, at: 63)
        suite.expect(Delivery.Notifier.requests.count == 4
                     && Delivery.Notifier.requests.last?.body == "External has less than 5% free.",
                     "an escalation names the same volume and reports the lower threshold")
        Delivery.Notifier.requests.last?.completion(false)
        evaluate(low, at: 123)
        suite.expect(Delivery.Notifier.requests.count == 4, "a refused escalation preserves the accepted low alert")
        evaluate(critical, at: 123)
        suite.expect(Delivery.Notifier.requests.count == 5, "an escalation can retry after a refusal")
        Delivery.Notifier.requests.last?.completion(true)
        evaluate(critical, at: 123 + 6 * 3_600 - 1)
        suite.expect(Delivery.Notifier.requests.count == 5, "an accepted critical notification suppresses repeats")
        evaluate(critical, at: 123 + 6 * 3_600)
        suite.expect(Delivery.Notifier.requests.count == 6, "persistent critical space repeats after six hours")
    }
}
