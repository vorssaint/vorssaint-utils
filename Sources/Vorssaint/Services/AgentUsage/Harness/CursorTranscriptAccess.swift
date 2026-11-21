// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// The root has already been resolved by AgentLogRoot. Never resolve a link
/// in a transcript path: the same open that checks the path supplies the
/// descriptor used for enumeration, metadata, checksums and actual reads.
struct CursorTranscriptAccess {
    let root: URL

    /// Resolve descendants relative to an opened directory. Callers supply
    /// only admitted transcript components, never an absolute path or "..".
    private func descriptor(for relative: String, flags: Int32) -> Int32 {
        let options = flags | O_NOFOLLOW_ANY | O_NONBLOCK | O_CLOEXEC
        if relative.isEmpty { return open(root.path, options) }
        let parent = open(root.path, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW_ANY | O_CLOEXEC)
        guard parent >= 0 else { return -1 }
        defer { close(parent) }
        return openat(parent, relative, options)
    }

    var exists: Bool {
        let fd = descriptor(for: "", flags: O_EVTONLY | O_DIRECTORY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    func entries(at components: [String]) -> [String] {
        for name in components {
            guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.utf8.contains(0) else { return [] }
        }
        let fd = descriptor(for: components.joined(separator: "/"), flags: O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { return [] }
        guard let stream = fdopendir(fd) else { close(fd); return [] }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: &entry.pointee.d_name) { bytes in
                String(bytes: bytes.prefix(length), encoding: .utf8)
            }
            if let name, !name.hasPrefix(".") { names.append(name) }
        }
        return names
    }

    struct File {
        let handle: FileHandle
        let info: stat

        func fingerprint(upTo offset: UInt64) -> UInt64? {
            withExtendedLifetime(handle) { AgentLogReader.fingerprint(handle.fileDescriptor, upTo: offset) }
        }
    }

    func info(at path: String) -> stat? {
        guard let file = openFile(at: path, mode: O_EVTONLY) else { return nil }
        defer { try? file.handle.close() }
        return file.info
    }

    func openFile(at path: String, mode: Int32 = O_RDONLY) -> File? {
        guard !path.utf8.contains(0), AgentLogRoot(provider: .cursor, url: root).accepts(path) else { return nil }
        let relative = String(path.dropFirst(root.path.count + 1))
        let fd = descriptor(for: relative, flags: mode)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { close(fd); return nil }
        return File(handle: FileHandle(fileDescriptor: fd, closeOnDealloc: true), info: info)
    }
}
