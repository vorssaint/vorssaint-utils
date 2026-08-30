// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

internal enum DiskBenchmarkMode: String, Codable, CaseIterable, Identifiable {
    case quick
    case standard

    internal var id: String { rawValue }

    internal var byteCount: UInt64 {
        switch self {
        case .quick: return 1_000_000_000
        case .standard: return 4_000_000_000
        }
    }

    internal var requiredAvailableBytes: UInt64 {
        byteCount + DiskBenchmarkSupport.safetyReserveBytes
    }
}

internal enum DiskBenchmarkSupport {
    internal static let safetyReserveBytes: UInt64 = 2_000_000_000

    internal static func hasEnoughSpace(mode: DiskBenchmarkMode, availableBytes: UInt64) -> Bool {
        availableBytes >= mode.requiredAvailableBytes
    }

    internal static func bytesPerSecond(byteCount: UInt64, duration: TimeInterval) -> Double? {
        guard duration > 0, duration.isFinite else { return nil }
        return Double(byteCount) / duration
    }

    internal static func normalizedVolumeUUID(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else { return nil }
        return normalized
    }

    internal static func physicalWholeDisk(from identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.replacingOccurrences(of: "/dev/", with: "")
        guard trimmed.hasPrefix("disk") else { return nil }
        var index = trimmed.index(trimmed.startIndex, offsetBy: 4)
        let numberStart = index
        while index < trimmed.endIndex, trimmed[index].isNumber {
            index = trimmed.index(after: index)
        }
        guard index > numberStart else { return nil }
        return String(trimmed[..<index])
    }

    internal static func refersToSamePhysicalDisk(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = physicalWholeDisk(from: lhs),
              let rhs = physicalWholeDisk(from: rhs) else { return false }
        return lhs == rhs
    }

    internal static func directoryBelongsToSelectedVolume(
        directoryIdentifier: String?,
        volumeIdentifier: String?,
        fallbackWholeDisk: String?
    ) -> Bool {
        refersToSamePhysicalDisk(directoryIdentifier, volumeIdentifier ?? fallbackWholeDisk)
    }

    internal static func bsdIdentifier(at url: URL) -> String? {
        var fileSystem = statfs()
        guard statfs(url.path, &fileSystem) == 0 else { return nil }
        return withUnsafeBytes(of: fileSystem.f_mntfromname) { bytes -> String? in
            guard let baseAddress = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return nil
            }
            let value = String(cString: baseAddress).replacingOccurrences(of: "/dev/", with: "")
            return value.hasPrefix("disk") ? value : nil
        }
    }
}

internal enum DiskBenchmarkPhase: String, Codable, Hashable {
    case preparing
    case writing
    case flushing
    case reading
}

internal struct DiskBenchmarkProgress: Equatable {
    internal let phase: DiskBenchmarkPhase
    internal let completedBytes: UInt64
    internal let totalBytes: UInt64

    internal var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(completedBytes) / Double(totalBytes)))
    }
}

internal struct DiskBenchmarkMeasurement: Equatable {
    internal let readBytesPerSecond: Double
    internal let writeBytesPerSecond: Double
}

internal struct DiskBenchmarkResult: Codable, Equatable, Identifiable {
    internal let id: UUID
    internal let volumeUUID: String?
    internal let sessionDiskID: String
    internal let diskName: String
    internal let fileSystem: String?
    internal let mode: DiskBenchmarkMode
    internal let readBytesPerSecond: Double
    internal let writeBytesPerSecond: Double
    internal let measuredAt: Date
}

internal enum DiskBenchmarkFailure: Error, Equatable, LocalizedError {
    case cancelled
    case readOnly
    case targetUnavailable
    case volumeIdentityUnavailable
    case volumeMismatch
    case insufficientSpace(required: UInt64, available: UInt64)
    case unavailableCapacity
    case cacheControl(code: Int32)
    case memoryAllocation(code: Int32)
    case io(operation: String, code: Int32)

    internal var errorDescription: String? {
        switch self {
        case .cancelled:
            return "The disk benchmark was cancelled."
        case .readOnly:
            return "The selected disk is read-only."
        case .targetUnavailable:
            return "The selected disk is no longer available."
        case .volumeIdentityUnavailable:
            return "The selected disk's physical identity could not be verified."
        case .volumeMismatch:
            return "The benchmark folder is not on the selected physical disk."
        case let .insufficientSpace(required, available):
            return "The disk benchmark needs \(required) bytes but only \(available) bytes are available."
        case .unavailableCapacity:
            return "The disk's available capacity could not be read."
        case let .cacheControl(code):
            return "Disk cache control failed (\(code))."
        case let .memoryAllocation(code):
            return "The benchmark buffer could not be allocated (\(code))."
        case let .io(operation, code):
            return "Disk \(operation) failed (\(code))."
        }
    }
}

