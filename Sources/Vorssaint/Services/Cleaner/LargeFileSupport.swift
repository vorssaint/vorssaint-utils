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

    /// How safe a file is to remove, judged from its type alone. This is a hint
    /// for the person choosing, never a reason to tick anything for them.
    enum Safety: Equatable {
        /// Installers and archives that normally come from somewhere else.
        case replaceable
        /// Media and documents the person made or collected: maybe the only copy.
        case yours
        /// Data an app depends on, or a type we do not recognise.
        case check
    }

    private static let replaceableExtensions: Set<String> = [
        "dmg", "pkg", "iso", "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
        "ipsw", "xip", "msi", "exe", "deb", "apk",
    ]
    private static let yoursExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mkv", "avi", "mpg", "mpeg", "wmv", "webm", "mts",
        "mp3", "m4a", "wav", "aif", "aiff", "flac", "aac",
        "jpg", "jpeg", "png", "heic", "tif", "tiff", "raw", "dng", "cr2", "cr3", "nef", "arw", "psd",
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers",
        "fcpbundle", "logicx", "prproj", "aep",
    ]

    /// The type-based safety hint. Anything unlisted, including data files an
    /// app may rely on (virtual machines, databases, mail stores), is `.check`.
    static func safety(of url: URL) -> Safety {
        let ext = url.pathExtension.lowercased()
        if replaceableExtensions.contains(ext) { return .replaceable }
        if yoursExtensions.contains(ext) { return .yours }
        return .check
    }

    /// The website a download came from, taken from the first address in the
    /// "where from" list macOS records. Nothing else is shown from that list.
    static func sourceHost(from whereFroms: [String]?) -> String? {
        guard let first = whereFroms?.first, let host = URL(string: first)?.host,
              !host.isEmpty else { return nil }
        return host
    }

    /// Largest first, trimmed to the cap.
    static func ranked<T>(_ items: [T], size: (T) -> Int64) -> [T] {
        Array(items.sorted { size($0) > size($1) }.prefix(maxResults))
    }
}
