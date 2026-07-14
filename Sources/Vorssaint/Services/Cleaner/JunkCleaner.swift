// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Finds junk the Mac accumulates — leftovers of uninstalled apps, orphaned
/// startup items, caches, logs, developer build junk, the Trash — lets the
/// user review every single path with its size, and moves what they confirm
/// to the Trash. Nothing is deleted in place, nothing is touched while the
/// scan runs, and nothing runs at all until the user opens the tool.
///
/// The safety model, in order of importance:
/// 1. Review first. Every item shows its full path and size before anything
///    happens, and uncertain finds start unchecked.
/// 2. Trash, not delete. Every removal is a reversible move to the Trash
///    (the Trash category itself is the one explicit exception).
/// 3. Never guess against a living app. A leftover needs a bundle shaped
///    name whose owner is not installed, not running, not Apple, and not
///    related to any installed identifier (dot boundary family match).
/// 4. Scoped roots only. Items come from fixed, well known junk locations,
///    one directory level deep; nothing outside them can ever be listed.
final class JunkCleaner: ObservableObject {
    static let shared = JunkCleaner()

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaning
        case done(freed: Int64, failed: Int)
    }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let category: CleanerSupport.Category
        let size: Int64
        /// A short secondary line: the owning bundle identifier or label.
        let detail: String
        /// Whether this find is safe enough to clean without a second look.
        /// Recommended items start selected and live in the safe section of
        /// the interface; the rest wait unchecked under optional.
        let recommended: Bool
        var include: Bool

        var name: String { url.lastPathComponent }

        init(url: URL, category: CleanerSupport.Category, size: Int64,
             detail: String, recommended: Bool) {
            self.url = url
            self.category = category
            self.size = size
            self.detail = detail
            self.recommended = recommended
            self.include = recommended
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.include == rhs.include
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published var items: [Item] = []
    /// The category currently being scanned, for the progress line.
    @Published private(set) var scanningCategory: CleanerSupport.Category?

    private init() {}

    /// Serializes scans so a re-scan started while one runs is ignored.
    private var scanToken = UUID()

    var selectedSize: Int64 { items.filter(\.include).reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.include).count }

    func items(in category: CleanerSupport.Category) -> [Item] {
        items.filter { $0.category == category }
    }

    func setInclude(_ include: Bool, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].include = include
    }

    func setInclude(_ include: Bool, forCategory category: CleanerSupport.Category) {
        for index in items.indices where items[index].category == category {
            items[index].include = include
        }
    }

    func reset() {
        scanToken = UUID()
        items = []
        scanningCategory = nil
        phase = .idle
    }

    // MARK: - Scan

    func scan() {
        guard phase != .scanning else { return }
        let token = UUID()
        scanToken = token
        items = []
        phase = .scanning

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let installed = Self.installedBundleIDs()
            // A path claimed by the leftover scan must not reappear under
            // caches or logs: one path, one row, one decision.
            var claimed = Set<String>()
            let categories: [(CleanerSupport.Category, () -> [Item])] = [
                (.leftovers, {
                    let found = Self.scanLeftovers(installed: installed)
                    claimed.formUnion(found.map { $0.url.standardizedFileURL.path })
                    return found
                }),
                (.loginItems, { Self.scanOrphanedLaunchPlists(installed: installed) }),
                (.caches, { Self.scanCaches(excluding: claimed) }),
                (.logs, { Self.scanLogs(excluding: claimed) }),
                (.developer, { Self.scanDeveloperJunk() }),
                (.trash, { Self.scanTrash() }),
                (.deviceBackups, { Self.scanDeviceBackups() }),
            ]
            for (category, run) in categories {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.scanToken == token else { return }
                    self.scanningCategory = category
                }
                let found = run()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.scanToken == token else { return }
                    self.items.append(contentsOf: found)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scanToken == token else { return }
                self.scanningCategory = nil
                self.phase = .results
            }
        }
    }

    // MARK: - Clean

    func cleanSelected() {
        let chosen = items.filter(\.include)
        guard !chosen.isEmpty else { return }
        phase = .cleaning

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            var freed: Int64 = 0
            var failed = 0
            var stubborn: [Item] = []

            // Emptying the Trash MUST come first: the row means the Trash as
            // it was scanned. Running it after the moves would silently wipe
            // the very items this clean just made recoverable, which reads
            // as "nothing ever went to the Trash".
            for item in chosen where item.category == .trash {
                if Self.emptyTrash() { freed += item.size } else { failed += 1 }
            }

            for item in chosen where item.category != .trash {
                guard Self.mayRemove(item.url) else {
                    failed += 1
                    continue
                }
                if item.category == .loginItems {
                    // Retire the job first so nothing keeps running from a
                    // plist that is about to leave; then the regular move.
                    Self.bootoutUserAgent(item.url)
                }
                do {
                    try fm.trashItem(at: item.url, resultingItemURL: nil)
                    freed += item.size
                } catch {
                    stubborn.append(item)
                }
            }

            // Root owned files (system LaunchDaemons and friends) go through
            // Finder, which shows the standard administrator prompt and moves
            // them to the Trash exactly like a drag would. One batch, one
            // prompt; a cancel leaves them in place and they count as failed.
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

            DispatchQueue.main.async { [weak self] in
                guard let self, self.phase == .cleaning else { return }
                self.items = []
                self.phase = .done(freed: freed, failed: failed)
            }
        }
    }

    /// Exact match guard against ever removing a critical root, even if a
    /// scanner bug produced one. Items are already scoped by construction;
    /// this is the last line of defense.
    private static func mayRemove(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()
        let critical: Set<String> = [
            "/", "/Applications", "/Library", "/System", "/Users", "/usr",
            "/bin", "/sbin", "/etc", "/var", "/private", "/opt",
            home, home + "/Library", home + "/Documents", home + "/Desktop",
            home + "/Downloads", home + "/Pictures", home + "/Music", home + "/Movies",
        ]
        guard !critical.contains(path) else { return false }
        // Depth guard: anything this shallow is a root of some kind, never junk.
        return url.pathComponents.count >= 4
    }

    private static func trashViaFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else { return }
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

    /// Emptying the Trash is the one permanent action here, clearly labeled
    /// in the interface. Finder owns it, exactly like the menu command.
    private static func emptyTrash() -> Bool {
        guard AppleScriptRunner.consentToAutomate(bundleID: "com.apple.finder") else { return false }
        return AppleScriptRunner.run("tell application \"Finder\" to empty trash").ok
    }

    /// Unloads a user launch agent before its plist is trashed, so the job
    /// does not keep running until logout. Best effort: a plist that was
    /// never loaded simply makes launchctl exit nonzero, which is fine.
    private static func bootoutUserAgent(_ plistURL: URL) {
        guard plistURL.path.hasPrefix(NSHomeDirectory() + "/Library/LaunchAgents/") else { return }
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let label = plist["Label"] as? String, !label.isEmpty,
              !label.contains("/"), !label.contains("..") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        // A plist that was never loaded makes launchctl complain; that is
        // expected and not worth a line in anyone's console.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Installed apps oracle

    /// Every bundle identifier that must be treated as alive: apps found in
    /// the application folders (three levels deep, covering subfolders and
    /// suites), everything currently running, and login item helpers nested
    /// inside those apps.
    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications",
                     NSHomeDirectory() + "/Applications"]

        func collect(at url: URL, depth: Int) {
            guard depth > 0 else { return }
            guard let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles]) else { return }
            for entry in entries {
                if entry.pathExtension == "app" {
                    if let id = Bundle(url: entry)?.bundleIdentifier {
                        ids.insert(id.lowercased())
                    }
                    // Login item helpers live inside the app and own launch
                    // plists under their own identifiers.
                    collect(at: entry.appendingPathComponent("Contents/Library/LoginItems"), depth: 1)
                } else {
                    collect(at: entry, depth: depth - 1)
                }
            }
        }

        for root in roots {
            collect(at: URL(fileURLWithPath: root), depth: 3)
        }
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { ids.insert(id.lowercased()) }
        }
        return ids
    }

    /// The final say on whether a candidate identifier has a living owner:
    /// the collected set (family match), the vendor namespace rule (suites
    /// and updaters share a namespace with sibling identifiers), and Launch
    /// Services, which knows apps registered anywhere on disk.
    private static func hasLivingOwner(_ candidate: String, installed: Set<String>) -> Bool {
        if CleanerSupport.isOwned(candidate: candidate, byInstalled: installed) { return true }
        if CleanerSupport.sharesVendorNamespace(candidate: candidate, withInstalled: installed) { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate) != nil
    }

    // MARK: - Category scanners

    /// User domain locations where uninstalled apps leave data behind. One
    /// level deep; every entry must map to a bundle identifier to even be
    /// considered (plain vendor folders are never guessed at by name).
    /// Group Containers and Application Scripts are deliberately absent:
    /// their team prefixed, cross app names cannot be attributed safely.
    private static let leftoverRoots: [String] = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost",
        "Saved Application State", "HTTPStorages", "WebKit", "Logs",
        "Containers", "Cookies",
    ]

    private static func scanLeftovers(installed: Set<String>) -> [Item] {
        let fm = FileManager.default
        let lib = NSHomeDirectory() + "/Library"
        var found: [Item] = []
        for root in leftoverRoots {
            let dir = lib + "/" + root
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where !entry.hasPrefix(".") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                var candidate = CleanerSupport.bundleIDCandidate(fromEntryName: entry)
                if candidate == nil, root == "Containers" {
                    // Modern containers carry an opaque UUID name; the owner
                    // is recorded in the container metadata.
                    candidate = containerOwner(at: url)
                }
                guard let owner = candidate,
                      !CleanerSupport.isProtectedBundleID(owner),
                      !hasLivingOwner(owner, installed: installed) else { continue }
                found.append(Item(url: url, category: .leftovers,
                                  size: directorySize(of: url, fm: fm),
                                  detail: owner,
                                  recommended: CleanerPolicy.precheckLeftovers))
            }
        }
        return sorted(found)
    }

    /// The owning bundle identifier of a container folder, from the metadata
    /// the container manager writes inside it.
    private static func containerOwner(at url: URL) -> String? {
        let metadata = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
        guard let dict = NSDictionary(contentsOf: metadata),
              let owner = dict["MCMMetadataIdentifier"] as? String,
              CleanerSupport.looksLikeBundleID(owner) else { return nil }
        return owner
    }

    /// Launch agents and daemons whose every referenced executable is gone
    /// and whose label has no living owner: the classic ghost that keeps a
    /// deleted app listed under Login Items and Extensions.
    private static func scanOrphanedLaunchPlists(installed: Set<String>) -> [Item] {
        let fm = FileManager.default
        let roots = [NSHomeDirectory() + "/Library/LaunchAgents",
                     "/Library/LaunchAgents",
                     "/Library/LaunchDaemons"]
        var found: [Item] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".plist") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(entry)
                guard let plist = NSDictionary(contentsOfFile: url.path) as? [String: Any] else { continue }
                let label = plist["Label"] as? String
                let executables = CleanerSupport.executablePaths(inLaunchPlist: plist)
                guard CleanerSupport.launchPlistIsRemovableOrphan(
                    label: label,
                    executables: executables,
                    // A missing binary on an external volume is inconclusive
                    // (the volume may just be unmounted), so it counts as
                    // present and the plist is left alone.
                    executableExists: { $0.hasPrefix("/Volumes/") || fm.fileExists(atPath: $0) }) else { continue }
                // Second signal: the label itself must not belong to anything
                // installed either (a moved binary is not an uninstalled app).
                if let label, hasLivingOwner(label, installed: installed) { continue }
                found.append(Item(url: url, category: .loginItems,
                                  size: directorySize(of: url, fm: fm),
                                  detail: label ?? entry,
                                  recommended: CleanerPolicy.precheckLoginItems))
            }
        }
        return sorted(found)
    }

    private static func scanCaches(excluding claimed: Set<String>) -> [Item] {
        let fm = FileManager.default
        let dir = NSHomeDirectory() + "/Library/Caches"
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        var found: [Item] = []
        for entry in entries where !entry.hasPrefix(".") {
            guard !CleanerPolicy.isExcludedCacheEntry(entry) else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
            guard !claimed.contains(url.standardizedFileURL.path) else { continue }
            let size = directorySize(of: url, fm: fm)
            guard size > 0 else { continue }
            found.append(Item(url: url, category: .caches, size: size,
                              detail: entry,
                              recommended: CleanerPolicy.precheckCacheEntry(entry)))
        }
        return sorted(found)
    }

    private static func scanLogs(excluding claimed: Set<String>) -> [Item] {
        let fm = FileManager.default
        var found: [Item] = []
        let logsDir = NSHomeDirectory() + "/Library/Logs"
        if let entries = try? fm.contentsOfDirectory(atPath: logsDir) {
            for entry in entries where entry != "DiagnosticReports"
                && !entry.hasPrefix(".")
                && !CleanerPolicy.isExcludedCacheEntry(entry) {
                let url = URL(fileURLWithPath: logsDir).appendingPathComponent(entry)
                guard !claimed.contains(url.standardizedFileURL.path) else { continue }
                let size = directorySize(of: url, fm: fm)
                guard size > 0 else { continue }
                found.append(Item(url: url, category: .logs, size: size,
                                  detail: entry, recommended: CleanerPolicy.precheckLogs))
            }
        }
        let reports = logsDir + "/DiagnosticReports"
        let reportsURL = URL(fileURLWithPath: reports)
        let reportsSize = directorySize(of: reportsURL, fm: fm)
        if reportsSize > 0 {
            found.append(Item(url: reportsURL, category: .logs, size: reportsSize,
                              detail: "DiagnosticReports", recommended: CleanerPolicy.precheckLogs))
        }
        return sorted(found)
    }

    private static func scanDeveloperJunk() -> [Item] {
        let fm = FileManager.default
        var found: [Item] = []
        for path in CleanerPolicy.developerJunkPaths {
            let url = URL(fileURLWithPath: NSHomeDirectory() + path)
            guard fm.fileExists(atPath: url.path) else { continue }
            let size = directorySize(of: url, fm: fm)
            guard size > 0 else { continue }
            found.append(Item(url: url, category: .developer, size: size,
                              detail: url.lastPathComponent,
                              recommended: CleanerPolicy.precheckDeveloper))
        }
        return sorted(found)
    }

    /// Old iPhone and iPad backups under MobileSync: with caches, the other
    /// classic tenant of the storage macOS files under "Other". They are the
    /// user's safety net, so every find starts unchecked and names the
    /// device and the backup date. Without Full Disk Access the folder is
    /// unreadable and nothing is offered.
    private static func scanDeviceBackups() -> [Item] {
        let fm = FileManager.default
        let root = NSHomeDirectory() + "/Library/Application Support/MobileSync/Backup"
        guard let entries = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        var found: [Item] = []
        for entry in entries where !entry.hasPrefix(".") {
            let url = URL(fileURLWithPath: root).appendingPathComponent(entry)
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let size = directorySize(of: url, fm: fm)
            guard size > 0 else { continue }
            let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist"))
            let device = info?["Device Name"] as? String
            let date = (info?["Last Backup Date"] as? Date).map {
                DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none)
            }
            let detail = [device, date].compactMap { $0 }.joined(separator: ", ")
            found.append(Item(url: url, category: .deviceBackups, size: size,
                              detail: detail.isEmpty ? entry : detail,
                              recommended: CleanerPolicy.precheckDeviceBackups))
        }
        return sorted(found)
    }

    private static func scanTrash() -> [Item] {
        let fm = FileManager.default
        let trash = NSHomeDirectory() + "/.Trash"
        // Only what the user can see in the Trash counts: an "empty" Trash
        // still carries hidden bookkeeping files (.DS_Store), and offering
        // to empty those reads as a lie.
        guard let entries = try? fm.contentsOfDirectory(atPath: trash) else { return [] }
        let visible = entries.filter { !$0.hasPrefix(".") }
        guard !visible.isEmpty else { return [] }
        let url = URL(fileURLWithPath: trash)
        let size = visible.reduce(Int64(0)) {
            $0 + directorySize(of: url.appendingPathComponent($1), fm: fm)
        }
        guard size > 0 else { return [] }
        return [Item(url: url, category: .trash, size: size,
                     detail: "", recommended: false)]
    }

    // MARK: - Helpers

    private static func sorted(_ items: [Item]) -> [Item] {
        items.sorted { $0.size > $1.size }
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
