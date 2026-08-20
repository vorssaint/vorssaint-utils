// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreServices
import Foundation

/// The other names macOS itself knows an app by.
///
/// Spotlight keeps a list of aliases for every bundle, and no key inside an
/// app's own Info.plist exposes them. Without those aliases the bar can only
/// find an app by the name written under its icon, which is not always the
/// name the person learned.
///
/// Nothing here runs while the bar is closed, and nothing is written to disk.
enum SpotlightNames {
    /// The attribute is real and documented in `MDItem.h`, but no constant is
    /// exported for it, so it is named directly.
    private static let attribute = "kMDItemAlternateNames" as CFString

    private struct Entry {
        let modified: Date?
        let names: [String]
    }

    private static let lock = NSLock()
    private static var cache: [String: Entry] = [:]

    /// The aliases of every bundle handed in, keyed by path, with the bundles
    /// that have none left out.
    ///
    /// One Spotlight round trip costs about a millisecond, and the app scan
    /// runs again every time the bar opens, so an answer is reused until the
    /// bundle itself changes. Each pass keeps only what it looked at, so an
    /// app that was removed leaves the cache with it instead of the cache
    /// growing for as long as the app runs.
    /// The same apps, each carrying the other names macOS knows it by. The
    /// enrichment lives here rather than in the scan itself, so the pickers
    /// that only want a list of apps never pay Spotlight for aliases nobody
    /// is going to type into them.
    static func enriching(_ apps: [InstalledApps.InstalledApp]) -> [InstalledApps.InstalledApp] {
        let found = names(forBundlesAt: apps.map(\.url))
        guard !found.isEmpty else { return apps }
        return apps.map { app in
            guard let names = found[app.url.standardizedFileURL.path] else { return app }
            var enriched = app
            enriched.alternateNames = names
            return enriched
        }
    }

    static func names(forBundlesAt urls: [URL]) -> [String: [String]] {
        let previous = lock.withLock { cache }
        var next: [String: Entry] = [:]
        next.reserveCapacity(urls.count)
        var result: [String: [String]] = [:]
        for url in urls {
            let path = url.standardizedFileURL.path
            guard next[path] == nil else { continue }
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            let entry: Entry
            if let cached = previous[path], cached.modified == modified {
                entry = cached
            } else {
                entry = Entry(modified: modified, names: read(atPath: path, url: url))
            }
            next[path] = entry
            if !entry.names.isEmpty { result[path] = entry.names }
        }
        lock.withLock { cache = next }
        return result
    }

    private static func read(atPath path: String, url: URL) -> [String] {
        guard let item = MDItemCreate(nil, path as CFString),
              let raw = MDItemCopyAttribute(item, attribute) as? [String]
        else { return [] }
        return SpotlightNamesSupport.usableAlternateNames(
            raw,
            displayName: url.deletingPathExtension().lastPathComponent,
            fileName: url.lastPathComponent)
    }
}
