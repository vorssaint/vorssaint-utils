// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

/// A lease spans journal preparation, authorization and completion. A second
/// app instance cannot overwrite or delete recovery belonging to that lease.
final class PasswordLengthRecovery {
    private let url: URL
    private let fd: Int32

    init(url: URL) throws {
        self.url = url
        fd = open(url.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw PasswordLengthPolicy.Failure.unavailable }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw PasswordLengthPolicy.Failure.conflict
        }
    }

    deinit { _ = flock(fd, LOCK_UN); close(fd) }

    func read() throws -> PasswordLengthPolicy.Snapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 256 * 1024 else { throw PasswordLengthPolicy.Failure.invalid }
        return try JSONDecoder().decode(PasswordLengthPolicy.Snapshot.self, from: data)
    }

    func create(_ snapshot: PasswordLengthPolicy.Snapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 256 * 1024 else { throw PasswordLengthPolicy.Failure.invalid }
        let temporary = url.appendingPathExtension(UUID().uuidString)
        let output = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
        guard output >= 0 else { throw PasswordLengthPolicy.Failure.unavailable }
        defer { close(output); unlink(temporary.path) }
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let count = Darwin.write(output, bytes.baseAddress!.advanced(by: written), bytes.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw PasswordLengthPolicy.Failure.unavailable }
                written += count
            }
        }
        guard fsync(output) == 0 else { throw PasswordLengthPolicy.Failure.unavailable }
        // Atomic publication without replacement; stale writers cannot clobber it.
        guard link(temporary.path, url.path) == 0 else { throw PasswordLengthPolicy.Failure.conflict }
    }

    func remove(matching snapshot: PasswordLengthPolicy.Snapshot) throws {
        guard let existing = try read(), try existing.equivalent(to: snapshot) else {
            throw PasswordLengthPolicy.Failure.conflict
        }
        try FileManager.default.removeItem(at: url)
    }
}
