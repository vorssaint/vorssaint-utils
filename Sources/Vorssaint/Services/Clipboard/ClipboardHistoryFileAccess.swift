// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Keep this object for the full preview, thumbnail request or drag session.
/// Recreating its URL from a path would discard the original security scope.
final class ClipboardHistoryFileLease {
    let url: URL
    private let scoped: Bool
    private let stopAccessing: (URL) -> Void
    private let onRelease: (() -> Void)?

    private init(url: URL, scoped: Bool, stopAccessing: @escaping (URL) -> Void, onRelease: (() -> Void)?) {
        self.url = url
        self.scoped = scoped
        self.stopAccessing = stopAccessing
        self.onRelease = onRelease
    }

    static func open(_ url: URL,
                     startAccessing: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
                     stopAccessing: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() },
                     onRelease: (() -> Void)? = nil) -> ClipboardHistoryFileLease? {
        guard url.isFileURL else { return nil }
        let scoped = startAccessing(url)
        // FileHandle can block indefinitely on a FIFO or device. Inspect the
        // resolved target first, while keeping the original scoped URL for
        // export (a symlink itself must remain a symlink when dragged).
        let target = url.resolvingSymlinksInPath()
        let values = try? target.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
        let readable: Bool
        if values?.isDirectory == true {
            readable = FileManager.default.isReadableFile(atPath: url.path)
        } else if values?.isRegularFile == true, let handle = try? FileHandle(forReadingFrom: url) {
            try? handle.close()
            readable = true
        } else { readable = false }
        guard readable else {
            if scoped { stopAccessing(url) }
            return nil
        }
        return ClipboardHistoryFileLease(url: url, scoped: scoped, stopAccessing: stopAccessing, onRelease: onRelease)
    }

    deinit {
        if scoped { stopAccessing(url) }
        onRelease?()
    }
}

struct ClipboardCapturedFile {
    let url: URL
    let reference: ClipboardHistoryFileReference
    let snapshot: Data?
}

/// Captures use the pasteboard's native URL while its grant is still present.
/// Bytes stay in memory until source exclusions have admitted the entry.
enum ClipboardHistoryFileCapture {
    static let maxSnapshotBytes = 32 * 1024 * 1024
    static let maxCaptureSnapshotBytes = 64 * 1024 * 1024

    static func capture(_ urls: [URL], snapshotByteLimit: Int = maxSnapshotBytes,
                        totalSnapshotByteLimit: Int = maxCaptureSnapshotBytes) -> [ClipboardCapturedFile] {
        var remaining = max(0, totalSnapshotByteLimit)
        return urls.map { url in
            let lease = ClipboardHistoryFileLease.open(url)
            defer { withExtendedLifetime(lease) {} }
            let bookmark = lease.flatMap { _ in
                (try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]))
                    ?? (try? url.bookmarkData())
            }
            var snapshot: Data?
            let limit = min(max(0, snapshotByteLimit), remaining)
            if lease != nil, limit > 0,
               let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
               values.isRegularFile == true, values.isSymbolicLink != true,
               let size = values.fileSize, size >= 0, size <= limit,
               let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                do {
                    let data = try handle.read(upToCount: limit + 1) ?? Data()
                    if data.count <= limit {
                        snapshot = data
                        remaining -= data.count
                    }
                } catch { /* A bookmark can still preserve the original. */ }
            }
            return ClipboardCapturedFile(url: url,
                reference: ClipboardHistoryFileReference(path: url.standardizedFileURL.path,
                                                          bookmark: bookmark, snapshotDirectory: nil),
                snapshot: snapshot)
        }
    }
}

enum ClipboardHistoryFileResolver {
    private static let lock = NSLock()
    private static var originals: [String: URL] = [:]

    static func remember(_ files: [ClipboardCapturedFile]) {
        lock.withLock {
            for file in files { originals[file.reference.path] = file.url }
        }
    }

    static func prune(keepingPaths paths: Set<String>) {
        lock.withLock { originals = originals.filter { paths.contains($0.key) } }
    }

    static func resolve(_ entry: ClipboardHistoryEntry, at index: Int = 0,
                        storeDirectory: URL? = ClipboardFileStore.directory,
                        imageDirectory: URL? = nil) -> ClipboardHistoryFileLease? {
        guard entry.kind == .files, entry.filePaths.indices.contains(index) else { return nil }
        let path = entry.filePaths[index]
        guard (path as NSString).isAbsolutePath else { return nil }
        if let original = lock.withLock({ originals[path] }), let lease = ClipboardHistoryFileLease.open(original) {
            return lease
        }
        let reference = entry.fileReferences.first { $0.path == path }
        if let bookmark = reference?.bookmark {
            var stale = false
            let options: URL.BookmarkResolutionOptions = [.withoutUI, .withoutMounting, .withoutImplicitStartAccessing]
            let resolved = (try? URL(resolvingBookmarkData: bookmark, options: options.union(.withSecurityScope),
                                     relativeTo: nil, bookmarkDataIsStale: &stale))
                ?? (try? URL(resolvingBookmarkData: bookmark, options: options,
                             relativeTo: nil, bookmarkDataIsStale: &stale))
            if let resolved, let lease = ClipboardHistoryFileLease.open(resolved) { return lease }
        }
        if let lease = ClipboardHistoryFileLease.open(URL(fileURLWithPath: path)) { return lease }
        if let reference, let name = reference.snapshotDirectory, UUID(uuidString: name) != nil {
            ClipboardFileStore.retainSnapshot(name)
            if let url = ClipboardFileStore.snapshotURL(for: reference, directory: storeDirectory),
               let lease = ClipboardHistoryFileLease.open(url, onRelease: {
                   ClipboardFileStore.releaseSnapshot(name)
               }) { return lease }
            ClipboardFileStore.releaseSnapshot(name)
        }
        // Older copied-image entries may have only the durable PNG preview.
        let images = imageDirectory ?? PrivateFileStore.containerURL?.appendingPathComponent("ClipboardImages")
        if entry.filePaths.count == 1, ClipboardHistoryImageSupport.isImageFileName(path),
           let name = entry.imageFile, !name.isEmpty,
           name != ".", name != "..", (name as NSString).lastPathComponent == name,
           let images {
            return ClipboardHistoryFileLease.open(images.appendingPathComponent(name))
        }
        return nil
    }

