// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Walks a folder tree with `getattrlistbulk`, several directories at a time.
/// One call returns the name, type, flags and allocated size of a batch of
/// entries, so a whole disk is read without a `stat` per file.
///
/// The walk never follows symbolic links, never leaves the allowed volumes,
/// never descends into cloud placeholders and asks the kernel not to download
/// dataless files, so scanning iCloud Drive cannot fill the disk it measures.
final class DiskAnalyzerScanner: @unchecked Sendable {
    struct Options {
        /// Volumes the walk may enter. Empty means the root's own volume.
        var allowedDevices: Set<dev_t> = []
        /// Absolute paths that are skipped entirely, such as the other APFS
        /// volumes a whole-disk scan would otherwise count twice.
        var skippedPaths: Set<String> = []
        /// Folders smaller than this keep their size but not their contents.
        var collapseBelow: Int64 = 1 << 20
        /// Files smaller than this fold into a directory's small-files entry.
        var minimumListedFile: Int64 = 256 << 10
        var workers = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
    }

    struct Progress: Equatable {
        var files = 0
        var folders = 0
        var bytes: Int64 = 0
        var unreadable = 0
        var currentPath = ""
    }

    private struct Job {
        let node: DiskNode
        let path: String
    }

    private let options: Options
    private let condition = NSCondition()
    private var jobs: [Job] = []
    private var active = 0
    private var finished = false
    private let stateLock = NSLock()
    private var progress = Progress()
    private var cancelled = false
    /// Files with more than one hard link are counted once. An inode number
    /// is only unique within its volume, and a startup disk spans two.
    private struct LinkID: Hashable {
        let device: dev_t
        let file: UInt64
    }
    private var seenLinks: Set<LinkID> = []
    private let pendingLock = NSLock()

    init(options: Options) {
        self.options = options
    }

