// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

struct ArchivePublisher {
    enum Attempt: Equatable {
        case success
        case destinationExists
        case unsupported
        case failed
    }

    typealias Operation = (URL, URL, CancellationToken) -> Attempt

    private let renameExclusive: Operation
    private let copyExclusive: Operation

    init() {
        renameExclusive = Self.systemRenameExclusive
        copyExclusive = { source, destination, token in
            Self.systemCopyExclusive(source, destination, token)
        }
    }

    init(renameExclusive: @escaping Operation, copyExclusive: Operation? = nil) {
        self.renameExclusive = renameExclusive
        self.copyExclusive = copyExclusive ?? { source, destination, token in
            Self.systemCopyExclusive(source, destination, token)
        }
    }

    func publish(_ stagedURL: URL, in directory: URL, baseName: String,
                 fileManager: FileManager, token: CancellationToken) throws -> URL {
        for _ in 1...10_000 {
            if token.isCancelled { throw ArchiveFailure.cancelled }
            let candidate = FileOutputSupport.uniqueOutputURL(in: directory,
                                                              baseName: baseName,
                                                              fileExtension: "zip",
                                                              fileManager: fileManager)
            switch renameExclusive(stagedURL, candidate, token) {
            case .success:
                if token.isCancelled {
                    try? fileManager.removeItem(at: candidate)
                    throw ArchiveFailure.cancelled
                }
                return candidate
            case .destinationExists:
                continue
            case .unsupported:
                let attempt = copyExclusive(stagedURL, candidate, token)
                if token.isCancelled {
                    if case .success = attempt { try? fileManager.removeItem(at: candidate) }
                    throw ArchiveFailure.cancelled
                }
                switch attempt {
                case .success:
                    return candidate
                case .destinationExists:
                    continue
                case .unsupported, .failed:
                    throw ArchiveFailure.cannotPublish
                }
            case .failed:
                throw ArchiveFailure.cannotPublish
            }
        }
        throw ArchiveFailure.cannotPublish
    }

    private static func systemRenameExclusive(_ sourceURL: URL,
                                              _ destinationURL: URL,
                                              _ token: CancellationToken) -> Attempt {
        guard !token.isCancelled else { return .failed }
        let result = sourceURL.withUnsafeFileSystemRepresentation { source in
            destinationURL.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return Int32(-1) }
                return renameatx_np(AT_FDCWD, source, AT_FDCWD, destination,
                                    UInt32(RENAME_EXCL))
            }
        }
        guard result != 0 else { return .success }
        return renameFailureAttempt(for: errno)
    }

    static func renameFailureAttempt(for errorNumber: Int32) -> Attempt {
        errorNumber == EEXIST ? .destinationExists : .unsupported
    }

    static func fallbackCopyFlags(_ flags: UInt32, hidden: Bool) -> UInt32 {
        hidden ? flags | UInt32(UF_HIDDEN) : flags & ~UInt32(UF_HIDDEN)
    }

    static func systemCopyExclusive(
        _ sourceURL: URL,
        _ destinationURL: URL,
        _ token: CancellationToken,
        readStatus: (Int32, UnsafeMutablePointer<stat>) -> Int32 = fstat,
        writeFlags: (Int32, UInt32) -> Int32 = fchflags
    ) -> Attempt {
        guard !token.isCancelled else { return .failed }
        let sourceDescriptor = sourceURL.withUnsafeFileSystemRepresentation { source in
            guard let source else { return Int32(-1) }
            return open(source, O_RDONLY | O_NOFOLLOW)
        }
        guard sourceDescriptor >= 0 else { return .failed }
        defer { close(sourceDescriptor) }

        let destinationDescriptor = destinationURL.withUnsafeFileSystemRepresentation { destination in
            guard let destination else { return Int32(-1) }
            return open(destination, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                        mode_t(S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH))
        }
        guard destinationDescriptor >= 0 else {
            return errno == EEXIST ? .destinationExists : .failed
        }

        var destinationIsOpen = true
        var completed = false
        defer {
            if destinationIsOpen { close(destinationDescriptor) }
            if !completed { try? FileManager.default.removeItem(at: destinationURL) }
        }

        var destinationStatus = stat()
        let destinationIsHidden = readStatus(destinationDescriptor, &destinationStatus) == 0
            && writeFlags(destinationDescriptor,
                          fallbackCopyFlags(destinationStatus.st_flags, hidden: true)) == 0

        var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while !token.isCancelled {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                read(sourceDescriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead == 0 { break }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                return .failed
            }

            var written = 0
            while written < bytesRead {
                if token.isCancelled { return .failed }
                let count = buffer.withUnsafeBytes { bytes in
                    write(destinationDescriptor,
                          bytes.baseAddress?.advanced(by: written),
                          bytesRead - written)
                }
                if count < 0 {
                    if errno == EINTR { continue }
                    return .failed
                }
                if count == 0 { return .failed }
                written += count
            }
        }
        guard !token.isCancelled else { return .failed }
        guard fsync(destinationDescriptor) == 0 else { return .failed }
        if destinationIsHidden {
            _ = writeFlags(destinationDescriptor, destinationStatus.st_flags)
        }
        guard close(destinationDescriptor) == 0 else {
            destinationIsOpen = false
            return .failed
        }
        destinationIsOpen = false

        completed = true
        try? FileManager.default.removeItem(at: sourceURL)
        return .success
    }
}

