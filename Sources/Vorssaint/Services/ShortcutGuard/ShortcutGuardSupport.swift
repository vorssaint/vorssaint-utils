// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShortcutGuardSupport {
    static func isOwnProcessEvent(sourceProcessID: Int64, ownProcessID: Int64) -> Bool {
        sourceProcessID == ownProcessID
    }

    static func shouldBlock(frontmostIdentity: String?,
                            selectedIdentities: Set<String>,
                            shortcut: GlobalShortcut,
                            blockedShortcuts: Set<GlobalShortcut>) -> Bool {
        guard let frontmostIdentity else { return false }
        return selectedIdentities.contains(frontmostIdentity)
            && blockedShortcuts.contains(shortcut)
    }

    static func mergingIdentities(existing: [String],
                                  candidates: [String]) -> (values: [String], addedCount: Int) {
        var seen = Set<String>()
        var values: [String] = []

        for identity in existing where !identity.isEmpty {
            if seen.insert(identity).inserted {
                values.append(identity)
            }
        }

        var addedCount = 0
        for identity in candidates where !identity.isEmpty {
            if seen.insert(identity).inserted {
                values.append(identity)
                addedCount += 1
            }
        }
        return (values, addedCount)
    }

    static func acceptsPickedURL(_ url: URL, fileManager: FileManager = .default) -> Bool {
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
           Bundle(url: url) != nil {
            return true
        }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? true
        return !isDirectory && fileManager.isExecutableFile(atPath: url.path)
    }
}
