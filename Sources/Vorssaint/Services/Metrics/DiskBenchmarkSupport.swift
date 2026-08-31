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

    internal var passCount: Int {
        switch self {
        case .quick: return 1
        case .standard: return 3
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

    internal static func availableCapacity(importantUsage: UInt64?,
                                           regular: UInt64?,
                                           fileSystem: UInt64?) -> UInt64? {
        if let importantUsage, importantUsage > 0 { return importantUsage }
        if let regular, regular > 0 { return regular }
        if let fileSystem, fileSystem > 0 { return fileSystem }
        return importantUsage != nil || regular != nil || fileSystem != nil ? 0 : nil
    }

    internal static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    internal static func shouldFallbackToFSync(afterFullSyncError errorCode: Int32) -> Bool {
        errorCode == ENOTSUP || errorCode == EINVAL || errorCode == ENOTTY
    }

    internal static func shouldFallbackFromNoCache(errorCode: Int32) -> Bool {
        errorCode == ENOTSUP || errorCode == EINVAL || errorCode == ENOTTY
    }

    internal static func applyPatternMarkers(to buffer: UnsafeMutableRawPointer,
                                             byteCount: Int,
                                             passIndex: Int,
                                             chunkIndex: UInt64) {
        guard byteCount >= MemoryLayout<UInt64>.size else { return }
        let passMarker = UInt64(truncatingIfNeeded: passIndex) &* 0x9E37_79B9_7F4A_7C15
        let chunkMarker = chunkIndex &* 0xBF58_476D_1CE4_E5B9
        var offset = 0
        var pageIndex: UInt64 = 0
        while offset + MemoryLayout<UInt64>.size <= byteCount {
            let marker = (passMarker ^ chunkMarker ^ pageIndex &* 0x94D0_49BB_1331_11EB).littleEndian
            buffer.advanced(by: offset).storeBytes(of: marker, as: UInt64.self)
            offset += 4_096
            pageIndex += 1
        }
    }

    internal static func buffersMatch(_ expected: UnsafeRawPointer,
                                      _ actual: UnsafeRawPointer,
                                      byteCount: Int) -> Bool {
        Darwin.memcmp(expected, actual, byteCount) == 0
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

internal struct DiskEjectionSafety {
    private let isDiskBenchmarkRunning: () -> Bool

    internal init(isDiskBenchmarkRunning: @escaping () -> Bool) {
        self.isDiskBenchmarkRunning = isDiskBenchmarkRunning
    }

    internal var allowsEjection: Bool {
        !isDiskBenchmarkRunning()
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
    case verificationFailed
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
        case .verificationFailed:
            return "The disk benchmark read-back verification failed."
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
    internal let passCount: Int

    internal init(byteCount: UInt64,
                  chunkSize: Int,
                  requiredAvailableBytes: UInt64,
                  requiresNoCache: Bool,
                  passCount: Int = 1) {
        self.byteCount = byteCount
        self.chunkSize = chunkSize
        self.requiredAvailableBytes = requiredAvailableBytes
        self.requiresNoCache = requiresNoCache
        self.passCount = passCount
    }

    internal init(mode: DiskBenchmarkMode) {
        self.init(byteCount: mode.byteCount,
                  chunkSize: 8 * 1_048_576,
                  requiredAvailableBytes: mode.requiredAvailableBytes,
                  requiresNoCache: true,
                  passCount: mode.passCount)
    }

    internal var totalProgressBytes: UInt64? {
        guard passCount > 0 else { return nil }
        let (bytesPerPass, phaseOverflow) = byteCount.multipliedReportingOverflow(by: 2)
        guard !phaseOverflow else { return nil }
        let (totalBytes, passOverflow) = bytesPerPass
            .multipliedReportingOverflow(by: UInt64(passCount))
        return passOverflow ? nil : totalBytes
    }

    internal func progressBaseBytes(passIndex: Int,
                                    phase: DiskBenchmarkPhase) -> UInt64? {
        guard passIndex >= 0,
              passIndex < passCount,
              let unsignedPassIndex = UInt64(exactly: passIndex),
              totalProgressBytes != nil else { return nil }
        let (passSegment, passOverflow) = unsignedPassIndex.multipliedReportingOverflow(by: 2)
        guard !passOverflow else { return nil }
        let phaseSegment: UInt64 = phase == .reading || phase == .flushing ? 1 : 0
        let (segment, segmentOverflow) = passSegment.addingReportingOverflow(phaseSegment)
        guard !segmentOverflow else { return nil }
        let (offset, offsetOverflow) = byteCount.multipliedReportingOverflow(by: segment)
        return offsetOverflow ? nil : offset
    }
}

internal struct DiskBenchmarkRunner {
    private let configuration: DiskBenchmarkRunConfiguration
    private let setNoCache: (Int32) -> Int32

    internal init(configuration: DiskBenchmarkRunConfiguration,
                  setNoCache: @escaping (Int32) -> Int32 = { descriptor in
                      Darwin.fcntl(descriptor, F_NOCACHE, 1)
                  }) {
        self.configuration = configuration
        self.setNoCache = setNoCache
    }

    internal func run(in directory: URL,
                      cancellation: DiskBenchmarkCancellationToken,
                      progress: (DiskBenchmarkProgress) -> Void) throws -> DiskBenchmarkMeasurement {
        try checkCancellation(cancellation)
        guard configuration.byteCount > 0,
              configuration.chunkSize > 0,
              configuration.passCount > 0 else {
            throw DiskBenchmarkFailure.io(operation: "configuration", code: EINVAL)
        }
        try checkAvailableSpace(in: directory)

        guard let totalBytes = configuration.totalProgressBytes else {
            throw DiskBenchmarkFailure.io(operation: "configuration", code: EOVERFLOW)
        }

        var measurements: [DiskBenchmarkMeasurement] = []
        measurements.reserveCapacity(configuration.passCount)
        for passIndex in 0..<configuration.passCount {
            try checkCancellation(cancellation)
            measurements.append(try runPass(in: directory,
                                            passIndex: passIndex,
                                            totalBytes: totalBytes,
                                            cancellation: cancellation,
                                            progress: progress))
        }

        guard let readRate = DiskBenchmarkSupport.median(measurements.map(\.readBytesPerSecond)),
              let writeRate = DiskBenchmarkSupport.median(measurements.map(\.writeBytesPerSecond)) else {
            throw DiskBenchmarkFailure.io(operation: "timing", code: EINVAL)
        }
        return DiskBenchmarkMeasurement(readBytesPerSecond: readRate,
                                        writeBytesPerSecond: writeRate)
    }

    private func runPass(in directory: URL,
                         passIndex: Int,
                         totalBytes: UInt64,
                         cancellation: DiskBenchmarkCancellationToken,
                         progress: (DiskBenchmarkProgress) -> Void) throws -> DiskBenchmarkMeasurement {
        let scratchURL = directory.appendingPathComponent(
            ".vorssaint-disk-benchmark-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = scratchURL.path.withCString {
            Darwin.open($0, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw ioFailure("open") }
        defer {
            Darwin.close(descriptor)
            Darwin.unlink(scratchURL.path)
        }

        guard Darwin.unlink(scratchURL.path) == 0 else { throw ioFailure("unlink") }
        if configuration.requiresNoCache, setNoCache(descriptor) == -1 {
            let cacheControlError = errno
            guard DiskBenchmarkSupport.shouldFallbackFromNoCache(errorCode: cacheControlError) else {
                throw DiskBenchmarkFailure.cacheControl(code: cacheControlError)
            }
        }

        var expectedAllocation: UnsafeMutableRawPointer?
        let expectedStatus = posix_memalign(&expectedAllocation, 4_096, configuration.chunkSize)
        guard expectedStatus == 0, let expectedBuffer = expectedAllocation else {
            throw DiskBenchmarkFailure.memoryAllocation(code: Int32(expectedStatus))
        }
        defer { free(expectedBuffer) }

        var readAllocation: UnsafeMutableRawPointer?
        let readStatus = posix_memalign(&readAllocation, 4_096, configuration.chunkSize)
        guard readStatus == 0, let readBuffer = readAllocation else {
            throw DiskBenchmarkFailure.memoryAllocation(code: Int32(readStatus))
        }
        defer { free(readBuffer) }
        arc4random_buf(expectedBuffer, configuration.chunkSize)

        guard let writeOffset = configuration.progressBaseBytes(passIndex: passIndex,
                                                                phase: .writing),
              let readOffset = configuration.progressBaseBytes(passIndex: passIndex,
                                                               phase: .reading) else {
            throw DiskBenchmarkFailure.io(operation: "configuration", code: EOVERFLOW)
        }

        progress(DiskBenchmarkProgress(phase: .writing,
                                       completedBytes: writeOffset,
                                       totalBytes: totalBytes))
        var writeNanoseconds = try transferWrite(descriptor: descriptor,
                                                 buffer: expectedBuffer,
                                                 passIndex: passIndex,
                                                 passOffset: writeOffset,
                                                 totalBytes: totalBytes,
                                                 cancellation: cancellation,
                                                 progress: progress)
        progress(DiskBenchmarkProgress(phase: .flushing,
                                       completedBytes: readOffset,
                                       totalBytes: totalBytes))
        let syncStarted = DispatchTime.now().uptimeNanoseconds
        try synchronize(descriptor: descriptor)
        writeNanoseconds += DispatchTime.now().uptimeNanoseconds - syncStarted

        try checkCancellation(cancellation)
        guard Darwin.lseek(descriptor, 0, SEEK_SET) != -1 else { throw ioFailure("seek") }
        progress(DiskBenchmarkProgress(phase: .reading,
                                       completedBytes: readOffset,
                                       totalBytes: totalBytes))
        let readNanoseconds = try transferRead(descriptor: descriptor,
                                               expectedBuffer: expectedBuffer,
                                               readBuffer: readBuffer,
                                               passIndex: passIndex,
                                               passOffset: readOffset,
                                               totalBytes: totalBytes,
                                               cancellation: cancellation,
                                               progress: progress)

        guard let writeRate = DiskBenchmarkSupport.bytesPerSecond(
            byteCount: configuration.byteCount,
            duration: seconds(nanoseconds: writeNanoseconds)
        ), let readRate = DiskBenchmarkSupport.bytesPerSecond(
            byteCount: configuration.byteCount,
            duration: seconds(nanoseconds: readNanoseconds)
        ) else {
            throw DiskBenchmarkFailure.io(operation: "timing", code: EINVAL)
        }
        return DiskBenchmarkMeasurement(readBytesPerSecond: readRate,
                                        writeBytesPerSecond: writeRate)
    }

    private func checkAvailableSpace(in directory: URL) throws {
        guard configuration.requiredAvailableBytes > 0 else { return }
        let values = try? directory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let importantCapacity = nonnegativeUInt(values?.volumeAvailableCapacityForImportantUsage)
        let regularCapacity = nonnegativeUInt(values?.volumeAvailableCapacity)
        let fileSystemCapacity = fileSystemAvailableCapacity(at: directory)
        guard let available = DiskBenchmarkSupport.availableCapacity(
            importantUsage: importantCapacity,
            regular: regularCapacity,
            fileSystem: fileSystemCapacity
        ) else {
            throw DiskBenchmarkFailure.unavailableCapacity
        }
        guard available >= configuration.requiredAvailableBytes else {
            throw DiskBenchmarkFailure.insufficientSpace(required: configuration.requiredAvailableBytes,
                                                         available: available)
        }
    }

    private func transferWrite(descriptor: Int32,
                               buffer: UnsafeMutableRawPointer,
                               passIndex: Int,
                               passOffset: UInt64,
                               totalBytes: UInt64,
                               cancellation: DiskBenchmarkCancellationToken,
                               progress: (DiskBenchmarkProgress) -> Void) throws -> UInt64 {
        var completed: UInt64 = 0
        var elapsedNanoseconds: UInt64 = 0
        var lastUpdate = DispatchTime.now().uptimeNanoseconds
        while completed < configuration.byteCount {
            try checkCancellation(cancellation)
            let count = min(UInt64(configuration.chunkSize), configuration.byteCount - completed)
            DiskBenchmarkSupport.applyPatternMarkers(
                to: buffer,
                byteCount: Int(count),
                passIndex: passIndex,
                chunkIndex: completed / UInt64(configuration.chunkSize)
            )
            var offset = 0
            while offset < Int(count) {
                let started = DispatchTime.now().uptimeNanoseconds
                let written = Darwin.write(descriptor,
                                           buffer.advanced(by: offset),
                                           Int(count) - offset)
                elapsedNanoseconds += DispatchTime.now().uptimeNanoseconds - started
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
                                    completed: passOffset + completed,
                                    passCompleted: completed,
                                    totalBytes: totalBytes,
                                    lastUpdate: &lastUpdate,
                                    progress: progress)
        }
        return elapsedNanoseconds
    }

    private func transferRead(descriptor: Int32,
                              expectedBuffer: UnsafeMutableRawPointer,
                              readBuffer: UnsafeMutableRawPointer,
                              passIndex: Int,
                              passOffset: UInt64,
                              totalBytes: UInt64,
                              cancellation: DiskBenchmarkCancellationToken,
                              progress: (DiskBenchmarkProgress) -> Void) throws -> UInt64 {
        var completed: UInt64 = 0
        var elapsedNanoseconds: UInt64 = 0
        var lastUpdate = DispatchTime.now().uptimeNanoseconds
        while completed < configuration.byteCount {
            try checkCancellation(cancellation)
            let count = min(UInt64(configuration.chunkSize), configuration.byteCount - completed)
            DiskBenchmarkSupport.applyPatternMarkers(
                to: expectedBuffer,
                byteCount: Int(count),
                passIndex: passIndex,
                chunkIndex: completed / UInt64(configuration.chunkSize)
            )
            var offset = 0
            while offset < Int(count) {
                let started = DispatchTime.now().uptimeNanoseconds
                let amount = Darwin.read(descriptor,
                                         readBuffer.advanced(by: offset),
                                         Int(count) - offset)
                elapsedNanoseconds += DispatchTime.now().uptimeNanoseconds - started
                if amount > 0 {
                    offset += amount
                } else if amount == -1, errno == EINTR {
                    continue
                } else {
                    throw DiskBenchmarkFailure.io(operation: "read", code: amount == 0 ? EIO : errno)
                }
            }
            guard DiskBenchmarkSupport.buffersMatch(expectedBuffer,
                                                    readBuffer,
                                                    byteCount: Int(count)) else {
                throw DiskBenchmarkFailure.verificationFailed
            }
            completed += count
            publishProgressIfNeeded(phase: .reading,
                                    completed: passOffset + completed,
                                    passCompleted: completed,
                                    totalBytes: totalBytes,
                                    lastUpdate: &lastUpdate,
                                    progress: progress)
        }
        return elapsedNanoseconds
    }

    private func publishProgressIfNeeded(phase: DiskBenchmarkPhase,
                                         completed: UInt64,
                                         passCompleted: UInt64,
                                         totalBytes: UInt64,
                                         lastUpdate: inout UInt64,
                                         progress: (DiskBenchmarkProgress) -> Void) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard passCompleted == configuration.byteCount || now - lastUpdate >= 100_000_000 else { return }
        lastUpdate = now
        progress(DiskBenchmarkProgress(phase: phase,
                                       completedBytes: completed,
                                       totalBytes: totalBytes))
    }

    private func synchronize(descriptor: Int32) throws {
        if Darwin.fcntl(descriptor, F_FULLFSYNC) == 0 { return }
        let fullSyncError = errno
        guard DiskBenchmarkSupport.shouldFallbackToFSync(afterFullSyncError: fullSyncError) else {
            throw DiskBenchmarkFailure.io(operation: "full sync", code: fullSyncError)
        }
        guard Darwin.fsync(descriptor) == 0 else { throw ioFailure("sync") }
    }

    private func fileSystemAvailableCapacity(at directory: URL) -> UInt64? {
        var fileSystem = statfs()
        guard statfs(directory.path, &fileSystem) == 0,
              let availableBlocks = nonnegativeUInt(fileSystem.f_bavail),
              let blockSize = nonnegativeUInt(fileSystem.f_bsize) else { return nil }
        let (capacity, overflow) = availableBlocks.multipliedReportingOverflow(by: blockSize)
        return overflow ? nil : capacity
    }

    private func nonnegativeUInt<Value: BinaryInteger>(_ value: Value?) -> UInt64? {
        guard let value, value >= 0 else { return nil }
        return UInt64(exactly: value)
    }

    private func checkCancellation(_ cancellation: DiskBenchmarkCancellationToken) throws {
        guard !cancellation.isCancelled else { throw DiskBenchmarkFailure.cancelled }
    }

    private func seconds(nanoseconds: UInt64) -> TimeInterval {
        TimeInterval(nanoseconds) / 1_000_000_000
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
