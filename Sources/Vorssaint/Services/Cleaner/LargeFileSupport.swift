// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for the large files finder, kept free of AppKit and the scan
/// itself so tests can pin them. The finder only ever offers regular files
/// that sit inside the home folder, outside Library and the Trash.
enum LargeFileSupport {
    /// Size thresholds offered in the picker, smallest first.
    static let minimumSizes: [Int64] = [100_000_000, 500_000_000, 1_000_000_000]
    /// Age filters in days; 0 means no age filter.
    static let ageFilterDays: [Int] = [0, 90, 365]
    /// The list stops here so a huge result stays readable.
    static let maxResults = 200

    /// Folders directly inside home that the walk never enters. Library holds
    /// app data that is not the user's to clean here, and the Trash is its own
    /// tool.
    private static let skippedHomeChildren: Set<String> = ["Library", ".Trash"]

    /// Whether the walk should skip a directory entirely: hidden folders
    /// anywhere, and Library or the Trash directly under home.
    static func shouldSkipDirectory(_ url: URL, home: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return true }
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        return parent == home.standardizedFileURL.path && skippedHomeChildren.contains(name)
    }

    /// Whether a file found by the walk belongs in the results. An age filter
    /// needs a last-opened date: a file without one is left out rather than
    /// guessed at.
    static func qualifies(size: Int64, lastOpened: Date?, minimumSize: Int64,
                          olderThanDays: Int, now: Date = Date()) -> Bool {
        guard size >= minimumSize else { return false }
        guard olderThanDays > 0 else { return true }
        guard let lastOpened else { return false }
        let cutoff = now.addingTimeInterval(-Double(olderThanDays) * 86_400)
        return lastOpened <= cutoff
    }

    /// The check made again right before a file goes to the Trash, so a stale
    /// list cannot remove something outside what the scan was allowed to see.
    static func mayRemove(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return false }
        let relative = path.dropFirst(homePath.count + 1)
        let components = relative.split(separator: "/").map(String.init)
        guard let first = components.first, !components.isEmpty else { return false }
        if skippedHomeChildren.contains(first) { return false }
        return !components.contains { $0.hasPrefix(".") }
    }

    /// Largest first, trimmed to the cap.
    static func ranked<T>(_ items: [T], size: (T) -> Int64) -> [T] {
        Array(items.sorted { size($0) > size($1) }.prefix(maxResults))
    }
}