    var isCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelled
    }

    func cancel() {
        stateLock.lock()
        cancelled = true
        stateLock.unlock()
        condition.lock()
        jobs.removeAll()
        condition.broadcast()
        condition.unlock()
    }

    func snapshot() -> Progress {
        stateLock.lock()
        defer { stateLock.unlock() }
        return progress
    }

    /// Scans `path` and returns its finalized tree, or nil when cancelled or
    /// when the root itself cannot be opened. Blocks the calling thread.
    func scan(path: String, displayName: String) -> DiskNode? {
        var rootStat = stat()
        guard lstat(path, &rootStat) == 0, (rootStat.st_mode & S_IFMT) == S_IFDIR else { return nil }
        var allowed = options.allowedDevices
        if allowed.isEmpty { allowed.insert(rootStat.st_dev) }
        let root = DiskNode(name: displayName, kind: .directory, rootPath: path)

        condition.lock()
        jobs = [Job(node: root, path: path)]
        active = 0
        finished = false
        condition.unlock()

        let group = DispatchGroup()
        for index in 0..<options.workers {
            group.enter()
            let thread = Thread { [self] in
                Self.disableCloudDownloads()
                work(allowed: allowed)
                group.leave()
            }
            thread.name = "Disk analyzer \(index)"
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 20
            thread.start()
        }
        group.wait()

        guard !isCancelled else { return nil }
        return root
    }

    /// Opening or reading a dataless file fails instead of downloading it.
    private static func disableCloudDownloads() {
        _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
                           IOPOL_SCOPE_THREAD,
                           IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    }

    private func work(allowed: Set<dev_t>) {
        // One listing buffer per worker, reused for every directory it reads.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            condition.lock()
            while jobs.isEmpty && !finished {
                if active == 0 {
                    finished = true
                    condition.broadcast()
                    break
                }
                condition.wait()
            }
            if finished || isCancelled {
                finished = true
                condition.broadcast()
                condition.unlock()
                return
            }
            let job = jobs.removeLast()
            active += 1
            condition.unlock()

            let discovered = list(job, allowed: allowed, buffer: buffer)
            if discovered.isEmpty { complete(job.node) }

            condition.lock()
            active -= 1
            if !discovered.isEmpty {
                jobs.append(contentsOf: discovered)
                condition.broadcast()
            } else if jobs.isEmpty && active == 0 {
                finished = true
                condition.broadcast()
            }
            condition.unlock()
        }
    }

    // MARK: - Reading one directory

    private static let commonAttributes: attrgroup_t =
        attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_ERROR)
        | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
    private static let fileAttributes: attrgroup_t =
        attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
    private static let bufferSize = 256 * 1024

    /// Lists one directory into its node and returns the subdirectories to
    /// visit next.
    private func list(_ job: Job, allowed: Set<dev_t>, buffer: UnsafeMutableRawPointer) -> [Job] {
        let node = job.node
        let fd = open(job.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            node.unreadable = true
            record(unreadable: true, path: job.path)
            return []
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, allowed.contains(info.st_dev) else { return [] }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = Self.commonAttributes
        request.fileattr = Self.fileAttributes


        var files: [DiskNode] = []
        var folders: [DiskNode] = []
        var next: [Job] = []
        var ownBytes: Int64 = 0
        var ownFiles = 0
        var batchBytes: Int64 = 0
        let prefix = job.path.hasSuffix("/") ? job.path : job.path + "/"

        while !isCancelled {
            let count = getattrlistbulk(fd, &request, buffer, Self.bufferSize, 0)
            if count < 0 {
                if files.isEmpty && folders.isEmpty { node.unreadable = true }
                break
            }
            if count == 0 { break }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }
                guard let parsed = Self.parse(entry) else { continue }
                switch parsed.type {
                case VDIR.rawValue:
                    let child = DiskNode(name: parsed.name, kind: .directory)
                    child.parent = node
                    folders.append(child)
                    let childPath = prefix + parsed.name
                    if parsed.flags & UInt32(SF_DATALESS) != 0 {
                        child.cloudOnly = true
                    } else if !options.skippedPaths.contains(childPath) {
                        next.append(Job(node: child, path: childPath))
                    }
                case VREG.rawValue:
                    var size = parsed.allocated
                    if parsed.links > 1, !firstSighting(of: LinkID(device: info.st_dev, file: parsed.fileID)) { size = 0 }
                    let file = DiskNode(name: parsed.name, kind: .file, size: size, fileCount: 1)
                    file.parent = node
                    files.append(file)
                    ownBytes += size
                    ownFiles += 1
                    batchBytes += size
                case VLNK.rawValue:
                    // Links take a few bytes and point at items counted where
                    // they really live.
                    continue
                default:
                    continue
                }
            }
        }

        node.size = ownBytes
        node.fileCount = ownFiles
        let listed = DiskAnalyzerSupport.foldFiles(files, minimumSize: options.minimumListedFile)
        for entry in listed where entry.kind == .smallFiles { entry.parent = node }
        node.children = folders + listed
        node.pendingFolders = next.count
        record(files: ownFiles, folders: 1, bytes: batchBytes, path: job.path)
        return next
    }

    /// Settles a folder whose subfolders are all done, then walks up while
    /// that completes a parent too. Each folder settles exactly once, after
    /// all of its subfolders, so small ones can be collapsed as the walk goes
    /// instead of holding a whole disk's worth of entries until the end.
    private func complete(_ finished: DiskNode) {
        var node = finished
        while true {
            DiskAnalyzerSupport.settle(node, collapseBelow: options.collapseBelow)
            guard let parent = node.parent else { return }
            pendingLock.lock()
            parent.pendingFolders -= 1
            let ready = parent.pendingFolders == 0
            pendingLock.unlock()
            guard ready else { return }
            node = parent
        }
    }

    private struct Entry {
        let name: String
        let type: UInt32
        let flags: UInt32
        let fileID: UInt64
        let links: UInt32
        let allocated: Int64
    }

    /// Reads one packed `getattrlistbulk` record. Fields appear in a fixed
    /// order, each only when its bit is set in the returned attribute set.
    private static func parse(_ start: UnsafeMutableRawPointer) -> Entry? {
        var cursor = start + MemoryLayout<UInt32>.size
        let returned = cursor.loadUnaligned(as: attribute_set_t.self)
        cursor += MemoryLayout<attribute_set_t>.size

        if returned.commonattr & attrgroup_t(ATTR_CMN_ERROR) != 0 {
            let error = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
            if error != 0 { return nil }
        }
        guard returned.commonattr & attrgroup_t(ATTR_CMN_NAME) != 0 else { return nil }
        let nameField = cursor
        let reference = cursor.loadUnaligned(as: attrreference_t.self)
        cursor += MemoryLayout<attrreference_t>.size
        let nameStart = nameField + Int(reference.attr_dataoffset)
        let name = String(cString: nameStart.assumingMemoryBound(to: CChar.self))
        guard !name.isEmpty, name != ".", name != ".." else { return nil }

        var type: UInt32 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_OBJTYPE) != 0 {
            type = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
        }
        var flags: UInt32 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_FLAGS) != 0 {
            flags = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
        }
        var fileID: UInt64 = 0
        if returned.commonattr & attrgroup_t(ATTR_CMN_FILEID) != 0 {
            fileID = cursor.loadUnaligned(as: UInt64.self)
            cursor += MemoryLayout<UInt64>.size
        }
        var links: UInt32 = 1
        if returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 {
            links = cursor.loadUnaligned(as: UInt32.self)
            cursor += MemoryLayout<UInt32>.size
        }
        var allocated: Int64 = 0
        if returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 {
            allocated = cursor.loadUnaligned(as: Int64.self)
        }
        return Entry(name: name, type: type, flags: flags, fileID: fileID,
                     links: links, allocated: max(0, allocated))
    }

    private func firstSighting(of link: LinkID) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return seenLinks.insert(link).inserted
    }

    private func record(files: Int = 0, folders: Int = 0, bytes: Int64 = 0,
                        unreadable: Bool = false, path: String? = nil) {
        stateLock.lock()
        progress.files += files
        progress.folders += folders
        progress.bytes += bytes
        if unreadable { progress.unreadable += 1 }
        if let path { progress.currentPath = path }
        stateLock.unlock()
    }
}
