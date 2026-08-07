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
        let isSystem: Bool

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

    /// Apps that belong to the system wherever their bundle really sits. An
    /// app inside these is never offered for uninstalling, and only shows up
    /// in the pickers that ask for system apps too.
    private static let systemPathPrefixes = ["/System/", "/Library/Apple/"]

    /// Apps the user knows well but that no application folder holds. The file
    /// manager cannot reach them by walking, so they are resolved by identity
    /// instead of by a hardcoded path.
    private static let systemBundleIDsOutsideFolders = ["com.apple.finder"]

    static func isSystemApplication(at url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return systemPathPrefixes.contains { path.hasPrefix($0) }
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
            // Hidden entries are deliberately NOT skipped: the browser that
            // ships with macOS lives on the system volume and is exposed in
            // /Applications as a hidden symlink, so skipping them left it out
            // of every picker. Only bundles ending in .app are taken anyway.
            guard let enumerator = fm.enumerator(at: root,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsPackageDescendants]) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                // A link's target decides whether the app is the system's:
                // the path inside the application folder says nothing.
                let resolved = url.resolvingSymlinksInPath()
                let isSystemApp = isSystemApplication(at: url)
                guard includeSystemApplications || !isSystemApp else { continue }
                guard seen.insert(resolved.standardizedFileURL.path).inserted else { continue }
                apps.append(app(at: url, fileManager: fm))
            }
        }

        if includeSystemApplications {
            for bundleID in systemBundleIDsOutsideFolders {
                guard let url = url(for: bundleID),
                      seen.insert(url.resolvingSymlinksInPath().standardizedFileURL.path).inserted else {
                    continue
                }
                apps.append(app(at: url, fileManager: fm))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func app(at url: URL, fileManager fm: FileManager) -> InstalledApp {
        var name = fm.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return InstalledApp(id: url.standardizedFileURL.path,
                            name: name,
                            bundleID: Bundle(url: url)?.bundleIdentifier,
                            url: url,
                            isSystem: isSystemApplication(at: url))
    }

    static func installedBundleApplications(excluding excludedBundleIDs: Set<String>,
                                            includeRunningApplications: Bool = false) -> [InstalledApp] {
        var apps = installedApplications(includeSystemApplications: true)
        if includeRunningApplications {
            apps += NSWorkspace.shared.runningApplications.compactMap { runningApp in
                guard runningApp.activationPolicy == .regular,
                      let bundleID = runningApp.bundleIdentifier,
                      !bundleID.isEmpty,
                      let url = runningApp.bundleURL,
                      url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    return nil
                }
                let name = runningApp.localizedName ?? FileManager.default.displayName(atPath: url.path)
                return InstalledApp(id: url.standardizedFileURL.path,
                                    name: name,
                                    bundleID: bundleID,
                                    url: url,
                                    isSystem: isSystemApplication(at: url))
            }
        }

        var seen = Set<String>()
        return apps.filter { app in
            guard let bundleID = app.bundleID,
                  !excludedBundleIDs.contains(bundleID),
                  seen.insert(bundleID).inserted else { return false }
            return true
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