final class ArchiveOperationWorker {
    typealias CommandRunner = (String, [String], CancellationToken) -> BoundedProcessRunner.Result
    typealias StageDirectoryProvider = (URL) throws -> URL

    private let fileManager: FileManager
    private let stageDirectoryProvider: StageDirectoryProvider
    private let runCommand: CommandRunner
    private let publisher: ArchivePublisher

    init(fileManager: FileManager = .default,
         stageDirectoryProvider: StageDirectoryProvider? = nil,
         commandRunner: @escaping CommandRunner = { path, arguments, token in
             BoundedProcessRunner.run(path, arguments,
                                      timeout: nil,
                                      maxOutputBytes: 32_768,
                                      environment: ["LC_ALL": "C"],
                                      cancellationToken: token)
         },
         publisher: ArchivePublisher = ArchivePublisher()) {
        self.fileManager = fileManager
        self.stageDirectoryProvider = stageDirectoryProvider ?? { destinationDirectory in
            try fileManager.url(for: .itemReplacementDirectory,
                                in: .userDomainMask,
                                appropriateFor: destinationDirectory,
                                create: true)
        }
        runCommand = commandRunner
        self.publisher = publisher
    }

    func create(sources: [URL], destinationDirectory: URL, excludesDSStore: Bool,
                token: CancellationToken) -> Result<URL, ArchiveFailure> {
        guard !sources.isEmpty else { return .failure(.noInput) }
        guard sources.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return .failure(.sourceUnavailable)
        }
        if let duplicate = ArchiveSupport.duplicateTopLevelName(in: sources) {
            return .failure(.duplicateSourceName(duplicate))
        }

        let stageRoot: URL
        do {
            stageRoot = try stageDirectoryProvider(destinationDirectory)
        } catch {
            return .failure(.cannotPrepare)
        }
        guard ArchiveSupport.stageDirectoryIsOutsideSources(stageRoot, sources: sources) else {
            stageRoot.withUnsafeFileSystemRepresentation { path in
                if let path { _ = rmdir(path) }
            }
            return .failure(.cannotPrepare)
        }
        defer { try? fileManager.removeItem(at: stageRoot) }

        let stagedOutput = stageRoot.appendingPathComponent("Archive.zip")
        let result = runCommand("/usr/bin/tar",
                                ArchiveSupport.createArguments(sources: sources,
                                                               stagedOutput: stagedOutput,
                                                               excludesDSStore: excludesDSStore),
                                token)
        if token.isCancelled { return .failure(.cancelled) }
        guard result.status == 0, fileManager.fileExists(atPath: stagedOutput.path) else {
            return .failure(.commandFailed(ArchiveSupport.boundedFailureMessage(result.output)))
        }

        do {
            return .success(try publisher.publish(
                stagedOutput,
                in: destinationDirectory,
                baseName: ArchiveSupport.archiveBaseName(for: sources),
                fileManager: fileManager,
                token: token))
        } catch let failure as ArchiveFailure {
            return .failure(failure)
        } catch {
            return .failure(.cannotPublish)
        }
    }
}

final class ArchiveService: ObservableObject {
    static let shared = ArchiveService()

    @Published private(set) var state: ArchiveOperationState = .idle

    private let queue = DispatchQueue(label: "com.vorssaint.utils.archive", qos: .userInitiated)
    private let lock = NSLock()
    private let worker: ArchiveOperationWorker
    private var operationID: UUID?
    private var token: CancellationToken?

    init(worker: ArchiveOperationWorker = ArchiveOperationWorker()) {
        self.worker = worker
    }

    func reset() {
        cancel()
        setStateOnMain(.idle)
    }

    func create(sources: [URL], destinationDirectory: URL, excludesDSStore: Bool) {
        let id = UUID()
        let token = CancellationToken()
        lock.lock()
        self.token?.cancel()
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
            if current {
                self.state = state
            } else if case let .completed(outputURL) = state {
                // A cancellation or replacement can win after publication but
                // before this main-queue update. The stale operation still owns
                // its collision-free result, so discard it as promised.
                try? FileManager.default.removeItem(at: outputURL)
            }
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
