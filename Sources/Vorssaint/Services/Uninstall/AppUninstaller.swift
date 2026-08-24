// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin

/// Finds the files an app leaves around — caches, preferences, logs, support
/// folders, containers — and removes only what you pick. Ordinary files go to
/// the Trash; after an extra confirmation, a package-managed app is delegated
/// to its package manager before the remaining choices go to the Trash.
final class AppUninstaller: ObservableObject {
    static let shared = AppUninstaller()

    enum Phase: Equatable {
        case empty
        case scanning
        case results
        case removing
        case done(freed: Int64, failed: [Leftover])
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
        let ownerBundleID: String?
        var include: Bool = true

        var name: String { url.lastPathComponent }

        static func == (lhs: Leftover, rhs: Leftover) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var target: Target?
    @Published private(set) var homebrewPackage: HomebrewPackage?
    @Published var items: [Leftover] = []
    private var allowedRemovalPaths = Set<String>()
    private var homebrewRemovalSize: Int64 = 0
    private var homebrewRemovalObservation: AnyCancellable?

    private init() {}

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedHomebrewPackage: HomebrewPackage? {
        guard items.contains(where: { $0.category == .app && $0.include }) else { return nil }
        return homebrewPackage
    }
    var isRemovingWithHomebrew: Bool {
        guard let package = selectedHomebrewPackage,
              let status = HomebrewManager.shared.operationStatus else { return false }
        return status.action == .uninstall
            && status.package?.id == package.id
            && status.isActive
    }

    // MARK: - Selection & scan

    /// Reads an app bundle and starts scanning for its leftovers.
    func select(appURL: URL) {
        guard let bundle = Bundle(url: appURL) else { return }
        // System apps are SIP-protected and their support data is live OS
        // state; removing either would be wrong, so refuse the selection.
        guard !InstalledApps.isSystemApplication(at: appURL) else { return }
        // Only a verified bundle identifier becomes a path component. A
        // display name is presentation only and can never claim user data.
        guard let bundleID = UninstallerSupport.verifiedBundleID(bundle.bundleIdentifier) else { return }
        let selectedURL = appURL.standardizedFileURL
        guard selectedURL == selectedURL.resolvingSymlinksInPath() else { return }
        guard selectedURL != Bundle.main.bundleURL.standardizedFileURL else { return }
        guard !Self.isSymbolicLink(appURL) else { return }
        var name = FileManager.default.displayName(atPath: appURL.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        target = Target(name: name, bundleID: bundleID, url: selectedURL, icon: icon)
        homebrewPackage = nil
        homebrewRemovalSize = 0
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = nil
        items = []
        allowedRemovalPaths = []
        phase = .scanning

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ownedBundleIDs = Self.ownedBundleIDs(
                in: selectedURL, primary: bundleID, fm: .default)
            let exclusiveBundleIDs = Self.exclusiveOwnedBundleIDs(
                in: selectedURL, candidates: ownedBundleIDs)
            let found = Self.collect(appURL: selectedURL,
                                     exclusiveBundleIDs: exclusiveBundleIDs)
            DispatchQueue.main.async {
                HomebrewManager.shared.packageManagingApplication(at: selectedURL) { package in
                    // Drop the result if the user picked a different app (or reset)
                    // while this scan was running — never show A's files under B.
                    guard let self, self.phase == .scanning, self.target?.url == selectedURL else { return }
                    self.items = found
                    self.homebrewPackage = package
                    self.allowedRemovalPaths = Set(found.map { $0.url.standardizedFileURL.path })
                    self.phase = .results
                }
            }
        }
    }