internal final class DiskBenchmarkCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    internal var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    internal func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

internal struct DiskBenchmarkRunConfiguration: Equatable {
    internal let byteCount: UInt64
    internal let chunkSize: Int
    internal let requiredAvailableBytes: UInt64
    internal let requiresNoCache: Bool

    internal init(byteCount: UInt64,
                  chunkSize: Int,
                  requiredAvailableBytes: UInt64,
                  requiresNoCache: Bool) {
        self.byteCount = byteCount
        self.chunkSize = chunkSize
        self.requiredAvailableBytes = requiredAvailableBytes
        self.requiresNoCache = requiresNoCache
    }

    internal init(mode: DiskBenchmarkMode) {
        self.init(byteCount: mode.byteCount,
                  chunkSize: 8 * 1_048_576,
                  requiredAvailableBytes: mode.requiredAvailableBytes,
                  requiresNoCache: true)
    }
}

internal struct DiskBenchmarkRunner {
    private let configuration: DiskBenchmarkRunConfiguration

    internal init(configuration: DiskBenchmarkRunConfiguration) {
        self.configuration = configuration
    }

    internal func run(in directory: URL,
                      cancellation: DiskBenchmarkCancellationToken,
                      progress: (DiskBenchmarkProgress) -> Void) throws -> DiskBenchmarkMeasurement {
        try checkCancellation(cancellation)
        try checkAvailableSpace(in: directory)

        let scratchURL = directory.appendingPathComponent(
            ".vorssaint-disk-benchmark-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = scratchURL.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw ioFailure("open") }
        defer { Darwin.close(descriptor) }

        guard Darwin.unlink(scratchURL.path) == 0 else { throw ioFailure("unlink") }
        if configuration.requiresNoCache, Darwin.fcntl(descriptor, F_NOCACHE, 1) == -1 {
            throw DiskBenchmarkFailure.cacheControl(code: errno)
        }

        var allocation: UnsafeMutableRawPointer?
        let allocationStatus = posix_memalign(&allocation, 4_096, configuration.chunkSize)
        guard allocationStatus == 0, let buffer = allocation else {
            throw DiskBenchmarkFailure.memoryAllocation(code: Int32(allocationStatus))
        }
        defer { free(buffer) }
        memset(buffer, 0xA5, configuration.chunkSize)

        progress(DiskBenchmarkProgress(phase: .writing,
                                       completedBytes: 0,
                                       totalBytes: configuration.byteCount))
        let writeStarted = DispatchTime.now().uptimeNanoseconds
        try transferWrite(descriptor: descriptor,
                          buffer: buffer,
                          cancellation: cancellation,
                          progress: progress)
        progress(DiskBenchmarkProgress(phase: .flushing,
                                       completedBytes: configuration.byteCount,
                                       totalBytes: configuration.byteCount))
        guard Darwin.fsync(descriptor) == 0 else { throw ioFailure("sync") }
        let writeEnded = DispatchTime.now().uptimeNanoseconds

        try checkCancellation(cancellation)
        guard Darwin.lseek(descriptor, 0, SEEK_SET) != -1 else { throw ioFailure("seek") }
        progress(DiskBenchmarkProgress(phase: .reading,
                                       completedBytes: 0,
                                       totalBytes: configuration.byteCount))
        let readStarted = DispatchTime.now().uptimeNanoseconds
        try transferRead(descriptor: descriptor,
                         buffer: buffer,
                         cancellation: cancellation,
                         progress: progress)
        let readEnded = DispatchTime.now().uptimeNanoseconds

        guard let writeRate = DiskBenchmarkSupport.bytesPerSecond(
            byteCount: configuration.byteCount,
            duration: seconds(from: writeStarted, to: writeEnded)
        ), let readRate = DiskBenchmarkSupport.bytesPerSecond(
            byteCount: configuration.byteCount,
            duration: seconds(from: readStarted, to: readEnded)
        ) else {
            throw DiskBenchmarkFailure.io(operation: "timing", code: EINVAL)
        }
        return DiskBenchmarkMeasurement(readBytesPerSecond: readRate,
                                        writeBytesPerSecond: writeRate)
    }

    private func checkAvailableSpace(in directory: URL) throws {
        guard configuration.requiredAvailableBytes > 0 else { return }
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let rawAvailable = values?.volumeAvailableCapacityForImportantUsage,
              rawAvailable >= 0 else {
            throw DiskBenchmarkFailure.unavailableCapacity
        }
        let available = UInt64(rawAvailable)
        guard available >= configuration.requiredAvailableBytes else {
            throw DiskBenchmarkFailure.insufficientSpace(required: configuration.requiredAvailableBytes,
                                                         available: available)
        }
    }

    private func transferWrite(descriptor: Int32,
                               buffer: UnsafeMutableRawPointer,
                               cancellation: DiskBenchmarkCancellationToken,
                               progress: (DiskBenchmarkProgress) -> Void) throws {
        var completed: UInt64 = 0
        var lastUpdate = DispatchTime.now().uptimeNanoseconds
        while completed < configuration.byteCount {
            try checkCancellation(cancellation)
            let count = min(UInt64(configuration.chunkSize), configuration.byteCount - completed)
            var offset = 0
            while offset < Int(count) {
                let written = Darwin.write(descriptor,
                                           buffer.advanced(by: offset),
                                           Int(count) - offset)
                if written > 0 {
                    offset += written
                } else if written == -1, errno == EINTR {
                    continue
                } else {
                    throw ioFailure("write")
                }
            }
            completed += count
            publishProgressIfNeeded(phase: .writing,
                                    completed: completed,
                                    lastUpdate: &lastUpdate,
                                    progress: progress)
        }
    }

    private func transferRead(descriptor: Int32,
                              buffer: UnsafeMutableRawPointer,
                              cancellation: DiskBenchmarkCancellationToken,
                              progress: (DiskBenchmarkProgress) -> Void) throws {
        var completed: UInt64 = 0
        var lastUpdate = DispatchTime.now().uptimeNanoseconds
        while completed < configuration.byteCount {
            try checkCancellation(cancellation)
            let count = min(UInt64(configuration.chunkSize), configuration.byteCount - completed)
            var offset = 0
            while offset < Int(count) {
                let amount = Darwin.read(descriptor,
                                         buffer.advanced(by: offset),
                                         Int(count) - offset)
                if amount > 0 {
                    offset += amount
                } else if amount == -1, errno == EINTR {
                    continue
                } else {
                    throw DiskBenchmarkFailure.io(operation: "read", code: amount == 0 ? EIO : errno)
                }
            }
            completed += count
            publishProgressIfNeeded(phase: .reading,
                                    completed: completed,
                                    lastUpdate: &lastUpdate,
                                    progress: progress)
        }
    }

    private func publishProgressIfNeeded(phase: DiskBenchmarkPhase,
                                         completed: UInt64,
                                         lastUpdate: inout UInt64,
                                         progress: (DiskBenchmarkProgress) -> Void) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard completed == configuration.byteCount || now - lastUpdate >= 100_000_000 else { return }
        lastUpdate = now
        progress(DiskBenchmarkProgress(phase: phase,
                                       completedBytes: completed,
                                       totalBytes: configuration.byteCount))
    }

