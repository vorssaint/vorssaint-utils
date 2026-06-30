// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Small lookups for resolving a bundle identifier to a human name and icon,
/// and for listing apps the user might pick. Shared by the auto-quit exception
/// list and the uninstaller.
enum InstalledApps {
    struct InstalledApp: Identifiable, Equatable {
        let id: String
        let name: String
        let bundleID: String?
        let url: URL

        var icon: NSImage {
            NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    static func icon(for bundleID: String) -> NSImage {
        if let url = url(for: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    static func installedApplications(includeSystemApplications: Bool = false) -> [InstalledApp] {
        let fm = FileManager.default
        var roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true),
        ]
        if includeSystemApplications {
            roots.append(URL(fileURLWithPath: "/System/Applications", isDirectory: true))
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var seen = Set<String>()
        var apps: [InstalledApp] = []

        for root in roots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(at: root,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let bundle = Bundle(url: url)
                var name = fm.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name.removeLast(4) }
                apps.append(InstalledApp(id: path,
                                         name: name,
                                         bundleID: bundle?.bundleIdentifier,
                                         url: url))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func installedBundleApplications(excluding excludedBundleIDs: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return installedApplications(includeSystemApplications: true).filter { app in
            guard let bundleID = app.bundleID,
                  !excludedBundleIDs.contains(bundleID),
                  seen.insert(bundleID).inserted else { return false }
            return true
        }
    }
}