    static func resolveAll(_ entry: ClipboardHistoryEntry,
                           storeDirectory: URL? = ClipboardFileStore.directory,
                           imageDirectory: URL? = nil) -> [ClipboardHistoryFileLease] {
        entry.filePaths.indices.compactMap {
            resolve(entry, at: $0, storeDirectory: storeDirectory, imageDirectory: imageDirectory)
        }
    }
}

/// Exact-byte regular-file snapshots, bounded independently of history count.
/// An entry owns its files; pending writes and live consumers protect their
/// directories from cleanup until the corresponding leases are released.
enum ClipboardFileStore {
    static let maxStoredBytes = 256 * 1024 * 1024
    static var directory: URL? { PrivateFileStore.containerURL?.appendingPathComponent("ClipboardFiles", isDirectory: true) }
    private static let queue = DispatchQueue(label: "com.vorssaint.utils.clipboard-files", qos: .utility)
    private static let lock = NSLock()
    private static var pending: Set<String> = []
    private static var active: [String: Int] = [:]

    final class StoredBatch {
        let references: [ClipboardHistoryFileReference]
        private let created: Set<String>
        private let directory: URL?
        private var finished = false

        fileprivate init(references: [ClipboardHistoryFileReference], created: Set<String>, directory: URL?) {
            self.references = references
            self.created = created
            self.directory = directory
        }

        func finish(keeping: Bool) {
            guard !finished else { return }
            finished = true
            if !keeping, let directory {
                for name in created { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
            }
            ClipboardFileStore.lock.withLock { ClipboardFileStore.pending.subtract(created) }
        }

        deinit { finish(keeping: false) }
    }

    static func persist(_ files: [ClipboardCapturedFile], previous: [ClipboardHistoryFileReference] = [],
                        directory: URL? = directory, byteLimit: Int = maxStoredBytes,
                        completion: @escaping (StoredBatch) -> Void) {
        queue.async {
            var created: Set<String> = []
            var used = directory.map(storedBytes) ?? 0
            let references = files.map { file -> ClipboardHistoryFileReference in
                var reference = file.reference
                let old = previous.first { $0.path == reference.path }
                reference.bookmark = reference.bookmark ?? old?.bookmark
                guard let data = file.snapshot else {
                    reference.snapshotDirectory = old?.snapshotDirectory
                    return reference
                }
                if let old, let url = snapshotURL(for: old, directory: directory),
                   (try? Data(contentsOf: url)) == data {
                    reference.snapshotDirectory = old.snapshotDirectory
                    return reference
                }
                guard let directory, data.count <= ClipboardHistoryFileCapture.maxSnapshotBytes,
                      data.count <= max(0, byteLimit - used) else { return reference }
                let name = UUID().uuidString
                let folder = directory.appendingPathComponent(name, isDirectory: true)
                let target = folder.appendingPathComponent((reference.path as NSString).lastPathComponent)
                lock.withLock { _ = pending.insert(name) }
                guard PrivateFileStore.createDirectory(at: folder), PrivateFileStore.write(data, to: target) else {
                    try? FileManager.default.removeItem(at: folder)
                    lock.withLock { _ = pending.remove(name) }
                    return reference
                }
                used += data.count
                created.insert(name)
                reference.snapshotDirectory = name
                return reference
            }
            let result = StoredBatch(references: references, created: created, directory: directory)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func snapshotURL(for reference: ClipboardHistoryFileReference, directory: URL?) -> URL? {
        guard let directory, let name = reference.snapshotDirectory, UUID(uuidString: name) != nil,
              (reference.path as NSString).isAbsolutePath else { return nil }
        let filename = (reference.path as NSString).lastPathComponent
        guard !filename.isEmpty, filename != "/", filename != ".", filename != ".." else { return nil }
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        let file = folder.appendingPathComponent(filename)
        guard let folderValues = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              folderValues.isDirectory == true, folderValues.isSymbolicLink != true,
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return file
    }

    static func retainSnapshot(_ name: String) { lock.withLock { active[name, default: 0] += 1 } }
    static func releaseSnapshot(_ name: String) {
        lock.withLock {
            let count = active[name, default: 0] - 1
            active[name] = count > 0 ? count : nil
        }
    }

    static func cleanup(keeping names: Set<String>, directory: URL? = directory) {
        guard let directory,
              let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return }
        for child in children where UUID(uuidString: child.lastPathComponent) != nil {
            lock.withLock {
                let name = child.lastPathComponent
                guard !names.contains(name), !pending.contains(name), active[name] == nil else { return }
                try? FileManager.default.removeItem(at: child)
            }
        }
    }

    private static func storedBytes(_ directory: URL) -> Int {
        guard let folders = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else { return 0 }
        return folders.reduce(0) { total, folder in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
            else { return total }
            return total + children.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }
}
