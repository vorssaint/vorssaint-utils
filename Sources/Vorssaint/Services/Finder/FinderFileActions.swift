// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CryptoKit
import Darwin
import Foundation

public struct FinderFileActionItemFailure: Sendable, Equatable {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

public enum FinderFileActionError: Error, LocalizedError {
    case invalidName(String)
    case invalidRequest(String)
    case itemNotFound(URL)
    case destinationExists(URL)
    case notDirectory(URL)
    case unsupported(URL, String)
    case operationFailed(operation: String, url: URL, reason: String)
    case partialFailure(operation: String, completed: [URL], failures: [FinderFileActionItemFailure])

    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "The file name is empty or unsafe: \(name)"
        case .invalidRequest(let message):
            return message
        case .itemNotFound(let url):
            return "No file exists at \(url.path)."
        case .destinationExists(let url):
            return "A file already exists at \(url.path)."
        case .notDirectory(let url):
            return "The destination is not a directory: \(url.path)."
        case .unsupported(let url, let message):
            return "\(message): \(url.path)"
        case .operationFailed(let operation, let url, let reason):
            return "Could not \(operation) \(url.path): \(reason)"
        case .partialFailure(let operation, let completed, let failures):
            let names = failures.map(\.url.lastPathComponent).joined(separator: ", ")
            return "Could not complete \(operation). Completed \(completed.count) item(s); failed: \(names)."
        }
    }
}

/// Safe Foundation-backed file operations shared by Finder tools.
///
/// All destination writes are exclusive. Multi-item moves report completed
/// destinations and individual failures; they are intentionally not rolled
/// back because doing so could overwrite or discard user data.
public enum FinderFileActions {
    public enum CollisionPolicy: Sendable, Equatable {
        case fail
        case makeUnique
    }

    public enum ItemKind: String, Sendable, Equatable {
        case file
        case directory
        case symbolicLink
        case other
    }

    public struct TreeEntry: Sendable, Equatable {
        public let url: URL
        public let name: String
        public let depth: Int
        public let kind: ItemKind
        /// File bytes for regular files, link bytes for symbolic links, nil for directories.
        public let size: Int64?
    }

    public struct TreeSnapshot: Sendable, Equatable {
        public let entries: [TreeEntry]
        public let truncated: Bool
    }

    public struct RenameChange: Sendable, Equatable {
        public let source: URL
        public let newName: String

        public init(source: URL, newName: String) {
            self.source = source
            self.newName = newName
        }
    }

    public struct Rename: Sendable, Equatable {
        public let source: URL
        public let destination: URL
    }

    public struct RenamePlan: Sendable, Equatable {
        public let renames: [Rename]
    }

    private struct Metadata {
        let kind: ItemKind
        let size: Int64
    }

    private static let hashReadSize = 1024 * 1024
    private static let uniqueNameAttempts = 10_000

    /// Creates a new regular file. `makeUnique` adds a numbered suffix if needed.
    @discardableResult
    public static func createFile(in directory: URL,
                                  named name: String,
                                  contents: Data = Data(),
                                  collisionPolicy: CollisionPolicy = .fail) throws -> URL {
        try requireDirectory(directory)
        let safeName = try validatedName(name)
        return try createExclusive(in: directory, named: safeName, collisionPolicy: collisionPolicy) { url in
            try writeExclusively(contents, to: url)
        }
    }

    /// Creates a new empty directory. `makeUnique` adds a numbered suffix if needed.
    @discardableResult
    public static func createFolder(in directory: URL,
                                    named name: String,
                                    collisionPolicy: CollisionPolicy = .fail) throws -> URL {
        try requireDirectory(directory)
        let safeName = try validatedName(name)
        return try createExclusive(in: directory, named: safeName, collisionPolicy: collisionPolicy) { url in
            let result = url.path.withCString { mkdir($0, mode_t(0o777)) }
            guard result == 0 else { throw posixError(operation: "create folder", at: url) }
        }
    }

