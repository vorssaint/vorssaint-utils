// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Darwin
import Foundation

struct ArchivePublisher {
    enum Attempt {
        case success
        case destinationExists
        case unsupported
        case failed
    }

    typealias Operation = (URL, URL) -> Attempt

    private let renameExclusive: Operation
    private let copyExclusive: Operation

    init() {
        renameExclusive = Self.systemRenameExclusive
        copyExclusive = Self.systemCopyExclusive
    }

    init(renameExclusive: @escaping Operation, copyExclusive: Operation? = nil) {
        self.renameExclusive = renameExclusive
        self.copyExclusive = copyExclusive ?? Self.systemCopyExclusive
    }

    func publish(_ stagedURL: URL, in directory: URL, baseName: String,
                 fileManager: FileManager) throws -> URL {
        for _ in 1...10_000 {
            let candidate = FileOutputSupport.uniqueOutputURL(in: directory,
                                                              baseName: baseName,
                                                              fileExtension: "zip",
                                                              fileManager: fileManager)
            switch renameExclusive(stagedURL, candidate) {
            case .success:
                return candidate
            case .destinationExists:
                continue
            case .unsupported:
                switch copyExclusive(stagedURL, candidate) {
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
                                              _ destinationURL: URL) -> Attempt {
        let result = sourceURL.withUnsafeFileSystemRepresentation { source in
            destinationURL.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return Int32(-1) }
                return renameatx_np(AT_FDCWD, source, AT_FDCWD, destination,
                                    UInt32(RENAME_EXCL))
            }
        }
        guard result != 0 else { return .success }
        switch errno {
        case EEXIST: return .destinationExists
        case ENOTSUP, EXDEV: return .unsupported
        default: return .failed
        }
    }

    private static func systemCopyExclusive(_ sourceURL: URL,
                                            _ destinationURL: URL) -> Attempt {
        let destinationExisted = FileManager.default.fileExists(atPath: destinationURL.path)
        let result = sourceURL.withUnsafeFileSystemRepresentation { source in
            destinationURL.withUnsafeFileSystemRepresentation { destination in
                guard let source, let destination else { return Int32(-1) }
                return copyfile(source, destination, nil,
                                copyfile_flags_t(COPYFILE_DATA | COPYFILE_EXCL
                                    | COPYFILE_MOVE | COPYFILE_NOFOLLOW))
            }
        }
        guard result != 0 else { return .success }
        let failure = errno
        if failure == EEXIST { return .destinationExists }
        if !destinationExisted { try? FileManager.default.removeItem(at: destinationURL) }
        return .failed
    }
}

final class ArchiveOperationWorker {
    typealias CommandRunner = (String, [String], CancellationToken) -> BoundedProcessRunner.Result

    private let fileManager: FileManager
    private let runCommand: CommandRunner
    private let publisher: ArchivePublisher

    init(fileManager: FileManager = .default,
         commandRunner: @escaping CommandRunner = { path, arguments, token in
             BoundedProcessRunner.run(path, arguments,
                                      timeout: nil,
                                      maxOutputBytes: 32_768,
                                      environment: ["LC_ALL": "C"],
                                      cancellationToken: token)
         },
         publisher: ArchivePublisher = ArchivePublisher()) {
        self.fileManager = fileManager
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
            stageRoot = try fileManager.url(for: .itemReplacementDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: destinationDirectory,
                                            create: true)
        } catch {
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
                fileManager: fileManager))
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