    private func checkCancellation(_ cancellation: DiskBenchmarkCancellationToken) throws {
        guard !cancellation.isCancelled else { throw DiskBenchmarkFailure.cancelled }
    }

    private func seconds(from start: UInt64, to end: UInt64) -> TimeInterval {
        TimeInterval(end - start) / 1_000_000_000
    }

    private func ioFailure(_ operation: String) -> DiskBenchmarkFailure {
        DiskBenchmarkFailure.io(operation: operation, code: errno)
    }
}

internal final class DiskBenchmarkResultStore {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()
    private var sessionResults: [String: DiskBenchmarkResult] = [:]
    private let maximumPersistentResults = 32

    internal init(defaults: UserDefaults = .standard,
                  key: String = DefaultsKey.diskBenchmarkResults) {
        self.defaults = defaults
        self.key = key
    }

    internal func save(_ result: DiskBenchmarkResult) {
        lock.lock()
        defer { lock.unlock() }
        guard let volumeUUID = DiskBenchmarkSupport.normalizedVolumeUUID(result.volumeUUID) else {
            sessionResults[result.sessionDiskID] = result
            return
        }
        var results = loadPersistentResultsLocked().filter {
            DiskBenchmarkSupport.normalizedVolumeUUID($0.volumeUUID) != volumeUUID
        }
        results.append(result)
        results.sort { $0.measuredAt > $1.measuredAt }
        if results.count > maximumPersistentResults {
            results.removeLast(results.count - maximumPersistentResults)
        }
        if let data = try? JSONEncoder().encode(results) {
            defaults.set(data, forKey: key)
        }
    }

    internal func result(volumeUUID: String?, sessionDiskID: String) -> DiskBenchmarkResult? {
        lock.lock()
        defer { lock.unlock() }
        if let volumeUUID = DiskBenchmarkSupport.normalizedVolumeUUID(volumeUUID) {
            return loadPersistentResultsLocked().first {
                DiskBenchmarkSupport.normalizedVolumeUUID($0.volumeUUID) == volumeUUID
            }
        }
        return sessionResults[sessionDiskID]
    }

    private func loadPersistentResultsLocked() -> [DiskBenchmarkResult] {
        guard let data = defaults.data(forKey: key),
              let results = try? JSONDecoder().decode([DiskBenchmarkResult].self, from: data) else {
            return []
        }
        return results
    }
}
