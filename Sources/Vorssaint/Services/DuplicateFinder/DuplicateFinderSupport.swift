// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Darwin
import Foundation

/// All content and paths are session-only. Identity includes nanosecond change
/// times: a replacement or edit must never inherit a scan's removal eligibility.
enum DuplicateFinderSupport {
    struct Identity: Equatable, Hashable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanos: Int
        let changedSeconds: Int
        let changedNanos: Int
        init(_ info: stat) {
            device = UInt64(info.st_dev); inode = UInt64(info.st_ino); size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec; modifiedNanos = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec; changedNanos = info.st_ctimespec.tv_nsec
        }
    }
    struct Directory: Equatable {
        let url: URL
        let device: UInt64
        let inode: UInt64
    }
    struct File: Identifiable, Equatable {
        var id: URL { url }
        let url: URL
        let identity: Identity
        let ancestry: [Directory]
        var modified: Date { Date(timeIntervalSince1970: Double(identity.modifiedSeconds) + Double(identity.modifiedNanos) / 1e9) }
    }
    struct Group: Identifiable, Equatable {
        var id: URL { files[0].url }
        let files: [File]
        var duplicateBytes: Int64 { files.dropFirst().reduce(0) { saturatingAdd($0, $1.identity.size) } }
    }
    enum Reason: String, CaseIterable {
        case hidden, package, trash, symbolicLink, alias, hardLink, cloud, resourceFork, inaccessible, changed, cancelled, keepCopy, failed
    }
    struct Issue: Identifiable {
        let id = UUID()
        let url: URL
        let reason: Reason
    }
    struct Report {
        var groups: [Group] = []
        var issues: [Issue] = []
        var examined = 0
        var cancelled = false
    }
    struct Progress {
        enum Phase { case enumerating, comparing }
        let phase: Phase
        let completed: Int
        let total: Int?
    }
    struct Outcome {
        let file: File
        let reason: Reason?
        var moved: Bool { reason == nil }
    }
    /// Shared across the UI and its worker; cancellation never relies on polling
    /// a main-thread property from the filesystem queue.
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
        func cancel() { lock.lock(); value = true; lock.unlock() }
    }
    enum Failure: Error { case cancelled, changed, inaccessible }
    static let chunkSize = 1_048_576

    static func saturatingAdd(_ a: Int64, _ b: Int64) -> Int64 {
        let result = a.addingReportingOverflow(b)
        return result.overflow ? Int64.max : result.partialValue
    }
    static func canonicalURL(_ url: URL) -> URL {
        // Foundation may abbreviate /private/var back to the /var symlink.
        // Preserve realpath's spelling so ancestry checks see real directories.
        guard let resolved = url.withUnsafeFileSystemRepresentation({ path in path.flatMap { realpath($0, nil) } }) else { return url }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }
    static func normalizedRoots(_ roots: [URL]) -> [URL] {
        let sorted = Set(roots.map(canonicalURL)).sorted { $0.path < $1.path }
        return sorted.filter { root in !sorted.contains { $0 != root && contains(root, in: $0) } }
    }
    static func contains(_ url: URL, in root: URL) -> Bool {
        url.path == root.path || url.path.hasPrefix(root.path == "/" ? "/" : root.path + "/")
    }
    static func info(_ url: URL) -> stat? {
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ $0.map { lstat($0, &value) == 0 } ?? false }) else { return nil }
        return value
    }
    static func directories(to url: URL) -> [Directory]? {
        var result: [Directory] = []
        var current = url
        while true {
            guard let value = info(current), value.st_mode & S_IFMT == S_IFDIR else { return nil }
            result.append(Directory(url: current, device: UInt64(value.st_dev), inode: UInt64(value.st_ino)))
            if current.path == "/" { return result }
            current = URL(fileURLWithPath: (current.path as NSString).deletingLastPathComponent)
        }
    }
    static func ancestryMatches(_ ancestry: [Directory]) -> Bool {
        ancestry.allSatisfy { directory in
            guard let value = info(directory.url) else { return false }
            return value.st_mode & S_IFMT == S_IFDIR && UInt64(value.st_dev) == directory.device && UInt64(value.st_ino) == directory.inode
        }
    }
    static func exclusion(_ url: URL, info value: stat) -> Reason? {
        if value.st_mode & S_IFMT == S_IFLNK { return .symbolicLink }
        if value.st_flags & UInt32(SF_DATALESS) != 0 { return .cloud }
        guard let values = try? url.resourceValues(forKeys: [.isHiddenKey, .isPackageKey, .isAliasFileKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) else { return .inaccessible }
        if [".Trash", ".Trashes"].contains(url.lastPathComponent) { return .trash }
        if values.isHidden == true || url.lastPathComponent.hasPrefix(".") { return .hidden }
        if values.isPackage == true { return .package }
        if values.isAliasFile == true { return .alias }
        if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current && values.ubiquitousItemDownloadingStatus != .downloaded { return .cloud }
        if value.st_mode & S_IFMT == S_IFREG {
            if value.st_nlink > 1 { return .hardLink }
            // Size lookup does not read the fork or materialize its contents.
            let forkSize = url.withUnsafeFileSystemRepresentation { path -> Int in
                guard let path else { return -1 }
                return getxattr(path, "com.apple.ResourceFork", nil, 0, 0, XATTR_NOFOLLOW)
            }
            if forkSize >= 0 { return .resourceFork }
            if forkSize < 0 && errno != ENOATTR && errno != ENOTSUP { return .inaccessible }
        }
        return nil
    }
    static func snapshot(_ url: URL) -> File? {
        guard let value = info(url), value.st_mode & S_IFMT == S_IFREG,
              exclusion(url, info: value) == nil,
              let ancestry = directories(to: url.deletingLastPathComponent()) else { return nil }
        return File(url: url, identity: Identity(value), ancestry: ancestry)
    }
    static func stillMatches(_ file: File) -> Bool {
        guard ancestryMatches(file.ancestry), let value = info(file.url),
              value.st_mode & S_IFMT == S_IFREG, Identity(value) == file.identity,
              exclusion(file.url, info: value) == nil else { return false }
        return true
    }
    private static func opened(_ file: File) throws -> FileHandle {
        guard stillMatches(file) else { throw Failure.changed }
        let fd = file.url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard fd >= 0 else { throw Failure.inaccessible }
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              Identity(value) == file.identity, value.st_flags & UInt32(SF_DATALESS) == 0 else {
            Darwin.close(fd); throw Failure.changed
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    private static func check(_ file: File, handle: FileHandle) throws {
        var value = stat()
        guard fstat(handle.fileDescriptor, &value) == 0, Identity(value) == file.identity, stillMatches(file) else { throw Failure.changed }
    }
    static func digest(_ file: File, cancellation: Cancellation, didRead: () throws -> Void = {}) throws -> Data {
        let handle = try opened(file)
        defer { try? handle.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while true {
            if cancellation.isCancelled { throw Failure.cancelled }
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            bytes += Int64(data.count)
            guard bytes <= file.identity.size else { throw Failure.changed }
            hash.update(data: data)
            try didRead()
        }
        try check(file, handle: handle)
        guard bytes == file.identity.size else { throw Failure.changed }
        return Data(hash.finalize())
    }
    static func equal(_ left: File, _ right: File, cancellation: Cancellation) throws -> Bool {
        guard left.identity.size == right.identity.size else { return false }
        let a = try opened(left); defer { try? a.close() }
        let b = try opened(right); defer { try? b.close() }
        var bytes: Int64 = 0
        while true {
            if cancellation.isCancelled { throw Failure.cancelled }
            let x = try a.read(upToCount: chunkSize) ?? Data()
            let y = try b.read(upToCount: chunkSize) ?? Data()
            guard x == y else { return false }
            bytes += Int64(x.count)
            guard bytes <= left.identity.size else { throw Failure.changed }
            if x.isEmpty { break }
        }
        try check(left, handle: a); try check(right, handle: b)
        return bytes == left.identity.size
    }
    private static func readFailure(_ error: Error, cancellation: Cancellation) -> Reason {
        if cancellation.isCancelled { return .cancelled }
        if case Failure.changed = error { return .changed }
        return .inaccessible
    }
    static func excludedRoot(_ ancestry: [Directory]) -> Reason? {
        for directory in ancestry {
            if [".Trash", ".Trashes"].contains(directory.url.lastPathComponent) { return .trash }
            guard let values = try? directory.url.resourceValues(forKeys: [.isPackageKey]) else { return .inaccessible }
            if values.isPackage == true { return .package }
        }
        return nil
    }
    static func scan(roots: [URL], cancellation: Cancellation,
                     progress: (Progress) -> Void = { _ in },
                     hash: (File, Cancellation) throws -> Data = { try digest($0, cancellation: $1) }) -> Report {
        var report = Report()
        var files: [File] = []
        var lastProgress = Date.distantPast
        func publish(_ phase: Progress.Phase, _ count: Int, _ total: Int? = nil) {
            if Date().timeIntervalSince(lastProgress) >= 0.1 || count == total {
                lastProgress = Date(); progress(Progress(phase: phase, completed: count, total: total))
            }
        }
        for root in normalizedRoots(roots) {
            guard !cancellation.isCancelled else { break }
            guard let ancestry = directories(to: root), ancestryMatches(ancestry),
                  let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isHiddenKey, .isPackageKey], options: [], errorHandler: { url, _ in
                      report.issues.append(Issue(url: url, reason: .inaccessible)); return !cancellation.isCancelled
                  }) else { report.issues.append(Issue(url: root, reason: .inaccessible)); continue }
            if let reason = excludedRoot(ancestry) {
                report.issues.append(Issue(url: root, reason: reason)); continue
            }
            for case let url as URL in enumerator {
                if cancellation.isCancelled { break }
                report.examined += 1; publish(.enumerating, report.examined)
                guard ancestryMatches(ancestry), let value = info(url) else {
                    report.issues.append(Issue(url: url, reason: .inaccessible)); enumerator.skipDescendants(); continue
                }
                if let reason = exclusion(url, info: value) {
                    report.issues.append(Issue(url: url, reason: reason)); enumerator.skipDescendants(); continue
                }
                if value.st_mode & S_IFMT == S_IFREG {
                    if let file = snapshot(url) { files.append(file) }
                    else { report.issues.append(Issue(url: url, reason: .changed)) }
                }
            }
        }
        let candidates = Dictionary(grouping: files, by: { $0.identity.size }).values.filter { $0.count > 1 }.flatMap { $0 }.sorted { $0.url.path < $1.url.path }
        var buckets: [Data: [File]] = [:]
        for (index, file) in candidates.enumerated() {
            if cancellation.isCancelled { break }
            do { buckets[try hash(file, cancellation), default: []].append(file) }
            catch { report.issues.append(Issue(url: file.url, reason: readFailure(error, cancellation: cancellation))) }
            publish(.comparing, index + 1, candidates.count)
        }
        for bucket in buckets.values where bucket.count > 1 {
            var partitions: [[File]] = []
            for file in bucket {
                if cancellation.isCancelled { break }
                do {
                    guard stillMatches(file) else { throw Failure.changed }
                    var found = false
                    for index in partitions.indices {
                        if try equal(file, partitions[index][0], cancellation: cancellation) {
                            partitions[index].append(file); found = true; break
                        }
                    }
                    if !found { partitions.append([file]) }
                } catch { report.issues.append(Issue(url: file.url, reason: readFailure(error, cancellation: cancellation))) }
            }
            report.groups += partitions.filter { $0.count > 1 && $0.allSatisfy(stillMatches) }.map { Group(files: $0) }
        }
        report.cancelled = cancellation.isCancelled
        if report.cancelled { report.groups = [] }
        report.groups.sort { $0.duplicateBytes == $1.duplicateBytes ? $0.id.path < $1.id.path : $0.duplicateBytes > $1.duplicateBytes }
        return report
    }
    static func validSelection(_ selection: Set<URL>, groups: [Group]) -> Bool {
        let known = Set(groups.flatMap { $0.files.map(\.url) })
        return !selection.isEmpty && selection.isSubset(of: known) && groups.allSatisfy { group in
            group.files.contains { !selection.contains($0.url) }
        }
    }
    static func trash(selection: Set<URL>, groups: [Group], cancellation: Cancellation,
                      move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> [Outcome] {
        guard validSelection(selection, groups: groups) else { return [] }
        var outcomes: [Outcome] = []
        for group in groups {
            let keepers = group.files.filter { !selection.contains($0.url) }
            var keeperFailed = false
            for file in group.files where selection.contains(file.url) {
                if cancellation.isCancelled { outcomes.append(Outcome(file: file, reason: .cancelled)); continue }
                if keeperFailed { outcomes.append(Outcome(file: file, reason: .keepCopy)); continue }
                guard let keeper = keepers.first(where: stillMatches) else {
                    keeperFailed = true; outcomes.append(Outcome(file: file, reason: .keepCopy)); continue
                }
                do {
                    guard try equal(file, keeper, cancellation: cancellation), stillMatches(keeper), stillMatches(file) else { throw Failure.changed }
                    if cancellation.isCancelled { throw Failure.cancelled }
                    // A path-based Trash API cannot lock out other applications;
                    // check again at the last possible point before the move.
                    try move(file.url)
                    outcomes.append(Outcome(file: file, reason: nil))
                } catch {
                    if !stillMatches(keeper) { keeperFailed = true }
                    outcomes.append(Outcome(file: file, reason: cancellation.isCancelled ? .cancelled : (stillMatches(file) ? .failed : .changed)))
                }
            }
        }
        return outcomes
    }
}
