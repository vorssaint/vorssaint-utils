// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where recordings live before they become a file the person keeps.
///
/// A recording is a small folder holding the untouched master, so the editor
/// can always start over from the original pixels instead of from an already
/// rendered result. The person never sees the folder: they see a recording,
/// and then a video file wherever they chose to save it. The folder lives
/// exactly as long as the editor that owns it, so there is never a pile of
/// intermediates nobody asked for.
final class RecorderTakeStore: @unchecked Sendable {
    static let shared = RecorderTakeStore()

    struct Take: Equatable, Sendable {
        let id: UUID
        let folder: URL

        var videoURL: URL { folder.appendingPathComponent(RecorderSupport.takeVideoName) }
        var pointerURL: URL { folder.appendingPathComponent(RecorderSupport.takePointerName) }
        var typingURL: URL { folder.appendingPathComponent(RecorderSupport.takeTypingName) }
        var editURL: URL { folder.appendingPathComponent(RecorderSupport.takeEditName) }
    }

    private let manager = FileManager.default

    private init() {}

    // MARK: - Location

    private var root: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Space left where recordings are written, the way the system reports it
    /// for something the person actually wants to keep.
    func freeBytes() -> Int64 {
        guard let root else { return 0 }
        let probe = manager.fileExists(atPath: root.path)
            ? root
            : manager.homeDirectoryForCurrentUser
        let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // MARK: - Lifecycle

    func makeTake() -> Take? {
        guard let root else { return nil }
        let id = UUID()
        let folder = root.appendingPathComponent(RecorderSupport.takeFolderName(id: id),
                                                 isDirectory: true)
        guard PrivateFileStore.createDirectory(at: folder) else { return nil }
        return Take(id: id, folder: folder)
    }

    /// Gives an ordinary movie the same private, disposable master a screen
    /// recording gets. The copy is intentionally independent: edits or
    /// external changes to either file can never affect the other one.
    func importVideo(at sourceURL: URL) -> Take? {
        guard let take = makeTake() else { return nil }
        guard importVideo(at: sourceURL, into: take) else {
            delete(take)
            return nil
        }
        return take
    }

    /// The file operation is separate from choosing the private folder so the
    /// transactional contract can be exercised without touching app storage.
    func importVideo(at sourceURL: URL, into take: Take) -> Bool {
        guard let values = try? sourceURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize > 0,
              Self.canImport(fileSize: Int64(fileSize), availableBytes: freeBytes(at: take.folder))
        else { return false }

        do {
            try manager.copyItem(at: sourceURL, to: take.videoURL)
            return true
        } catch {
            try? manager.removeItem(at: take.videoURL)
            return false
        }
    }

    static func canImport(fileSize: Int64, availableBytes: Int64) -> Bool {
        guard fileSize > 0, availableBytes >= fileSize else { return false }
        return availableBytes - fileSize >= RecorderSupport.minimumFreeBytesToContinue
    }

    private func freeBytes(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Sharing never accepts a raw caller-supplied URL. The staged master must
    /// still be the regular file inside the exact private recording folder
    /// this store assigned to its id, with no symbolic-link escape.
    func owns(_ take: Take) -> Bool {
        guard let root else { return false }
        let expected = root.appendingPathComponent(RecorderSupport.takeFolderName(id: take.id),
                                                    isDirectory: true)
        guard take.folder.standardizedFileURL == expected.standardizedFileURL,
              let folderValues = try? take.folder.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              folderValues.isDirectory == true,
              folderValues.isSymbolicLink != true,
              let videoValues = try? take.videoURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              videoValues.isRegularFile == true,
              videoValues.isSymbolicLink != true,
              (videoValues.fileSize ?? 0) > 0
        else { return false }
        return true
    }

    func delete(_ take: Take) {
        try? manager.removeItem(at: take.folder)
    }

    /// Turns a finished take into the file the person keeps. The take stays
    /// intact if either step fails, so the editor can still recover it.
    func saveDirectly(_ take: Take, to destination: URL) throws {
        try manager.copyItem(at: take.videoURL, to: destination)
        do {
            try manager.removeItem(at: take.folder)
        } catch {
            try? manager.removeItem(at: destination)
            throw error
        }
    }

    func takes() -> [Take] {
        guard let root,
              let names = try? manager.contentsOfDirectory(atPath: root.path)
        else { return [] }
        return names.compactMap { name in
            guard let id = RecorderSupport.takeID(fromFolderName: name) else { return nil }
            return Take(id: id, folder: root.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// When a take stopped being written, read from the master itself so no
    /// extra bookkeeping file has to stay in sync with reality.
    func finishedAt(_ take: Take) -> Date? {
        let values = try? take.videoURL.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    // MARK: - Sweep

    /// Removes folders no editor owns any more: what a crash or a quit left
    /// behind. The recordings that still have an editor on screen are named by
    /// the caller and left alone whatever their age, so an editor left open
    /// overnight never has its master taken out from under it.
    func sweep(keeping owned: Set<UUID> = [], now: Date = Date()) {
        let all = takes().filter { !owned.contains($0.id) }
        guard !all.isEmpty else { return }
        var byID: [UUID: Take] = [:]
        let described: [(id: UUID, finishedAt: Date?, createdAt: Date?)] = all.map { take in
            byID[take.id] = take
            let created = try? take.folder.resourceValues(forKeys: [.creationDateKey]).creationDate
            return (id: take.id, finishedAt: finishedAt(take), createdAt: created)
        }
        for id in RecorderSupport.orphanTakeIDs(described, now: now) {
            if let take = byID[id] { delete(take) }
        }
    }
}
