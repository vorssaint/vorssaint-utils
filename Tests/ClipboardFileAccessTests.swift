// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

enum ClipboardFileAccessTests {
    static func run(_ suite: TestSuite) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vorss-file-history-\(UUID())")
        defer {
            ClipboardHistoryFileResolver.prune(keepingPaths: [])
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try retainedFiles(suite, in: directory)
            try boundsAndBookmarks(suite, in: directory)
            try scopeLifetime(suite, in: directory)
            try ordinaryAndSpecialTargets(suite, in: directory)
        } catch {
            suite.expect(false, "clipboard file fixtures: \(error)")
        }
    }

    private static func persisted(_ files: [ClipboardCapturedFile], in directory: URL,
                                  byteLimit: Int = ClipboardFileStore.maxStoredBytes,
                                  previous: [ClipboardHistoryFileReference] = []) -> ClipboardFileStore.StoredBatch? {
        var batch: ClipboardFileStore.StoredBatch?
        ClipboardFileStore.persist(files, previous: previous, directory: directory, byteLimit: byteLimit) { batch = $0 }
        let deadline = Date().addingTimeInterval(5)
        while batch == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return batch
    }

    private static func retainedFiles(_ suite: TestSuite, in directory: URL) throws {
        let fm = FileManager.default
        let source = directory.appendingPathComponent("Document from chat.pdf")
        let second = directory.appendingPathComponent("second document.txt")
        let bytes = Data("%PDF-1.4\nexact original bytes\n".utf8)
        let text = Data("full original document\n".utf8)
        try bytes.write(to: source)
        try text.write(to: second)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.writeObjects([source as NSURL, second as NSURL])
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let captures = ClipboardHistoryFileCapture.capture(urls)
        suite.expect(captures.map(\.snapshot) == [bytes, text]
                     && captures.map(\.reference.path) == [source.path, second.path],
                     "native clipboard URLs capture each regular file's exact bytes and order before access expires")
        suite.expect(captures.allSatisfy { $0.reference.bookmark != nil },
                     "copied files retain bookmarks as well as their original native URLs")
        ClipboardHistoryFileResolver.remember(captures)
        let cache = directory.appendingPathComponent("retained")
        guard let batch = persisted(captures, in: cache) else {
            suite.expect(false, "file capture storage completes")
            return
        }
        let references = batch.references
        let saved = ClipboardHistoryEntry(text: "", kind: .files, filePaths: [source.path, second.path],
                                          fileReferences: references)
        let cached = references.compactMap { ClipboardFileStore.snapshotURL(for: $0, directory: cache) }
        ClipboardFileStore.cleanup(keeping: [], directory: cache)
        suite.expect(cached.count == 2 && cached.allSatisfy { fm.fileExists(atPath: $0.path) },
                     "pending file storage survives cleanup before history owns its references")
        batch.finish(keeping: true)
        try fm.removeItem(at: source)
        try fm.removeItem(at: second)
        ClipboardHistoryFileResolver.prune(keepingPaths: [])
        var leases = ClipboardHistoryFileResolver.resolveAll(saved, storeDirectory: cache)
        let resolvedBytes = try leases.map { try Data(contentsOf: $0.url) }
        suite.expect(leases.map { $0.url.lastPathComponent } == [source.lastPathComponent, second.lastPathComponent]
                     && resolvedBytes == [bytes, text],
                     "expired source files resolve to saved originals with exact names, types and bytes")
        let roundTrip = try JSONDecoder().decode(ClipboardHistoryEntry.self, from: JSONEncoder().encode(saved))
        suite.expect(roundTrip.fileReferences == saved.fileReferences,
                     "file access metadata survives history persistence and app relaunch")
        do {
            let drag = ClipboardHistoryDrag.prepare(for: roundTrip, imageDirectory: nil, fileDirectory: cache)
            board.clearContents()
            suite.expect(board.writeObjects(drag.writers) && drag.fileLeases.count == 2,
                         "a restored file entry prepares native file writers with access held through its drag")
            let received = board.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            let receivedBytes = try received.map { try Data(contentsOf: $0) }
            suite.expect(received.map(\.lastPathComponent) == [source.lastPathComponent, second.lastPathComponent]
                         && receivedBytes == [bytes, text],
                         "native PDF and multi-file drops retain exact filenames, extensions and bytes after capture, restart and source deletion")
        }
        let destination = directory.appendingPathComponent("drop.pdf")
        if let lease = leases.first { try fm.copyItem(at: lease.url, to: destination) }
        suite.expect((try? Data(contentsOf: destination)) == bytes,
                     "a resolved copied PDF can be transferred after its source app removes the original")
        if let file = cached.first {
            let permissions = try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            suite.expect(permissions?.intValue == 0o600, "retained document contents remain owner-only")
        }
        ClipboardFileStore.cleanup(keeping: [], directory: cache)
        suite.expect(cached.allSatisfy { fm.fileExists(atPath: $0.path) },
                     "a preview or native drag lease protects its cached files while history is cleared")
        leases = []
        ClipboardFileStore.cleanup(keeping: [], directory: cache)
        suite.expect(cached.allSatisfy { !fm.fileExists(atPath: $0.path) },
                     "cleared history releases cached documents once all consumers finish")

        let legacy = Data(#"{"text":"","kind":"files","filePaths":["/tmp/legacy.pdf"]}"#.utf8)
        suite.expect(try JSONDecoder().decode(ClipboardHistoryEntry.self, from: legacy).fileReferences.isEmpty,
                     "history written before durable file access remains readable")
    }

    private static func boundsAndBookmarks(_ suite: TestSuite, in directory: URL) throws {
        let fm = FileManager.default
        let first = directory.appendingPathComponent("first.bin")
        let second = directory.appendingPathComponent("second.bin")
        let third = directory.appendingPathComponent("third.bin")
        let folder = directory.appendingPathComponent("copied folder", isDirectory: true)
        for file in [first, second, third] { try Data([1, 2, 3, 4]).write(to: file) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("private child".utf8).write(to: folder.appendingPathComponent("child.txt"))
        let bounded = ClipboardHistoryFileCapture.capture([first, second, third, folder],
            snapshotByteLimit: 4, totalSnapshotByteLimit: 8)
        suite.expect(bounded.map { $0.snapshot?.count } == [4, 4, nil, nil],
                     "file capture bounds aggregate bytes and never recursively snapshots a copied directory")
        let oversized = ClipboardHistoryFileCapture.capture([first], snapshotByteLimit: 3)
        suite.expect(oversized[0].snapshot == nil && oversized[0].reference.bookmark != nil,
                     "a file over the snapshot limit preserves access without backing up its contents")
        let cache = directory.appendingPathComponent("quota")
        guard let batch = persisted(Array(bounded.prefix(2)), in: cache, byteLimit: 4) else {
            suite.expect(false, "bounded cache storage completes")
            return
        }
        suite.expect(batch.references.filter { $0.snapshotDirectory != nil }.count == 1,
                     "the private file cache has a separate total storage bound")
        let reference = batch.references[0]
        batch.finish(keeping: true)
        if let again = persisted(Array(bounded.prefix(1)), in: cache, byteLimit: 4, previous: [reference]) {
            suite.expect(again.references[0].snapshotDirectory == reference.snapshotDirectory,
                         "recopying identical file bytes reuses their private storage even at quota")
            again.finish(keeping: true)
        } else { suite.expect(false, "reusing a file snapshot completes") }

        let moved = directory.appendingPathComponent("renamed.bin")
        try fm.moveItem(at: first, to: moved)
        let bookmarked = ClipboardHistoryEntry(text: "", kind: .files, filePaths: [first.path],
                                               fileReferences: [oversized[0].reference])
        let resolved = ClipboardHistoryFileResolver.resolve(bookmarked, storeDirectory: nil)
        suite.expect(resolved?.url.standardizedFileURL == moved.standardizedFileURL,
                     "a durable bookmark follows an original that moved without needing a cached backup")
        let legacy = ClipboardHistoryEntry(text: "", kind: .files, filePaths: [second.path, folder.path])
        suite.expect(ClipboardHistoryFileResolver.resolveAll(legacy, storeDirectory: nil).map(\.url) == [second, folder],
                     "legacy files and directories remain usable at their accessible original paths")
        let malformed = ClipboardHistoryFileReference(path: first.path, bookmark: nil, snapshotDirectory: "../quota")
        suite.expect(ClipboardFileStore.snapshotURL(for: malformed, directory: cache) == nil,
                     "persisted snapshot references cannot escape the private file store")
    }

    private static func scopeLifetime(_ suite: TestSuite, in directory: URL) throws {
        let file = directory.appendingPathComponent("scope.txt")
        try Data("scope".utf8).write(to: file)
        var starts = 0, stops = 0
        var lease: ClipboardHistoryFileLease? = ClipboardHistoryFileLease.open(file,
            startAccessing: { _ in starts += 1; return true }, stopAccessing: { _ in stops += 1 })
        suite.expect(lease?.url == file && starts == 1 && stops == 0,
                     "a consumer lease starts access and keeps it active while its URL is in use")
        lease = nil
        suite.expect(stops == 1, "finishing the consumer balances its security-scoped access exactly once")
        let missing = directory.appendingPathComponent("unavailable.txt")
        let rejected = ClipboardHistoryFileLease.open(missing,
            startAccessing: { _ in starts += 1; return true }, stopAccessing: { _ in stops += 1 })
        suite.expect(rejected == nil && starts == 2 && stops == 2,
                     "failed file access also relinquishes the grant without leaking a lease")
    }

    private static func ordinaryAndSpecialTargets(_ suite: TestSuite, in directory: URL) throws {
        let file = directory.appendingPathComponent("linked.txt")
        let folder = directory.appendingPathComponent("linked folder", isDirectory: true)
        let fileLink = directory.appendingPathComponent("file link")
        let folderLink = directory.appendingPathComponent("folder link")
        try Data("linked document".utf8).write(to: file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: fileLink, withDestinationURL: file)
        try FileManager.default.createSymbolicLink(at: folderLink, withDestinationURL: folder)
        let fileLease = ClipboardHistoryFileLease.open(fileLink)
        let folderLease = ClipboardHistoryFileLease.open(folderLink)
        suite.expect(fileLease?.url == fileLink && folderLease?.url == folderLink,
                     "ordinary file and directory symlinks keep their original URLs instead of exporting their targets")
        suite.expect(ClipboardHistoryFileCapture.capture([fileLink, folderLink]).allSatisfy { $0.snapshot == nil },
                     "symlinks are never replaced with snapshots of their targets")
        suite.expect(ClipboardHistoryFileLease.open(URL(fileURLWithPath: "/dev/null")) == nil,
                     "device files cannot become file preview or drag leases")

        let fifo = directory.appendingPathComponent("copied pipe")
        guard mkfifo(fifo.path, 0o600) == 0 else {
            suite.expect(false, "a named pipe fixture can be created")
            return
        }
        final class Probe {
            let done = DispatchSemaphore(value: 0)
            var rejected = false
        }
        let probe = Probe()
        DispatchQueue.global(qos: .userInitiated).async {
            probe.rejected = ClipboardHistoryFileLease.open(fifo) == nil
                && ClipboardHistoryFileCapture.capture([fifo]).allSatisfy { $0.snapshot == nil }
            probe.done.signal()
        }
        let finished = probe.done.wait(timeout: .now() + 1) == .success
        suite.expect(finished && probe.rejected,
                     "a copied FIFO is rejected immediately without blocking capture, preview or dragging")
    }
}
