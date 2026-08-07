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
final class RecorderTakeStore {
    static let shared = RecorderTakeStore()

    struct Take: Equatable {
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
        guard let base = manager.urls(for: .applicationSupportDirectory,
                                      in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier
        else { return nil }
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
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
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
        else { return nil }
        return Take(id: id, folder: folder)
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
