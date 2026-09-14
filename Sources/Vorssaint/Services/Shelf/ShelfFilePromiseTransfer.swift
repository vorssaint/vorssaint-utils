// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Copies each file inside AppKit's coordinated reader, before exposing it to
/// the shelf. Cancellation stops our copies, not the sending application's
/// write; its eventual completion still cleans the private incoming directory.
final class ShelfFilePromiseTransfer {
    struct Result {
        let urls: [URL]
        let failed: Bool
    }

    private let incomingDirectory: URL
    private let storeDirectory: URL
    private let maximumFiles: Int
    private let queue = OperationQueue()
    private let lock = NSLock()
    private var cancelled = false
    private var finished = false
    private var expectedCount: Int?
    private var expectedNames: [[String]] = []
    private var receivedCount = 0
    private var failed = false
    private var copies: [(receiver: Int, url: URL)] = []
    private let completion: (Result) -> Void

    init?(temporaryDirectory: URL, storeDirectory: URL, maximumFiles: Int = Int.max,
          completion: @escaping (Result) -> Void) {
        let incoming = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: incoming, container: temporaryDirectory),
              PrivateFileStore.createDirectory(at: storeDirectory) else {
            try? FileManager.default.removeItem(at: incoming)
            return nil
        }
        self.incomingDirectory = incoming
        self.storeDirectory = storeDirectory
        self.maximumFiles = maximumFiles
        self.completion = completion
        queue.name = "com.vorssaint.utils.shelf-file-promises"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
    }

    /// Must run within the drag destination callback. In particular, fileTypes
    /// is not a file count: legacy sources may list a type only once for a batch.
    @discardableResult
    func receive(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        var expected = 0
        var names: [[String]] = []
        for (index, receiver) in receivers.enumerated() {
            receiver.receivePromisedFiles(atDestination: incomingDirectory,
                                          options: [:], operationQueue: queue) { [self] url, error in
                var copy: URL?
                if error == nil, isActive {
                    copy = try? copyReceivedFile(url)
                }
                record(copy, receiver: index, failed: error != nil || copy == nil)
            }
            // AppKit supplies the actual names after calling in the promise.
            // A failed request can have no names, but still reports its error.
            let receivedNames = receiver.fileNames
            names.append(receivedNames)
            expected += max(1, receivedNames.count)
        }
        if expected > maximumFiles { cancel() }
        lock.lock()
        expectedCount = expected
        expectedNames = names
        lock.unlock()
        finishIfReady()
        return expected <= maximumFiles
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let abandoned = copies.map(\.url)
        copies.removeAll()
        lock.unlock()
        queue.addOperation { [storeDirectory] in
            Self.discard(abandoned, in: storeDirectory)
        }
    }

    private var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !cancelled && !finished
    }

    private func record(_ url: URL?, receiver: Int, failed: Bool) {
        lock.lock()
        receivedCount += 1
        let discard = cancelled || finished
        if let url, !discard { copies.append((receiver, url)) }
        self.failed = self.failed || failed
        lock.unlock()
        if let url, discard { Self.discard([url], in: storeDirectory) }
        finishIfReady()
    }

    private func finishIfReady() {
        lock.lock()
        guard !finished, let expectedCount, receivedCount >= expectedCount else {
            lock.unlock()
            return
        }
        finished = true
        let shouldDeliver = !cancelled
        var used = [Int: Set<Int>]()
        var ordered: [(receiver: Int, order: Int, url: URL)] = []
        for (offset, copy) in copies.enumerated() {
            let names = expectedNames[copy.receiver]
            let index = names.indices.first {
                names[$0] == copy.url.lastPathComponent && !(used[copy.receiver]?.contains($0) ?? false)
            }
            var order = names.count + offset
            if let index {
                used[copy.receiver, default: []].insert(index)
                order = index
            }
            ordered.append((copy.receiver, order, copy.url))
        }
        ordered.sort {
            $0.receiver == $1.receiver ? $0.order < $1.order : $0.receiver < $1.receiver
        }
        let urls = ordered.map(\.url)
        copies.removeAll()
        let result = Result(urls: urls, failed: failed)
        lock.unlock()
        // Callbacks already in this queue finish before its cleanup operation.
        queue.addOperation { [incomingDirectory] in
            try? FileManager.default.removeItem(at: incomingDirectory)
        }
        if shouldDeliver {
            DispatchQueue.main.async { [self] in
                lock.lock()
                let abandoned = cancelled
                lock.unlock()
                if abandoned {
                    Self.discard(result.urls, in: storeDirectory)
                } else {
                    completion(result)
                }
            }
        } else {
            Self.discard(urls, in: storeDirectory)
        }
    }

    private func copyReceivedFile(_ url: URL) throws -> URL {
        let manager = FileManager.default
        let source = url.standardizedFileURL
        let incoming = incomingDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = source.resolvingSymlinksInPath().path
        guard source.isFileURL, resolved.hasPrefix(incoming + "/"),
              source.lastPathComponent != ".", source.lastPathComponent != "..",
              !source.lastPathComponent.isEmpty,
              try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        // An owner-only parent preserves original names and separates equal
        // names from different promises, including callbacks in the same drop.
        let directory = storeDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard PrivateFileStore.createDirectory(at: directory) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try manager.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    /// Only removes the private, UUID-named parent we created for this file.
    /// Never follows a caller-supplied path out of the shelf store.
    static func discard(_ urls: [URL], in storeDirectory: URL) {
        let root = storeDirectory.standardizedFileURL.path
        for url in urls {
            let parent = url.standardizedFileURL.deletingLastPathComponent()
            guard parent.deletingLastPathComponent().path == root,
                  UUID(uuidString: parent.lastPathComponent) != nil else { continue }
            try? FileManager.default.removeItem(at: parent)
        }
    }
}
