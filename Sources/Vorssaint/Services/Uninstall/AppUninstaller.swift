// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Finds the files an app leaves around — caches, preferences, logs, support
/// folders, containers — and moves the ones you pick to the Trash, then reports
/// the space recovered. Everything goes to the Trash (reversible), never an
/// unrecoverable delete, so the flow stays safe.
final class AppUninstaller: ObservableObject {
    static let shared = AppUninstaller()

    enum Phase: Equatable {
        case empty
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: Int)
    }

    struct Target: Equatable {
        let name: String
        let bundleID: String?
        let url: URL
        let icon: NSImage

        static func == (lhs: Target, rhs: Target) -> Bool { lhs.url == rhs.url }
    }

    enum Category: Int, CaseIterable {
        case app, support, caches, preferences, containers, logs, state, other

        var sortRank: Int { rawValue }
    }

    struct Leftover: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let category: Category
        let size: Int64
        var include: Bool = true

        var name: String { url.lastPathComponent }

        static func == (lhs: Leftover, rhs: Leftover) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var target: Target?
    @Published var items: [Leftover] = []

    private init() {}

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    // MARK: - Selection & scan

    /// Reads an app bundle and starts scanning for its leftovers.
    func select(appURL: URL) {
        guard let bundle = Bundle(url: appURL) else { return }
        // System apps are SIP-protected and their support data is live OS
        // state; removing either would be wrong, so refuse the selection.
        guard !appURL.standardizedFileURL.path.hasPrefix("/System") else { return }
        // The bundle id and name become path components of the scan. Reject
        // values that could traverse out of the scanned roots (a hostile
        // Info.plist could otherwise make user folders look like leftovers).
        let bundleID = bundle.bundleIdentifier.flatMap { id in
            id.contains("/") || id.contains("..") ? nil : id
        }
        var name = FileManager.default.displayName(atPath: appURL.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        if name.contains("/") || name.contains("..") { name = "" }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        target = Target(name: name, bundleID: bundleID, url: appURL, icon: icon)
        items = []
        phase = .scanning

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = Self.collect(bundleID: bundleID, name: name, appURL: appURL)
            DispatchQueue.main.async {
                // Drop the result if the user picked a different app (or reset)
                // while this scan was running — never show A's files under B.
                guard let self, self.phase == .scanning, self.target?.url == appURL else { return }
                self.items = found
                self.phase = .results
            }
        }
    }

    func setInclude(_ include: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    func reset() {
        target = nil
        items = []
        phase = .empty
    }

    // MARK: - Removal

    func removeSelected() {
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty else { return }
        phase = .removing

        // Quit a running copy first so its files aren't busy; terminate() still
        // lets it prompt to save.
        if let bundleID = target?.bundleID {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                app.terminate()
            }
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let fm = FileManager.default
            var freed: Int64 = 0
            var stubborn: [Leftover] = []
            for item in chosen {
                do {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                    freed += item.size
                } catch {
                    stubborn.append(item)
                }
            }

            // Items we lack rights for (root-owned apps, /Library files) go
            // through Finder, which shows the administrator prompt and moves
            // them to the Trash exactly like a drag would. One batch, one
            // prompt; afterwards whatever still exists counts as failed.
            var failed = 0
            if !stubborn.isEmpty {
                Self.trashViaFinder(stubborn.map(\.url))
                for item in stubborn {
                    if fm.fileExists(atPath: item.url.path) {
                        failed += 1
                    } else {
                        freed += item.size
                    }
                }
            }

            DispatchQueue.main.async {
                // The user may have dismissed the flow while files moved.
                guard let self, self.phase == .removing else { return }
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
            }
        }
    }

    /// Asks Finder to trash `urls` in one batch. Finder owns the privilege
    /// elevation (the standard administrator prompt) and the result is a
    /// reversible move to the Trash, never a permanent delete. Waits until the
    /// user answers the prompt; a cancel simply leaves the items in place.
    private static func trashViaFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else { return }
        // In-process Apple Events (see AppleScriptRunner): the Finder Automation
        // consent is attributed to this app and re-requested if it was lost,
        // instead of a fragile osascript subprocess. Paths are embedded as
        // escaped string literals (no argv).
        let targets = urls
            .map { "set end of targets to POSIX file \(AppleScriptRunner.literal($0.path))" }
            .joined(separator: "\n")
        let source = """
        set targets to {}
        \(targets)
        tell application "Finder" to delete targets
        """
        _ = AppleScriptRunner.run(source)
    }

    // MARK: - Scanning

    private static func collect(bundleID: String?, name: String, appURL: URL) -> [Leftover] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let lib = home + "/Library"
        var paths: [(URL, Category)] = [(appURL, .app)]

        func add(_ path: String, _ category: Category) {
            let url = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: url.path) { paths.append((url, category)) }
        }
        func addMatches(in dir: String, _ category: Category, where matches: (String) -> Bool) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for entry in entries where matches(entry) {
                paths.append((URL(fileURLWithPath: dir).appendingPathComponent(entry), category))
            }
        }

        if let id = bundleID {
            add("\(lib)/Application Support/\(id)", .support)
            add("\(lib)/Containers/\(id)", .containers)
            add("\(lib)/Caches/\(id)", .caches)
            add("\(lib)/Preferences/\(id).plist", .preferences)
            add("\(lib)/Saved Application State/\(id).savedState", .state)
            add("\(lib)/HTTPStorages/\(id)", .caches)
            add("\(lib)/HTTPStorages/\(id).binarycookies", .caches)
            add("\(lib)/WebKit/\(id)", .caches)
            add("\(lib)/Application Scripts/\(id)", .containers)
            add("\(lib)/Cookies/\(id).binarycookies", .caches)
            add("\(lib)/Logs/\(id)", .logs)
            addMatches(in: "\(lib)/Preferences/ByHost", .preferences) { matchesBundleScopedName($0, bundleID: id) }
            addMatches(in: "\(lib)/Preferences", .preferences) { $0.hasPrefix("\(id).") && $0 != "\(id).plist" }
            addMatches(in: "\(lib)/Group Containers", .containers) { matchesBundleScopedName($0, bundleID: id) }
            addMatches(in: "\(lib)/LaunchAgents", .other) { matchesBundleScopedName($0, bundleID: id) }
            // System locations (may need admin to trash; failures are reported).
            add("/Library/Application Support/\(id)", .support)
            add("/Library/Caches/\(id)", .caches)
            add("/Library/Preferences/\(id).plist", .preferences)
            addMatches(in: "/Library/LaunchAgents", .other) { matchesBundleScopedName($0, bundleID: id) }
            addMatches(in: "/Library/LaunchDaemons", .other) { matchesBundleScopedName($0, bundleID: id) }
        }

        // Name-based folders, exact match only: fuzzy matching is risky.
        if !name.isEmpty {
            add("\(lib)/Application Support/\(name)", .support)
            add("\(lib)/Logs/\(name)", .logs)
            add("\(lib)/Caches/\(name)", .caches)
        }

        // Last line of defense: nothing outside the scanned roots (or the app
        // bundle itself) may ever reach the removal list.
        let appPath = appURL.standardizedFileURL.path
        let allowedRoots = ["\(lib)/", "/Library/"]
        let safe = dedupe(paths).filter { url, _ in
            let path = url.standardizedFileURL.path
            return path == appPath || allowedRoots.contains { path.hasPrefix($0) && path != $0 }
        }
        return safe
            .map { Leftover(url: $0.0, category: $0.1, size: directorySize(of: $0.0, fm: fm)) }
            .sorted { ($0.category.sortRank, -$0.size) < ($1.category.sortRank, -$1.size) }
    }

    private static func matchesBundleScopedName(_ name: String, bundleID: String) -> Bool {
        if name == bundleID { return true }
        if name.hasPrefix("\(bundleID).") { return true }
        if name.hasSuffix(".\(bundleID)") { return true }
        if name.contains(".\(bundleID).") { return true }
        let groupName = "group.\(bundleID)"
        return name == groupName || name.hasPrefix("\(groupName).")
    }

    /// Drops exact duplicates and any path nested inside another already found.
    private static func dedupe(_ paths: [(URL, Category)]) -> [(URL, Category)] {
        var seen = Set<String>()
        var roots: [String] = []
        var out: [(URL, Category)] = []
        for (url, category) in paths.sorted(by: { $0.0.path.count < $1.0.path.count }) {
            let path = url.standardizedFileURL.path
            if seen.contains(path) { continue }
            if roots.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            seen.insert(path)
            roots.append(path)
            out.append((url, category))
        }
        return out
    }

    private static func directorySize(of url: URL, fm: FileManager) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url,
                                          includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                                          options: [], errorHandler: nil) {
            for case let item as URL in enumerator {
                total += fileSize(item)
            }
        }
        return total
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
}
