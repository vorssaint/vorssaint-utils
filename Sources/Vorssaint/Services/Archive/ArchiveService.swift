// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

final class ArchiveCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

struct ArchiveCommandResult {
    let status: Int32
    let output: Data
}

protocol ArchiveCommandRunning: AnyObject {
    func run(_ path: String, arguments: [String],
             token: ArchiveCancellationToken) -> ArchiveCommandResult
    func cancel()
}

private final class ArchiveProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let available = max(0, 32_768 - data.count)
        if available > 0 { data.append(chunk.prefix(available)) }
    }

    func value() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

final class SystemArchiveCommandRunner: ArchiveCommandRunning {
    private let lock = NSLock()
    private var activeProcess: Process?

    func run(_ path: String, arguments: [String],
             token: ArchiveCancellationToken) -> ArchiveCommandResult {
        guard !token.isCancelled else { return ArchiveCommandResult(status: -1, output: Data()) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let output = ArchiveProcessOutput()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { output.append(chunk) }
        }

        lock.lock()
        activeProcess = process
        guard !token.isCancelled else {
            activeProcess = nil
            lock.unlock()
            pipe.fileHandleForReading.readabilityHandler = nil
            return ArchiveCommandResult(status: -1, output: Data())
        }

        do {
            try process.run()
        } catch {
            activeProcess = nil
            lock.unlock()
            pipe.fileHandleForReading.readabilityHandler = nil
            return ArchiveCommandResult(status: -1, output: Data())
        }
        lock.unlock()

        _ = finished.wait(timeout: .distantFuture)
        pipe.fileHandleForReading.readabilityHandler = nil
        let tail = pipe.fileHandleForReading.readDataToEndOfFile()
        if !tail.isEmpty { output.append(tail) }
        clear(process)
        return ArchiveCommandResult(status: process.terminationStatus, output: output.value())
    }

    func cancel() {
        lock.lock()
        let process = activeProcess
        lock.unlock()
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func clear(_ process: Process) {
        lock.lock()
        if activeProcess === process { activeProcess = nil }
        lock.unlock()
    }
}

final class ArchiveOperationWorker {
    private let fileManager: FileManager
    private let runner: ArchiveCommandRunning

    init(fileManager: FileManager = .default,
         runner: ArchiveCommandRunning = SystemArchiveCommandRunner()) {
        self.fileManager = fileManager
        self.runner = runner
    }

    func cancel() { runner.cancel() }

    func create(sources: [URL], destinationDirectory: URL, excludesDSStore: Bool,
                token: ArchiveCancellationToken) -> Result<URL, ArchiveFailure> {
        guard !sources.isEmpty,
              sources.allSatisfy({ fileManager.fileExists(atPath: $0.path) })
        else { return .failure(.noInput) }
        if let duplicate = ArchiveSupport.duplicateTopLevelName(in: sources) {
            return .failure(.duplicateSourceName(duplicate))
        }

        let stageRoot: URL
        do {
            stageRoot = try fileManager.url(for: .itemReplacementDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: destinationDirectory,
                                            create: true)
        } catch {
            return .failure(.cannotPrepare)
        }
        defer { try? fileManager.removeItem(at: stageRoot) }

        let stagedOutput = stageRoot.appendingPathComponent("Archive.zip")
        let result = runner.run("/usr/bin/tar",
                                arguments: ArchiveSupport.createArguments(
                                    sources: sources,
                                    stagedOutput: stagedOutput,
                                    excludesDSStore: excludesDSStore),
                                token: token)
        if token.isCancelled { return .failure(.cancelled) }
        guard result.status == 0, fileManager.fileExists(atPath: stagedOutput.path) else {
            return .failure(.commandFailed(ArchiveSupport.boundedFailureMessage(result.output)))
        }

        do {
            return .success(try publish(stagedOutput,
                                        in: destinationDirectory,
                                        baseName: ArchiveSupport.archiveBaseName(for: sources)))
        } catch {
            return .failure(.cannotPublish)
        }
    }

    private func publish(_ stagedURL: URL, in directory: URL, baseName: String) throws -> URL {
        for _ in 1...10_000 {
            let candidate = FileOutputSupport.uniqueOutputURL(in: directory,
                                                              baseName: baseName,
                                                              fileExtension: "zip",
                                                              fileManager: fileManager)
            let result = stagedURL.withUnsafeFileSystemRepresentation { source in
                candidate.withUnsafeFileSystemRepresentation { destination in
                    guard let source, let destination else { return Int32(-1) }
                    return renameatx_np(AT_FDCWD, source, AT_FDCWD, destination,
                                        UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return candidate }
            if errno != EEXIST { throw ArchiveFailure.cannotPublish }
        }
        throw ArchiveFailure.cannotPublish
    }
}

final class ArchiveService: ObservableObject {
    static let shared = ArchiveService()

    @Published private(set) var state: ArchiveOperationState = .idle

    private let queue = DispatchQueue(label: "com.vorssaint.utils.archive", qos: .userInitiated)
    private let lock = NSLock()
    private let worker: ArchiveOperationWorker
    private var operationID: UUID?
    private var token: ArchiveCancellationToken?

    init(worker: ArchiveOperationWorker = ArchiveOperationWorker()) {
        self.worker = worker
    }

    func reset() {
        cancel()
        setStateOnMain(.idle)
    }

    func create(sources: [URL], destinationDirectory: URL, excludesDSStore: Bool) {
        let id = UUID()
        let token = ArchiveCancellationToken()
        lock.lock()
        self.token?.cancel()
        worker.cancel()
        operationID = id
        self.token = token
        lock.unlock()
        state = .running

        queue.async { [weak self, worker] in
            let result = worker.create(sources: sources,
                                       destinationDirectory: destinationDirectory,
                                       excludesDSStore: excludesDSStore,
                                       token: token)
            switch result {
            case let .success(url): self?.publish(.completed(url), id: id)
            case .failure(.cancelled): self?.publish(.cancelled, id: id)
            case let .failure(failure): self?.publish(.failed(failure), id: id)
            }
        }
    }

    func cancel() {
        lock.lock()
        token?.cancel()
        operationID = nil
        token = nil
        lock.unlock()
        worker.cancel()
        setStateOnMain(.cancelled)
    }

    private func publish(_ state: ArchiveOperationState, id: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.operationID == id
            if current, case .running = state {} else if current {
                self.operationID = nil
                self.token = nil
            }
            self.lock.unlock()
            if current { self.state = state }
        }
    }

    private func setStateOnMain(_ state: ArchiveOperationState) {
        if Thread.isMainThread {
            self.state = state
        } else {
            DispatchQueue.main.async { [weak self] in self?.state = state }
        }
    }
}
