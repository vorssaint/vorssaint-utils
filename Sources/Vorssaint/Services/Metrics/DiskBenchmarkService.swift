// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

internal enum DiskBenchmarkState: Equatable {
    case idle
    case running(diskID: String, mode: DiskBenchmarkMode, progress: DiskBenchmarkProgress)
    case completed(DiskBenchmarkResult)
    case failed(diskID: String, failure: DiskBenchmarkFailure)
}

internal final class DiskBenchmarkService: ObservableObject {
    internal static let shared = DiskBenchmarkService()

    @Published internal private(set) var state: DiskBenchmarkState = .idle

    private let queue = DispatchQueue(label: "com.vorssaint.disk-benchmark", qos: .userInitiated)
    private let lock = NSLock()
    private let store: DiskBenchmarkResultStore
    private let configurationForMode: (DiskBenchmarkMode) -> DiskBenchmarkRunConfiguration
    private let directoryForDisk: (DiskDeviceReading) -> URL
    private var operationID: UUID?
    private var activeDiskID: String?
    private var cancellation: DiskBenchmarkCancellationToken?

    internal init(
        store: DiskBenchmarkResultStore = DiskBenchmarkResultStore(),
        configurationForMode: @escaping (DiskBenchmarkMode) -> DiskBenchmarkRunConfiguration = {
            DiskBenchmarkRunConfiguration(mode: $0)
        },
        directoryForDisk: @escaping (DiskDeviceReading) -> URL = { disk in
            disk.mountPath == "/"
                ? FileManager.default.temporaryDirectory
                : URL(fileURLWithPath: disk.mountPath, isDirectory: true)
        }
    ) {
        self.store = store
        self.configurationForMode = configurationForMode
        self.directoryForDisk = directoryForDisk
    }

    internal var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return operationID != nil
    }

    internal func isRunning(on disk: DiskDeviceReading) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return operationID != nil && activeDiskID == disk.id
    }

    internal func lastResult(for disk: DiskDeviceReading) -> DiskBenchmarkResult? {
        store.result(volumeUUID: disk.volumeUUID, sessionDiskID: disk.id)
    }

    internal func start(disk: DiskDeviceReading, mode: DiskBenchmarkMode) {
        guard !disk.isBenchmarkReadOnly else {
            setState(.failed(diskID: disk.id, failure: .readOnly))
            return
        }

        let directory = directoryForDisk(disk)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            setState(.failed(diskID: disk.id, failure: .targetUnavailable))
            return
        }
        guard disk.bsdName != nil || disk.wholeDisk != nil,
              let directoryIdentifier = DiskBenchmarkSupport.bsdIdentifier(at: directory) else {
            setState(.failed(diskID: disk.id, failure: .volumeIdentityUnavailable))
            return
        }
        guard DiskBenchmarkSupport.directoryBelongsToSelectedVolume(
            directoryIdentifier: directoryIdentifier,
            volumeIdentifier: disk.bsdName,
            fallbackWholeDisk: disk.wholeDisk
        ) else {
            setState(.failed(diskID: disk.id, failure: .volumeMismatch))
            return
        }
        if let values = try? directory.resourceValues(forKeys: [.volumeIsReadOnlyKey]),
           values.volumeIsReadOnly == true {
            setState(.failed(diskID: disk.id, failure: .readOnly))
            return
        }

        let id = UUID()
        let token = DiskBenchmarkCancellationToken()
        lock.lock()
        guard operationID == nil else {
            lock.unlock()
            return
        }
        operationID = id
        activeDiskID = disk.id
        cancellation = token
        lock.unlock()

        let configuration = configurationForMode(mode)
        let passCount = UInt64(max(1, configuration.passCount))
        let (configuredTotalBytes, totalOverflow) = configuration.byteCount
            .multipliedReportingOverflow(by: passCount)
        let totalBytes = totalOverflow ? configuration.byteCount : configuredTotalBytes
        setState(.running(diskID: disk.id,
                          mode: mode,
                          progress: DiskBenchmarkProgress(phase: .preparing,
                                                          completedBytes: 0,
                                                          totalBytes: totalBytes)))
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let measurement = try DiskBenchmarkRunner(configuration: configuration).run(
                    in: directory,
                    cancellation: token
                ) { [weak self] progress in
                    self?.publishProgress(progress, diskID: disk.id, mode: mode, operationID: id)
                }
                let result = DiskBenchmarkResult(id: UUID(),
                                                 volumeUUID: disk.volumeUUID,
                                                 sessionDiskID: disk.id,
                                                 diskName: disk.name,
                                                 fileSystem: disk.fileSystem,
                                                 mode: mode,
                                                 readBytesPerSecond: measurement.readBytesPerSecond,
                                                 writeBytesPerSecond: measurement.writeBytesPerSecond,
                                                 measuredAt: Date())
                self.finish(result: result, operationID: id, cancellation: token)
            } catch let failure as DiskBenchmarkFailure {
                self.fail(failure, diskID: disk.id, operationID: id)
            } catch {
                self.fail(.io(operation: "benchmark", code: 0),
                          diskID: disk.id,
                          operationID: id)
            }
        }
    }

    internal func cancel() {
        lock.lock()
        guard operationID != nil else {
            lock.unlock()
            return
        }
        cancellation?.cancel()
        operationID = nil
        activeDiskID = nil
        cancellation = nil
        lock.unlock()
        setState(.idle)
    }

    private func publishProgress(_ progress: DiskBenchmarkProgress,
                                 diskID: String,
                                 mode: DiskBenchmarkMode,
                                 operationID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(operationID) else { return }
            self.state = .running(diskID: diskID, mode: mode, progress: progress)
        }
    }

    private func finish(result: DiskBenchmarkResult,
                        operationID: UUID,
                        cancellation token: DiskBenchmarkCancellationToken) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.operationID == operationID, !token.isCancelled else {
                self.lock.unlock()
                return
            }
            self.operationID = nil
            self.activeDiskID = nil
            self.cancellation = nil
            self.lock.unlock()
            self.store.save(result)
            self.state = .completed(result)
        }
    }

    private func fail(_ failure: DiskBenchmarkFailure, diskID: String, operationID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.operationID == operationID else {
                self.lock.unlock()
                return
            }
            self.operationID = nil
            self.activeDiskID = nil
            self.cancellation = nil
            self.lock.unlock()
            self.state = .failed(diskID: diskID, failure: failure)
        }
    }

    private func isCurrent(_ operationID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return self.operationID == operationID
    }

    private func setState(_ newState: DiskBenchmarkState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { [weak self] in self?.state = newState }
        }
    }
}
