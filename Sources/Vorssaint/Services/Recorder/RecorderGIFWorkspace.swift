// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Scratch belongs to one export, in the app's private macOS temporary folder.
/// Remove it on every normal exit. A crash releases its file lock, so launch
/// and the next export can sweep it without an age guess or a PID reuse race.
/// Live exports in other processes are protected by their own locks.
final class RecorderGIFWorkspace {
    /// A process without a bundle, such as the test binary, keeps its scratch
    /// under its own name instead of in the app's folder.
    static var root: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
                                    isDirectory: true)
            .appendingPathComponent("GIF Exports", isDirectory: true)
    }

    let folder: URL
    var fileURL: URL { folder.appendingPathComponent("animation.gif") }
    private var lease: Int32

    init(root: URL = RecorderGIFWorkspace.root) throws {
        let rootLease = try Self.lockRoot(root)
        defer { Darwin.close(rootLease) }
        Self.sweepUnlocked(root: root)
        folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        lease = Self.openLease(in: folder)
        guard lease >= 0, flock(lease, LOCK_EX | LOCK_NB) == 0 else {
            if lease >= 0 { Darwin.close(lease) }
            lease = -1
            try? FileManager.default.removeItem(at: folder)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    deinit { discard() }

    func discard() {
        guard lease >= 0 else { return }
        // Keep the lock until removal completes. An unsuccessful removal will
        // be retried by a later sweep once the lease is released.
        try? FileManager.default.removeItem(at: folder)
        Darwin.close(lease)
        lease = -1
    }

    static func sweep(root: URL = RecorderGIFWorkspace.root) {
        guard FileManager.default.fileExists(atPath: root.path),
              let rootLease = try? lockRoot(root) else { return }
        defer { Darwin.close(rootLease) }
        sweepUnlocked(root: root)
    }

    private static func lockRoot(_ root: URL) throws -> Int32 {
        guard PrivateFileStore.createDirectory(at: root, container: root) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let lease = openLease(in: root)
        // Serialize folder creation with sweeping so a new, as-yet-unlocked
        // directory can never be mistaken for an abandoned export.
        guard lease >= 0, flock(lease, LOCK_EX) == 0 else {
            if lease >= 0 { Darwin.close(lease) }
            throw CocoaError(.fileWriteUnknown)
        }
        return lease
    }

    private static func openLease(in folder: URL) -> Int32 {
        Darwin.open(folder.appendingPathComponent(".lease").path,
                    O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    }

    private static func sweepUnlocked(root: URL) {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for folder in folders {
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let lease = openLease(in: folder)
            guard lease >= 0 else { continue }
            if flock(lease, LOCK_EX | LOCK_NB) == 0 {
                try? manager.removeItem(at: folder)
            }
            Darwin.close(lease)
        }
    }
}
