// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance's LockedFileIndex (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import Combine
import Foundation

/// Which items Vorssaint has locked and where, so Settings can list them.
/// Only what Finder already shows is kept (the container's path and the name
/// its file name carries), never a password. It lives in a private file on
/// this Mac and is not part of a settings backup.
@MainActor
final class LockedItemIndex: ObservableObject {
    static let shared = LockedItemIndex()

    struct Record: Codable, Identifiable, Hashable {
        /// The container header's item id, also the key of a remembered password.
        let id: String
        var originalName: String
        var isFolder: Bool
        var path: String
        var lockedAt: Date
        var remembered: Bool

        var url: URL { URL(fileURLWithPath: path) }
        var exists: Bool { FileManager.default.fileExists(atPath: path) }
    }

    @Published private(set) var records: [Record] = []

    private static var fileURL: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("PrivacyLock", isDirectory: true)
            .appendingPathComponent("locked-items.json")
    }

    private init() {
        if let url = Self.fileURL, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Record].self, from: data) {
            records = decoded
        }
    }

    func add(_ record: Record) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        save()
    }

    func remove(id: String) {
        records.removeAll { $0.id == id }
        save()
    }

    /// Forgets records whose container is gone, without touching Keychain items
    /// of containers that were only moved: those can still be opened.
    func pruneMissing() {
        let kept = records.filter(\.exists)
        guard kept.count != records.count else { return }
        records = kept
        save()
    }

    func deleteAll() {
        records = []
        if let url = Self.fileURL { try? FileManager.default.removeItem(at: url) }
    }

    private func save() {
        guard let url = Self.fileURL,
              PrivateFileStore.createDirectory(at: url.deletingLastPathComponent()),
              let data = try? JSONEncoder().encode(records) else { return }
        _ = PrivateFileStore.write(data, to: url)
    }
}