    func setInclude(_ include: Bool, for id: UUID) {
        guard !isRemovingWithHomebrew else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    func reset() {
        guard !isRemovingWithHomebrew else { return }
        target = nil
        homebrewPackage = nil
        homebrewRemovalSize = 0
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = nil
        items = []
        allowedRemovalPaths = []
        phase = .empty
    }

    // MARK: - Removal

    func removeSelected() {
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty else { return }
        phase = .removing

        // Quit the app and any background app embedded inside it before the
        // bundle moves. Embedded helpers do not always share the main bundle ID.
        if let targetURL = target?.url {
            for app in NSWorkspace.shared.runningApplications where
                app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == targetURL
                || UninstallerSupport.isNestedBundle(app.bundleURL, in: targetURL) {
                app.terminate()
            }
        }

        let allowedPaths = allowedRemovalPaths
        let targetURL = target?.url
        let candidateBundleIDs = Set(chosen.compactMap(\.ownerBundleID))
        let alreadyFreed = homebrewRemovalSize

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let fm = FileManager.default
            var freed = alreadyFreed
            var stubborn: [Leftover] = []
            var failed: [Leftover] = []
            let exclusiveBundleIDs = targetURL.map {
                Self.exclusiveOwnedBundleIDs(in: $0, candidates: candidateBundleIDs)
            } ?? []
            for item in chosen {
                if item.category != .app {
                    guard let owner = item.ownerBundleID,
                          exclusiveBundleIDs.contains(owner) else {
                        failed.append(item)
                        continue
                    }
                }
                guard Self.removalIsStillSafe(item.url,
                                              allowedPaths: allowedPaths,
                                              targetURL: targetURL) else {
                    failed.append(item)
                    continue
                }
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
            if !stubborn.isEmpty {
                Self.trashViaFinder(stubborn.map(\.url))
                for item in stubborn {
                    if fm.fileExists(atPath: item.url.path) {
                        failed.append(item)
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

    /// After Homebrew has removed its package receipt and app artifact, clean
    /// only the other items the person selected. The app itself is excluded so
    /// this flow never tries to remove the same bundle twice.
    func removeSelectedWithHomebrew() {
        guard let package = selectedHomebrewPackage else { return }
        let manager = HomebrewManager.shared
        guard manager.operation == nil else { return }
        manager.clearLog()
        homebrewRemovalObservation?.cancel()
        homebrewRemovalObservation = manager.$operationStatus
            .compactMap { $0 }
            .filter { $0.action == .uninstall && $0.package?.id == package.id }
            .sink { [weak self] status in
                guard status.result != .running else { return }
                self?.homebrewRemovalObservation?.cancel()
                self?.homebrewRemovalObservation = nil
                if status.result == .succeeded {
                    self?.finishRemovalAfterHomebrew(package: package)
                }
            }
        manager.uninstall(package)
    }

    private func finishRemovalAfterHomebrew(package: HomebrewPackage) {
        guard phase == .results,
              homebrewPackage?.id == package.id,
              let app = items.first(where: { $0.category == .app && $0.include }),
              let targetURL = target?.url else { return }
        if FileManager.default.fileExists(atPath: targetURL.path) {
            homebrewPackage = nil
            removeSelected()
            return
        }
        homebrewRemovalSize = app.size
        setInclude(false, for: app.id)
        if items.contains(where: \.include) {
            removeSelected()
        } else {
            phase = .done(freed: homebrewRemovalSize, failed: [])
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

    private static func collect(appURL: URL,
                                exclusiveBundleIDs: Set<String>) -> [Leftover] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let lib = home + "/Library"
        var paths: [(URL, Category, String?)] = [(appURL, .app, nil)]

        func add(_ path: String, _ category: Category, owner: String) {
            let url = URL(fileURLWithPath: path)
            if fm.fileExists(atPath: url.path) { paths.append((url, category, owner)) }
        }
        func addMatches(in dir: String, _ category: Category, owner: String,
                        where matches: (String) -> Bool) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for entry in entries where matches(entry) {
                paths.append((URL(fileURLWithPath: dir).appendingPathComponent(entry), category,
                              owner))
            }
        }

        for id in exclusiveBundleIDs {
            add("\(lib)/Application Support/\(id)", .support, owner: id)
            add("\(lib)/Containers/\(id)", .containers, owner: id)
            add("\(lib)/Caches/\(id)", .caches, owner: id)
            add("\(lib)/Preferences/\(id).plist", .preferences, owner: id)
            add("\(lib)/Saved Application State/\(id).savedState", .state, owner: id)
            add("\(lib)/HTTPStorages/\(id)", .caches, owner: id)
            add("\(lib)/HTTPStorages/\(id).binarycookies", .caches, owner: id)
            add("\(lib)/WebKit/\(id)", .caches, owner: id)
            add("\(lib)/Application Scripts/\(id)", .containers, owner: id)
            add("\(lib)/Cookies/\(id).binarycookies", .caches, owner: id)
            add("\(lib)/Logs/\(id)", .logs, owner: id)
            // System locations (may need admin to trash; failures are reported).
            add("/Library/Application Support/\(id)", .support, owner: id)
            add("/Library/Caches/\(id)", .caches, owner: id)
            add("/Library/Preferences/\(id).plist", .preferences, owner: id)
            add("/Library/PrivilegedHelperTools/\(id)", .other, owner: id)

            addMatches(in: "\(lib)/Preferences/ByHost", .preferences, owner: id) {
                UninstallerSupport.matchesByHostPreference($0, bundleIDs: [id])
            }
            // Group containers are shared by design. A matching directory name
            // does not prove that another installed app from the same developer
            // is not using it, so they are never offered for automatic removal.
            for directory in ["\(lib)/LaunchAgents", "/Library/LaunchAgents",
                              "/Library/LaunchDaemons"] {
                addMatches(in: directory, .other, owner: id) {
                    UninstallerSupport.matchesLaunchItem($0, bundleIDs: [id])
                }
            }
        }

        let deepCandidates = UninstallerSupport.exactDeepCandidates(
            home: URL(fileURLWithPath: home, isDirectory: true),
            bundleIDs: exclusiveBundleIDs,
            darwinCache: darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR),
            darwinTemp: darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR)
        )
        for candidate in deepCandidates {
            guard let owner = exclusiveBundleIDs.first(where: {
                candidate.url.lastPathComponent == $0
            }) else { continue }
            add(candidate.url.path, candidate.kind == .support ? .support : .caches,
                owner: owner)
        }

        // Last line of defense: nothing outside the scanned roots (or the app
        // bundle itself) may ever reach the removal list.
        let appPath = appURL.standardizedFileURL.path
        let allowedRoots = scanRoots(home: home)
        let safe = dedupe(paths).filter { url, _, _ in
            let path = url.standardizedFileURL.path
            if path == appPath { return true }
            guard let root = allowedRoots.first(where: { path.hasPrefix($0.path + "/") }) else { return false }
            return !hasSymbolicLinkInParents(of: url, through: root)
        }
        return safe
            .map { Leftover(url: $0.0, category: $0.1,
                            size: directorySize(of: $0.0, fm: fm), ownerBundleID: $0.2) }
            .sorted { ($0.category.sortRank, -$0.size) < ($1.category.sortRank, -$1.size) }
    }

    private static func exclusiveOwnedBundleIDs(in selectedURL: URL,
                                                candidates: Set<String>) -> Set<String> {
        var applications: [(url: URL, bundleID: String)] = []
        let fm = FileManager.default
        guard UninstallerSupport.applicationIsInTrustedInstallRoot(
            selectedURL, home: fm.homeDirectoryForCurrentUser) else { return [] }
        var roots = [URL(fileURLWithPath: "/Applications", isDirectory: true)]
        roots.append(fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true))
        for root in roots where fm.fileExists(atPath: root.path) {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
            guard let enumerator = fm.enumerator(at: root,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles],
                                                errorHandler: nil) else { continue }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard values?.isDirectory == true, url.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()
                for candidateID in allBundleIDs(in: url, fm: fm) {
                    applications.append((url, candidateID))
                }
            }
        }
        for app in NSWorkspace.shared.runningApplications {
            if let url = app.bundleURL,
               let bundleID = UninstallerSupport.verifiedBundleID(app.bundleIdentifier) {
                applications.append((url, bundleID))
            }
        }
        for id in candidates {
            for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id) {
                applications.append((url, id))
            }
        }
        return UninstallerSupport.exclusiveBundleIDs(candidates,
                                                     selectedURL: selectedURL,
                                                     knownApplications: applications)
    }

