// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Sonoma+ Index.plist + kill WallpaperAgent = Show on all Spaces
// (setDesktopImageURL alone only hits the current Space)
//
// Backup policy:
// - One-shot copy of Index.plist before the first apply-all write, kept under
//   the app Application Support folder (cleared with the rest of the app).
// - Feature uninstall deletes that copy. Later applies never overwrite it.
// - No in-app restore path; AppKit current-space apply remains the soft fallback
//   when the store patch cannot run.
enum WallpaperStore {
    static var indexURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return support
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("Store", isDirectory: true)
            .appendingPathComponent("Index.plist", isDirectory: false)
    }

    // lives with the app, not in the system wallpaper store
    static var backupURL: URL {
        let fallback = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/com.vorssaint.utils",
                                    isDirectory: true)
        let container = PrivateFileStore.containerURL ?? fallback
        return container.appendingPathComponent("WallpaperIndex.vorssaint-bak",
                                                isDirectory: false)
    }

    // leftover from when the bak lived next to Index.plist
    private static var legacySystemBackupURL: URL {
        indexURL.deletingLastPathComponent()
            .appendingPathComponent("Index.plist.vorssaint-bak", isDirectory: false)
    }

    // move a pristine system-side bak into App Support once (older builds)
    static func migrateLegacyBackupIfNeeded() {
        let backup = backupURL
        let legacy = legacySystemBackupURL
        guard !FileManager.default.fileExists(atPath: backup.path),
              FileManager.default.fileExists(atPath: legacy.path)
        else { return }
        let parent = backup.deletingLastPathComponent()
        _ = PrivateFileStore.createDirectory(at: parent)
        do {
            try FileManager.default.copyItem(at: legacy, to: backup)
            try? FileManager.default.removeItem(at: legacy)
        } catch {
            // leave legacy in place for a later apply/migrate
        }
    }

    @discardableResult
    static func setImageOnAllSpaces(_ imageURL: URL,
                                    shouldContinue: () -> Bool = { true }) -> Bool {
        let url = imageURL.standardizedFileURL
        guard shouldContinue() else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let index = indexURL
        guard FileManager.default.fileExists(atPath: index.path) else { return false }

        let data: Data
        do {
            data = try Data(contentsOf: index)
        } catch {
            return false
        }
        guard shouldContinue() else { return false }
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var root = try? PropertyListSerialization.propertyList(
            from: data, options: [.mutableContainers], format: &format
        ) as? [String: Any]
        else { return false }

        guard WallpaperSupport.patchStoreRoot(&root, imageURL: url) else { return false }
        guard shouldContinue() else { return false }

        guard ensureBackup(of: index) else { return false }
        guard shouldContinue() else { return false }

        guard let written = try? PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        ) else { return false }

        guard shouldContinue() else { return false }
        do {
            try written.write(to: index, options: .atomic)
        } catch {
            return false
        }

        guard shouldContinue() else { return false }
        // agent keeps the old tree until restarted
        _ = Shell.run("/usr/bin/killall", ["WallpaperAgent"])
        return true
    }

    // first pre-feature copy only; never overwrite with a later apply
    private static func ensureBackup(of index: URL) -> Bool {
        migrateLegacyBackupIfNeeded()
        let backup = backupURL
        if FileManager.default.fileExists(atPath: backup.path) { return true }
        let parent = backup.deletingLastPathComponent()
        _ = PrivateFileStore.createDirectory(at: parent)
        do {
            try FileManager.default.copyItem(at: index, to: backup)
        } catch {
            return false
        }
        return FileManager.default.fileExists(atPath: backup.path)
    }

    static func removeBackup() {
        let backup = backupURL
        if FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.removeItem(at: backup)
        }
        let legacy = legacySystemBackupURL
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }
}
