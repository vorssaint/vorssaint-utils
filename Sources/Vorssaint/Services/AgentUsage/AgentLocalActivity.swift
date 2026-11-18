// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Discovers the latest chat activity timestamps for agents that keep no usage
/// logs of their own, such as Antigravity, by inspecting the modification dates
/// of their local session files.
enum AgentLocalActivity {
    /// The default root directories for the provider's local files.
    static func defaultRoots(for provider: AgentProvider,
                             home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        switch provider {
        case .antigravity:
            return [
                home.appending(path: ".gemini/antigravity-cli/conversations"),
                home.appending(path: ".gemini/antigravity/conversations")
            ]
        default:
            return []
        }
    }

    /// Finds the latest chat activity timestamp across multiple candidate roots.
    static func latestActivity(for provider: AgentProvider, roots: [URL]) -> Date? {
        roots.compactMap { latestActivity(for: provider, root: $0) }.max()
    }

    /// Finds the latest chat activity timestamp for the given provider under the injected root URL.
    static func latestActivity(for provider: AgentProvider, root: URL) -> Date? {
        switch provider {
        case .antigravity:
            return latestAntigravityActivity(root: root)
        default:
            return nil
        }
    }

    /// Finds the newest modification date among regular files in the given list.
    static func newest(of files: [URL]) -> Date? {
        files.compactMap { file -> Date? in
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? true else { return nil }
            return (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }.max()
    }

    /// Finds the latest chat activity timestamp for Antigravity under root.
    /// Checks the conversations directory for the newest entry modification date,
    /// including SQLite WAL files (.db-wal), skipping lock files.
    static func latestAntigravityActivity(root: URL) -> Date? {
        let conversationsCandidate = root.appending(path: "conversations")
        let dir = FileManager.default.fileExists(atPath: conversationsCandidate.path)
            ? conversationsCandidate
            : root

        guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                       includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                                       options: [.skipsHiddenFiles]) else {
            return nil
        }
        let eligible = files.filter { !$0.lastPathComponent.hasSuffix(".lock") }
        return newest(of: eligible)
    }
}