    private static func removalIsStillSafe(_ url: URL,
                                           allowedPaths: Set<String>,
                                           targetURL: URL?) -> Bool {
        let path = url.standardizedFileURL.path
        guard allowedPaths.contains(path), let targetURL else { return false }
        if path == targetURL.standardizedFileURL.path { return !isSymbolicLink(url) }
        guard let root = scanRoots(home: NSHomeDirectory()).first(where: {
            path.hasPrefix($0.path + "/")
        }) else { return false }
        return !hasSymbolicLinkInParents(of: url, through: root)
    }

    private static func ownedBundleIDs(in appURL: URL,
                                       primary: String,
                                       fm: FileManager) -> Set<String> {
        var result: Set<String> = [primary]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ["app", "appex", "xpc", "plugin", "bundle"].contains(url.pathExtension.lowercased()),
                  let id = UninstallerSupport.verifiedBundleID(Bundle(url: url)?.bundleIdentifier),
                  id.hasPrefix(primary + ".") else { continue }
            result.insert(id)
        }
        return result
    }

    private static func allBundleIDs(in appURL: URL, fm: FileManager) -> Set<String> {
        var result = Set<String>()
        if let primary = UninstallerSupport.verifiedBundleID(Bundle(url: appURL)?.bundleIdentifier) {
            result.insert(primary)
        }
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: appURL,
                                             includingPropertiesForKeys: Array(keys),
                                             options: [.skipsHiddenFiles],
                                             errorHandler: nil) else { return result }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values?.isDirectory == true,
                  ["app", "appex", "xpc", "plugin", "bundle"].contains(
                    url.pathExtension.lowercased()),
                  let id = UninstallerSupport.verifiedBundleID(Bundle(url: url)?.bundleIdentifier)
            else { continue }
            result.insert(id)
        }
        return result
    }

    private static func scanRoots(home: String) -> [URL] {
        var roots = [
            URL(fileURLWithPath: home + "/Library", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: home + "/.config", isDirectory: true),
            URL(fileURLWithPath: home + "/.cache", isDirectory: true),
            URL(fileURLWithPath: home + "/.local/share", isDirectory: true),
        ]
        if let cache = darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR) { roots.append(cache) }
        if let temp = darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR) { roots.append(temp) }
        return roots.map(\.standardizedFileURL)
    }

    private static func darwinUserDirectory(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true).standardizedFileURL
    }

    private static func hasSymbolicLinkInParents(of url: URL, through root: URL) -> Bool {
        var current = url.deletingLastPathComponent().standardizedFileURL
        let root = root.standardizedFileURL
        while current.path.count >= root.path.count {
            if isSymbolicLink(current) { return true }
            if current.path == root.path { return false }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return true }
            current = parent
        }
        return true
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    /// Drops exact duplicates and any path nested inside another already found.
    private static func dedupe(_ paths: [(URL, Category, String?)])
        -> [(URL, Category, String?)] {
        var seen = Set<String>()
        var roots: [String] = []
        var out: [(URL, Category, String?)] = []
        for (url, category, owner) in paths.sorted(by: { $0.0.path.count < $1.0.path.count }) {
            let path = url.standardizedFileURL.path
            if seen.contains(path) { continue }
            if roots.contains(where: { path.hasPrefix($0 + "/") }) { continue }
            seen.insert(path)
            roots.append(path)
            out.append((url, category, owner))
        }
        return out
    }

    private static func directorySize(of url: URL, fm: FileManager) -> Int64 {
        if isSymbolicLink(url) { return fileSize(url) }
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: url,
                                          includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
                                          options: [], errorHandler: nil) {
            for case let item as URL in enumerator {
                if isSymbolicLink(item) { continue }
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
