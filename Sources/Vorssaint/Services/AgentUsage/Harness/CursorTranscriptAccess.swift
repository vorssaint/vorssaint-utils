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

        func read(into bytes: UnsafeMutableRawBufferPointer, at offset: UInt64) -> Bool {
            withExtendedLifetime(handle) {
                pread(handle.fileDescriptor, bytes.baseAddress, bytes.count, off_t(offset)) == bytes.count
            }
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

/// The checksum follows the bytes handed to the parser. A growing transcript
/// can also have edits anywhere before the old EOF, even when both edges match.
struct CursorTranscriptPrefix {
    private static let basis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static func mix(_ bytes: UnsafeRawBufferPointer, into value: UInt64) -> UInt64 {
        bytes.reduce(value) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }

    /// A saved cursor resumes at the last committed line boundary. Live reads
    /// also verify the unfinished bytes they carry into the next append.
    private(set) var boundaryChecksum: UInt64
    private var checksum: UInt64
    init(restoring value: UInt64? = nil) {
        boundaryChecksum = value ?? Self.basis
        checksum = boundaryChecksum
    }

    mutating func append(_ chunk: Data, pending: Int) {
        chunk.withUnsafeBytes { bytes in
            let committed = bytes.count - pending
            if committed >= 0 {
                boundaryChecksum = Self.mix(UnsafeRawBufferPointer(rebasing: bytes[..<committed]), into: checksum)
                checksum = Self.mix(UnsafeRawBufferPointer(rebasing: bytes[committed...]), into: boundaryChecksum)
            } else {
                checksum = Self.mix(bytes, into: checksum)
            }
        }
    }

    private struct Check {
        let end: UInt64
        let expected: UInt64
        var offset: UInt64 = 0
        var value = CursorTranscriptPrefix.basis

        mutating func advance(in file: CursorTranscriptAccess.File, budget: UInt64) -> Bool {
            let count = Int(min(budget, end - offset))
            var buffer = [UInt8](repeating: 0, count: count)
            let ok = buffer.withUnsafeMutableBytes { file.read(into: $0, at: offset) }
            guard ok else { return false }
            value = buffer.withUnsafeBytes { CursorTranscriptPrefix.mix($0, into: value) }
            offset += UInt64(count)
            return offset < end || value == expected
        }
    }

    private var check: Check?
    private var queued = false
    var needsVerification: Bool { check != nil || queued }
    var checkedBytes: UInt64 { check?.offset ?? 0 }

    mutating func matches(_ file: CursorTranscriptAccess.File, offset: UInt64, grew: Bool) -> Bool {
        if grew && offset > 0 { queued = true }
        if check == nil && queued {
            check = Check(end: offset, expected: checksum)
            queued = false
        }
        guard var pass = check else { return true }
        // Freeze each pass's endpoint. An edit behind its current position
        // schedules another pass while this one continues toward its endpoint.
        let budget = grew ? min(64 << 10, max(8192, pass.end / 8)) : 1 << 20
        guard pass.advance(in: file, budget: budget) else { return false }
        check = pass.offset == pass.end ? nil : pass
        return true
    }

    /// Nil leaves the checkpoint untouched when a stop interrupts verification.
    static func matches(_ file: CursorTranscriptAccess.File, upTo offset: UInt64, checksum: UInt64,
                        shouldContinue: () -> Bool) -> Bool? {
        guard offset <= UInt64(max(0, file.info.st_size)) else { return false }
        var pass = Check(end: offset, expected: checksum)
        repeat {
            guard shouldContinue() else { return nil }
            guard pass.advance(in: file, budget: 1 << 20) else { return false }
        } while pass.offset < offset
        return true
    }
}