    /// Copies an item to an exact destination URL without replacing an existing item.
    @discardableResult
    public static func copyItem(at source: URL, to destination: URL) throws -> URL {
        let sourceMetadata = try metadata(at: source)
        try requireNewDestination(destination)
        try requireDirectory(destination.deletingLastPathComponent())
        if sourceMetadata.kind == .directory && isDescendant(destination, of: source) {
            throw FinderFileActionError.invalidRequest("A directory cannot be copied into itself or a descendant.")
        }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            let state = itemExists(at: destination)
                ? " A destination exists after the failed copy and was preserved because its ownership is unclear."
                : ""
            throw FinderFileActionError.operationFailed(operation: "copy", url: source,
                                                        reason: error.localizedDescription + state)
        }
    }

    /// Moves an item to an exact destination URL without replacing an existing item.
    @discardableResult
    public static func moveItem(at source: URL, to destination: URL) throws -> URL {
        let sourceMetadata = try metadata(at: source)
        try requireNewDestination(destination)
        try requireDirectory(destination.deletingLastPathComponent())
        if sourceMetadata.kind == .directory && isDescendant(destination, of: source) {
            throw FinderFileActionError.invalidRequest("A directory cannot be moved into itself or a descendant.")
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            return destination
        } catch {
            var state = ""
            if itemExists(at: destination) {
                state += " A destination exists after the failed move and was preserved because its ownership is unclear."
            }
            if itemExists(at: source) {
                state += " The source remains at its original path."
            } else {
                state += " The source no longer exists at its original path; inspect the destination before retrying."
            }
            throw FinderFileActionError.operationFailed(operation: "move", url: source,
                                                        reason: error.localizedDescription + state)
        }
    }

    /// Creates a Finder alias file; the final install never replaces an existing item.
    @discardableResult
    public static func createAlias(to target: URL, at destination: URL) throws -> URL {
        _ = try metadata(at: target)
        try requireNewDestination(destination)
        try requireDirectory(destination.deletingLastPathComponent())
        let bookmark: Data
        do {
            bookmark = try target.bookmarkData(options: [.suitableForBookmarkFile],
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil)
        } catch {
            throw FinderFileActionError.operationFailed(operation: "create alias", url: destination,
                                                        reason: error.localizedDescription)
        }
        let staging = try createFolder(in: destination.deletingLastPathComponent(),
                                       named: ".vorssaint-alias-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let temporary = staging.appendingPathComponent("alias")
        try URL.writeBookmarkData(bookmark, to: temporary)
        return try moveItem(at: temporary, to: destination)
    }

    /// Changes the Finder hidden attribute. Symbolic links are not followed or mutated.
    public static func setHidden(_ hidden: Bool, at url: URL) throws {
        try requireMutableItem(url)
        do {
            var values = try url.resourceValues(forKeys: [.isHiddenKey])
            values.isHidden = hidden
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        } catch {
            throw FinderFileActionError.operationFailed(operation: hidden ? "hide" : "unhide",
                                                        url: url, reason: error.localizedDescription)
        }
    }

    /// Sets or clears the user immutable bit. Symbolic links are not followed or mutated.
    public static func setLocked(_ locked: Bool, at url: URL) throws {
        try requireMutableItem(url)
        do {
            try FileManager.default.setAttributes([.immutable: NSNumber(value: locked)], ofItemAtPath: url.path)
        } catch {
            throw FinderFileActionError.operationFailed(operation: locked ? "lock" : "unlock",
                                                        url: url, reason: error.localizedDescription)
        }
    }

    public static func path(of url: URL) -> String {
        url.standardizedFileURL.path
    }

    public static func name(of url: URL) -> String {
        url.lastPathComponent
    }

    /// Formats an absolute file URL as a Markdown link, escaping its label.
    public static func markdownLink(to url: URL, label: String? = nil) -> String {
        let title = escapeMarkdownLabel(label ?? name(of: url))
        return "[\(title)](<\(url.standardizedFileURL.absoluteString)>)"
    }

    /// Lists items without traversing symbolic links. Depth zero is the root.
    public static func fileTree(at root: URL,
                                maximumDepth: Int = 32,
                                maximumEntries: Int = 10_000,
                                checkCancellation: () throws -> Void = {}) throws -> TreeSnapshot {
        guard maximumDepth >= 0, maximumEntries > 0 else {
            throw FinderFileActionError.invalidRequest("Tree limits must have a nonnegative depth and positive entry count.")
        }
        let rootMetadata = try metadata(at: root)
        var entries = [TreeEntry(url: root, name: name(of: root), depth: 0,
                                 kind: rootMetadata.kind, size: treeSize(rootMetadata))]
        var truncated = false

        func visit(_ directory: URL, depth: Int) throws {
            try checkCancellation()
            guard depth < maximumDepth else {
                if try !children(of: directory).isEmpty { truncated = true }
                return
            }
            for child in try children(of: directory) {
                try checkCancellation()
                guard entries.count < maximumEntries else {
                    truncated = true
                    return
                }
                let childMetadata = try metadata(at: child)
                entries.append(TreeEntry(url: child, name: name(of: child), depth: depth + 1,
                                         kind: childMetadata.kind, size: treeSize(childMetadata)))
                if childMetadata.kind == .directory {
                    try visit(child, depth: depth + 1)
                    if truncated { return }
                }
            }
        }

        if rootMetadata.kind == .directory { try visit(root, depth: 0) }
        return TreeSnapshot(entries: entries, truncated: truncated)
    }

    /// Returns regular-file bytes recursively; symbolic links contribute zero and are never followed.
    public static func size(of url: URL, checkCancellation: () throws -> Void = {}) throws -> Int64 {
        var pending = [url]
        var total: Int64 = 0
        while let item = pending.popLast() {
            try checkCancellation()
            let info = try metadata(at: item)
            switch info.kind {
            case .file:
                let (sum, overflow) = total.addingReportingOverflow(info.size)
                guard !overflow else {
                    throw FinderFileActionError.invalidRequest("The folder size exceeds the supported integer range.")
                }
                total = sum
            case .directory: pending += try children(of: item)
            case .symbolicLink, .other: break
            }
        }
        return total
    }

    /// Computes SHA-256 using a fixed-size streaming read and refuses symbolic links.
    public static func sha256(of url: URL, checkCancellation: () throws -> Void = {}) throws -> String {
        guard try metadata(at: url).kind == .file else {
            throw FinderFileActionError.unsupported(url, "Hashing requires a regular file")
        }
        let descriptor = url.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else { throw posixError(operation: "open for hashing", at: url) }
        defer { _ = close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError(operation: "inspect for hashing", at: url) }
        guard kind(from: info.st_mode) == .file else {
            throw FinderFileActionError.unsupported(url, "Hashing requires a regular file")
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: hashReadSize)
        while true {
            try checkCancellation()
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress!, bytes.count)
            }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError(operation: "read for hashing", at: url)
            }
            hasher.update(data: Data(buffer.prefix(count)))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Moves selected items into a newly created folder. All inputs must have distinct names.
    @discardableResult
    public static func group(_ items: [URL], in parent: URL, named name: String) throws -> URL {
        guard !items.isEmpty else { throw FinderFileActionError.invalidRequest("Choose at least one item to group.") }
        try requireDirectory(parent)
        let safeName = try validatedName(name)
        let sourceKeys = items.map(pathKey)
        guard Set(sourceKeys).count == items.count else {
            throw FinderFileActionError.invalidRequest("The same item was selected more than once.")
        }

        var seenNames = Set<String>()
        let target = parent.appendingPathComponent(safeName, isDirectory: true)
        for item in items {
            let info = try metadata(at: item)
            guard seenNames.insert(nameKey(item.lastPathComponent)).inserted else {
                throw FinderFileActionError.invalidRequest("Selected items have ambiguous names and cannot be grouped safely.")
            }
            if info.kind == .directory && isDescendant(target, of: item) {
                throw FinderFileActionError.invalidRequest("The group folder cannot be created inside an item being grouped.")
            }
        }

        let folder = try createFolder(in: parent, named: safeName)
        var completed: [URL] = []
        var failures: [FinderFileActionItemFailure] = []
        for item in items {
            let destination = folder.appendingPathComponent(item.lastPathComponent)
            do {
                _ = try moveItem(at: item, to: destination)
                completed.append(destination)
            } catch {
                failures.append(FinderFileActionItemFailure(url: item, reason: error.localizedDescription))
            }
        }
        if !failures.isEmpty {
            throw FinderFileActionError.partialFailure(operation: "group items", completed: completed,
                                                       failures: failures)
        }
        return folder
    }

    /// Moves direct children into the parent, then removes the empty source folder.
    /// rmdir never removes a newly arrived child or recursively deletes content.
    @discardableResult
    public static func flattenContents(of folder: URL) throws -> [URL] {
        guard try metadata(at: folder).kind == .directory else {
            throw FinderFileActionError.notDirectory(folder)
        }
        let parent = folder.deletingLastPathComponent()
        try requireDirectory(parent)
        let items = try children(of: folder)
        let parentItems = try children(of: parent).filter { pathKey($0) != pathKey(folder) }
        let existingNames = Set(parentItems.map { nameKey($0.lastPathComponent) })
        var movingNames = Set<String>()
        for item in items {
            let key = nameKey(item.lastPathComponent)
            guard movingNames.insert(key).inserted else {
                throw FinderFileActionError.invalidRequest("Folder contents have ambiguous names and cannot be flattened safely.")
            }
            guard !existingNames.contains(key) else {
                throw FinderFileActionError.destinationExists(parent.appendingPathComponent(item.lastPathComponent))
            }
        }

        var completed: [URL] = []
        var failures: [FinderFileActionItemFailure] = []
        for item in items {
            let destination = parent.appendingPathComponent(item.lastPathComponent)
            do {
                _ = try moveItem(at: item, to: destination)
                completed.append(destination)
            } catch {
                failures.append(FinderFileActionItemFailure(url: item, reason: error.localizedDescription))
            }
        }
        if !failures.isEmpty {
            throw FinderFileActionError.partialFailure(operation: "flatten folder", completed: completed,
                                                       failures: failures)
        }
        guard folder.path.withCString({ rmdir($0) }) == 0 else {
            throw FinderFileActionError.partialFailure(operation: "remove empty source folder", completed: completed,
                failures: [.init(url: folder, reason: posixError(operation: "remove empty folder", at: folder).localizedDescription)])
        }
        return completed
    }

    /// Validates a batch rename and returns destinations without changing the file system.
    public static func planRenames(_ changes: [RenameChange]) throws -> RenamePlan {
        guard !changes.isEmpty else { throw FinderFileActionError.invalidRequest("Choose at least one rename.") }
        var sourceKeys = Set<String>()
        var destinationKeys = Set<String>()
        var renames: [Rename] = []
        for change in changes {
            _ = try metadata(at: change.source)
            let sourceKey = pathKey(change.source)
            guard sourceKeys.insert(sourceKey).inserted else {
                throw FinderFileActionError.invalidRequest("A source item appears more than once in the rename plan.")
            }
            let safeName = try validatedName(change.newName)
            let destination = change.source.deletingLastPathComponent().appendingPathComponent(safeName)
            guard destinationKeys.insert(pathKey(destination)).inserted else {
                throw FinderFileActionError.invalidRequest("Two items cannot be renamed to the same destination.")
            }
            renames.append(Rename(source: change.source, destination: destination))
        }

        for rename in renames where itemExists(at: rename.destination)
            && !sourceKeys.contains(pathKey(rename.destination)) {
            throw FinderFileActionError.destinationExists(rename.destination)
        }
        return RenamePlan(renames: renames)
    }

    private static func createExclusive(in directory: URL,
                                        named name: String,
                                        collisionPolicy: CollisionPolicy,
                                        create: (URL) throws -> Void) throws -> URL {
        for index in 0..<uniqueNameAttempts {
            let candidateName: String
            if index == 0 { candidateName = name }
            else {
                guard collisionPolicy == .makeUnique else {
                    throw FinderFileActionError.destinationExists(directory.appendingPathComponent(name))
                }
                candidateName = numberedName(name, index: index + 1)
            }
            let candidate = directory.appendingPathComponent(candidateName)
            do {
                try create(candidate)
                return candidate
            } catch FinderFileActionError.destinationExists(_) {
                if collisionPolicy == .fail { throw FinderFileActionError.destinationExists(candidate) }
            } catch {
                throw error
            }
        }
        throw FinderFileActionError.invalidRequest("Could not find an unused file name after \(uniqueNameAttempts) attempts.")
    }

    private static func writeExclusively(_ data: Data, to url: URL) throws {
        let descriptor = url.path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o666)) }
        guard descriptor >= 0 else { throw posixError(operation: "create file", at: url) }
        defer { _ = close(descriptor) }

        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                return Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
            }
            if count < 0 {
                if errno == EINTR { continue }
                let reason = String(cString: strerror(errno))
                throw FinderFileActionError.operationFailed(operation: "write; a partial file may remain",
                                                            url: url,
                                                            reason: "Wrote \(offset) of \(data.count) bytes: \(reason)")
            }
            guard count > 0 else {
                throw FinderFileActionError.operationFailed(operation: "write; a partial file may remain",
                                                            url: url,
                                                            reason: "Wrote \(offset) of \(data.count) bytes before the system stopped writing.")
            }
            offset += count
        }
    }

    private static func validatedName(_ name: String) throws -> String {
        let normalized = name.precomposedStringWithCanonicalMapping
        guard !normalized.isEmpty,
              normalized != ".",
              normalized != "..",
              !normalized.contains("/"),
              !normalized.contains("\\"),
              !normalized.unicodeScalars.contains(where: { $0.value == 0 || CharacterSet.controlCharacters.contains($0) })
        else { throw FinderFileActionError.invalidName(name) }
        return normalized
    }

    private static func numberedName(_ name: String, index: Int) -> String {
        let path = name as NSString
        let ext = path.pathExtension
        let stem = ext.isEmpty ? name : path.deletingPathExtension
        return ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
    }

    private static func metadata(at url: URL) throws -> Metadata {
        try requireFileURL(url)
        var info = stat()
        let result = url.path.withCString { Darwin.lstat($0, &info) }
        guard result == 0 else {
            if errno == ENOENT || errno == ENOTDIR { throw FinderFileActionError.itemNotFound(url) }
            throw posixError(operation: "inspect", at: url)
        }
        return Metadata(kind: kind(from: info.st_mode), size: Int64(info.st_size))
    }

    private static func kind(from mode: mode_t) -> ItemKind {
        if (mode & mode_t(S_IFMT)) == mode_t(S_IFREG) { return .file }
        if (mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) { return .directory }
        if (mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) { return .symbolicLink }
        return .other
    }

    private static func treeSize(_ info: Metadata) -> Int64? {
        switch info.kind {
        case .directory: return nil
        case .file, .symbolicLink: return info.size
        case .other: return nil
        }
    }

    private static func children(of directory: URL) throws -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(at: directory,
                                                              includingPropertiesForKeys: nil,
                                                              options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            throw FinderFileActionError.operationFailed(operation: "list directory", url: directory,
                                                        reason: error.localizedDescription)
        }
    }

    private static func requireFileURL(_ url: URL) throws {
        guard url.isFileURL else {
            throw FinderFileActionError.invalidRequest("Only local file URLs are supported: \(url.absoluteString)")
        }
    }

    private static func requireDirectory(_ url: URL) throws {
        let info = try metadata(at: url)
        guard info.kind == .directory else { throw FinderFileActionError.notDirectory(url) }
    }

    private static func requireMutableItem(_ url: URL) throws {
        let info = try metadata(at: url)
        guard info.kind != .symbolicLink else {
            throw FinderFileActionError.unsupported(url, "Changing attributes on a symbolic link is unsupported")
        }
    }

    private static func requireNewDestination(_ url: URL) throws {
        try requireFileURL(url)
        if itemExists(at: url) { throw FinderFileActionError.destinationExists(url) }
    }

    private static func itemExists(at url: URL) -> Bool {
        var info = stat()
        return url.path.withCString { Darwin.lstat($0, &info) == 0 }
    }

    private static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let path = nameKey(candidate.resolvingSymlinksInPath().standardizedFileURL.path)
        let parent = nameKey(ancestor.resolvingSymlinksInPath().standardizedFileURL.path)
        guard path != parent else { return false }
        return path.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }

    private static func pathKey(_ url: URL) -> String {
        nameKey(url.standardizedFileURL.path)
    }

    private static func nameKey(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                            locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func escapeMarkdownLabel(_ label: String) -> String {
        var result = ""
        for character in label {
            if "\\`*_{}[]()#+-.!|>".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }

    private static func posixError(operation: String, at url: URL) -> FinderFileActionError {
        let code = POSIXErrorCode(rawValue: errno) ?? .EIO
        if code == .EEXIST { return .destinationExists(url) }
        return .operationFailed(operation: operation, url: url, reason: String(cString: strerror(errno)))
    }
}
