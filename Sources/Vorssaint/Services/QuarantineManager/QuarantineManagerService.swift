// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Finds files carrying the `com.apple.quarantine` extended attribute - the
/// flag that triggers the "downloaded from the internet, are you sure?"
/// Gatekeeper prompt - and clears it from the ones the user picks. Targets
/// come from the current Finder selection, or a file picker when nothing is
/// selected there.
final class QuarantineManagerService: ObservableObject {
    static let shared = QuarantineManagerService()

    enum Phase: Equatable {
        case empty
        case scanning
        case results
        case removing
        case done(cleared: Int, failed: Int)
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let path: String
        let name: String
        let relativePath: String
        let quarantineValue: String
        /// True for a collapsed `.app` bundle entry - removal for these runs
        /// recursively (`-dr`) instead of on the single path (`-d`).
        let isApp: Bool

        static func == (lhs: Entry, rhs: Entry) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var phase: Phase = .empty
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var totalFound: Int = 0
    @Published var selection = Set<Entry.ID>()

    /// The paths behind the current result set, so the refresh button can
    /// re-run the same scan without the user having to pick or drop again.
    private var lastScanPaths: [URL] = []

    private init() {}

    // MARK: - Selection & scan

    /// One-click convenience for the app's most common target: everything
    /// installed in `/Applications`.
    func scanApplications() {
        scan(paths: [URL(fileURLWithPath: "/Applications")])
    }

    /// Opens a file/app picker directly, with no Finder-selection detection -
    /// the explicit "browse" half of the empty state's two options.
    func browseForTargets() {
        presentPicker()
    }

    private func presentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        scan(paths: panel.urls)
    }

    func scan(paths: [URL]) {
        guard !paths.isEmpty else { return }
        lastScanPaths = paths
        entries = []
        totalFound = 0
        selection = []
        phase = .scanning

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found: [Entry] = []
            var total = 0
            for url in paths {
                let scanned = Self.scanTarget(url)
                found.append(contentsOf: scanned.entries)
                total += scanned.totalFound
            }
            if found.count > QuarantineManagerSupport.maxScanEntries {
                found = Array(found.prefix(QuarantineManagerSupport.maxScanEntries))
            }
            DispatchQueue.main.async {
                guard let self, self.phase == .scanning else { return }
                self.entries = found
                self.totalFound = total
                self.phase = found.isEmpty ? .empty : .results
            }
        }
    }

    func selectAll() { selection = Set(entries.map(\.id)) }
    func selectNone() { selection = [] }

    func toggle(_ id: Entry.ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func reset() {
        lastScanPaths = []
        entries = []
        totalFound = 0
        selection = []
        phase = .empty
    }

    /// Re-runs the current scan over the same paths - the results-list
    /// refresh button.
    func refreshScan() {
        guard !lastScanPaths.isEmpty else { return }
        scan(paths: lastScanPaths)
    }

    /// Removes one entry from the current result list without disturbing the
    /// rest - used after clearing an attribute from the detail sheet, where a
    /// full re-scan would wipe out every other already-scanned result.
    func removeEntryFromList(_ id: Entry.ID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        selection.remove(id)
        totalFound = max(0, totalFound - 1)
        if entries.isEmpty { phase = .empty }
    }

    // MARK: - Removal

    func removeQuarantineFromSelected() {
        let targets = entries.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }
        phase = .removing
        let paths = targets.map { (path: $0.path, recursive: $0.isApp) }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.removeQuarantine(from: paths)
            DispatchQueue.main.async {
                guard let self, self.phase == .removing else { return }
                let removedIDs = Set(targets.map(\.id))
                self.entries.removeAll { removedIDs.contains($0.id) }
                self.totalFound = max(0, self.totalFound - removedIDs.count)
                self.selection = []
                self.phase = .done(cleared: result.cleared, failed: result.failed)
            }
        }
    }

    /// Leaves the done screen for the refreshed list - or the start screen
    /// only if nothing scanned is left. Never a full reset like the header's
    /// close button; this is a continuation, not an abandon.
    func continueAfterDone() {
        guard case .done = phase else { return }
        phase = entries.isEmpty ? .empty : .results
    }

    /// Tries every path in one call first (split by recursive vs. single, since
    /// `-dr` and `-d` cannot mix in one invocation), then falls back to a
    /// per-path retry so one already-clean file (already cleared, removed
    /// between scan and action) doesn't force the whole selection to escalate.
    /// Paths that fail for a real reason (e.g. permissions), from either
    /// group, are cleared together behind exactly one admin prompt - a mixed
    /// selection of an app and a loose file never chains two password dialogs.
    static func removeQuarantine(from targets: [(path: String, recursive: Bool)]) -> (cleared: Int, failed: Int) {
        let plain = targets.filter { !$0.recursive }.map(\.path)
        let recursive = targets.filter(\.recursive).map(\.path)

        var cleared = 0
        var needsAdmin: [(path: String, recursive: Bool)] = []

        if !plain.isEmpty {
            let (batchCleared, batchNeedsAdmin) = removeBatch(plain, recursive: false, timeout: 30)
            cleared += batchCleared
            needsAdmin += batchNeedsAdmin.map { (path: $0, recursive: false) }
        }
        if !recursive.isEmpty {
            let (batchCleared, batchNeedsAdmin) = removeBatch(recursive, recursive: true, timeout: 120)
            cleared += batchCleared
            needsAdmin += batchNeedsAdmin.map { (path: $0, recursive: true) }
        }

        guard !needsAdmin.isEmpty else { return (cleared, 0) }

        var commands: [String] = []
        let plainAdmin = needsAdmin.filter { !$0.recursive }.map(\.path)
        let recursiveAdmin = needsAdmin.filter(\.recursive).map(\.path)
        if !plainAdmin.isEmpty {
            commands.append("/usr/bin/xattr -d com.apple.quarantine " + plainAdmin.map(shellQuote).joined(separator: " "))
        }
        if !recursiveAdmin.isEmpty {
            commands.append("/usr/bin/xattr -dr com.apple.quarantine " + recursiveAdmin.map(shellQuote).joined(separator: " "))
        }
        let ok = AdminShell.runSync(commands.joined(separator: " && "),
                                    prompt: L10n.shared.s.adminPromptQuarantine)
        return ok ? (cleared + needsAdmin.count, 0) : (cleared, needsAdmin.count)
    }

    /// One batch `xattr -d[r]` call over `paths`; on failure, retries each
    /// path on its own. Returns the cleared count and the paths still
    /// blocked for a real reason (permissions), ready to be escalated.
    private static func removeBatch(_ paths: [String], recursive: Bool, timeout: TimeInterval)
        -> (cleared: Int, needsAdmin: [String]) {
        let flag = recursive ? "-dr" : "-d"
        let batch = Shell.run("/usr/bin/xattr", [flag, "com.apple.quarantine"] + paths, timeout: timeout)
        if batch.status == 0 {
            return (paths.count, [])
        }

        var cleared = 0
        var needsAdmin: [String] = []
        for path in paths {
            let result = Shell.run("/usr/bin/xattr", [flag, "com.apple.quarantine", path], timeout: timeout)
            if result.status == 0
                || result.output.range(of: "No such xattr", options: .caseInsensitive) != nil
                || result.output.range(of: "No such file", options: .caseInsensitive) != nil {
                cleared += 1
            } else {
                needsAdmin.append(path)
            }
        }
        return (cleared, needsAdmin)
    }

    private static func shellQuote(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - All attributes

    /// Every extended attribute on `path`, not just quarantine - the detail
    /// sheet's "All Attributes" section. A binary plist value is decoded and
    /// pretty-printed through `plutil`; other binary values fall back to a
    /// hex dump, matching the Raycast extension this was ported from.
    static func readAllAttributes(at path: String) -> [QuarantineManagerSupport.XattrInfo] {
        let list = Shell.run("/usr/bin/xattr", [path])
        guard list.status == 0 else { return [] }
        let names = list.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        return names.map { name in
            let raw = Shell.run("/usr/bin/xattr", ["-p", name, path]).output
            let value: String
            var isBinaryDisplay = false
            if raw.hasPrefix("bplist") {
                if let pretty = prettyPlistValue(name: name, path: path) {
                    value = pretty
                } else {
                    value = hexValue(name: name, path: path)
                    isBinaryDisplay = true
                }
            } else if QuarantineManagerSupport.looksBinary(raw) {
                value = hexValue(name: name, path: path)
                isBinaryDisplay = true
            } else {
                value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return QuarantineManagerSupport.XattrInfo(name: name, value: value,
                                                       isQuarantine: name == "com.apple.quarantine",
                                                       isBinaryDisplay: isBinaryDisplay)
        }
    }

    private static func hexValue(name: String, path: String) -> String {
        Shell.run("/usr/bin/xattr", ["-px", name, path]).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prettyPlistValue(name: String, path: String) -> String? {
        guard let data = QuarantineManagerSupport.data(fromHex: hexValue(name: name, path: path)) else {
            return nil
        }
        let result = Shell.run("/usr/bin/plutil", ["-p", "-"], timeout: 10, input: data)
        guard result.status == 0 else { return nil }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clears every extended attribute on `path`, not just quarantine
    /// (`xattr -c`). Same plain-call-then-admin-escalated shape as
    /// `removeQuarantine(from:)`, for exactly one path.
    static func removeAllAttributes(at path: String, recursive: Bool) -> Bool {
        let flag = recursive ? "-cr" : "-c"
        let result = Shell.run("/usr/bin/xattr", [flag, path], timeout: recursive ? 120 : 10)
        if result.status == 0 {
            return true
        }
        return AdminShell.runSync("/usr/bin/xattr \(flag) \(shellQuote(path))",
                                  prompt: L10n.shared.s.adminPromptQuarantine)
    }

    /// Clears one named attribute from `path` (the trash icon next to a row
    /// in "All Attributes"). Same plain-call-then-admin-escalated shape as
    /// `removeBatch`, including its tolerance for a recursive delete that
    /// exits nonzero merely because some internal files never had the
    /// attribute to begin with - e.g. `com.apple.provenance`, which usually
    /// lives only on the bundle itself, not every file inside it.
    ///
    /// Some attributes are kernel-managed and SIP-protected: `xattr -d`
    /// reports success (status 0, no error text) without actually clearing
    /// anything - `com.apple.provenance` is the known case, but others may
    /// exist on other macOS versions. A follow-up read on `path` catches
    /// this regardless of name, so the caller can tell a real removal from a
    /// silently-ignored one and lock that attribute going forward.
    static func removeAttribute(named name: String, at path: String, recursive: Bool) -> Bool {
        guard QuarantineManagerSupport.isRemovable(name) else { return false }
        let flag = recursive ? "-dr" : "-d"
        let result = Shell.run("/usr/bin/xattr", [flag, name, path], timeout: recursive ? 120 : 10)
        let attempted = result.status == 0
            || result.output.range(of: "No such xattr", options: .caseInsensitive) != nil
            || result.output.range(of: "No such file", options: .caseInsensitive) != nil
        if !attempted {
            guard AdminShell.runSync("/usr/bin/xattr \(flag) \(shellQuote(name)) \(shellQuote(path))",
                                     prompt: L10n.shared.s.adminPromptQuarantine) else {
                return false
            }
        }
        let stillPresent = Shell.run("/usr/bin/xattr", ["-p", name, path]).status == 0
        return !stillPresent
    }

    // MARK: - Scanning

    /// `.app` bundles and plain folders scan recursively vs. one level deep,
    /// same distinction the extension this was ported from makes: an app
    /// bundle is self-contained and often carries the flag on every internal
    /// file, while a plain folder (like Downloads) stays fast by only
    /// looking at its immediate children.
    private static func scanTarget(_ url: URL) -> (entries: [Entry], totalFound: Int) {
        let path = url.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return ([], 0)
        }

        guard isDirectory.boolValue else {
            let result = Shell.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", path])
            let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, !value.isEmpty else { return ([], 0) }
            let entry = Entry(path: path, name: url.lastPathComponent,
                              relativePath: url.lastPathComponent, quarantineValue: value, isApp: false)
            return ([entry], 1)
        }

        if QuarantineManagerSupport.isApp(path) {
            // An app bundle is presented as one item, not a flood of its
            // internal files - the recursive scan only decides whether
            // anything under it is quarantined and supplies a representative
            // value; removal (`removeQuarantine`) still clears the whole tree.
            // The returned count is 1 (this one row), not the internal file
            // count - that count only feeds the "truncated" indicator, which
            // must not fire just because a bundle has many internal files.
            let result = Shell.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", "-r", path], timeout: 120)
            let scanned = collectEntries(from: result.output, root: path)
            guard scanned.totalFound > 0 else { return ([], 0) }
            var name = FileManager.default.displayName(atPath: path)
            if name.hasSuffix(".app") { name.removeLast(4) }
            let ownResult = Shell.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", path])
            let ownValue = ownResult.status == 0
                ? ownResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let value = ownValue.isEmpty ? (scanned.entries.first?.quarantineValue ?? "") : ownValue
            let entry = Entry(path: path, name: name, relativePath: prettyParent(path),
                              quarantineValue: value, isApp: true)
            return ([entry], 1)
        }

        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        var entries: [Entry] = []
        var totalFound = 0
        let chunkSize = 256
        var start = 0
        while start < children.count {
            let batch = children[start..<min(start + chunkSize, children.count)]
            // The directory itself is appended as a sentinel so every call
            // has at least two paths - with a single path, xattr prints the
            // bare value with no "<path>: " prefix, and the extra argument
            // forces the prefixed format so a lone quarantined child is
            // never misread as the directory's own value.
            let args = ["-p", "com.apple.quarantine"] + batch.map(\.path) + [path]
            let result = Shell.run("/usr/bin/xattr", args, timeout: 30)
            let batchResult = collectEntries(from: result.output, root: path)
            entries.append(contentsOf: batchResult.entries.map(Self.normalizeIfApp))
            totalFound += batchResult.totalFound
            start += chunkSize
        }
        return (entries, totalFound)
    }

    /// A direct child of a shallow folder scan that happens to be an `.app`
    /// still needs recursive removal (its own top-level flag alone does not
    /// clear internal files), so it gets the same `isApp` treatment - and the
    /// same cleaned-up display name - as a bundle picked directly.
    private static func normalizeIfApp(_ entry: Entry) -> Entry {
        guard QuarantineManagerSupport.isApp(entry.path) else { return entry }
        var name = entry.name
        if name.hasSuffix(".app") { name.removeLast(4) }
        return Entry(path: entry.path, name: name, relativePath: prettyParent(entry.path),
                    quarantineValue: entry.quarantineValue, isApp: true)
    }

    private static func collectEntries(from output: String, root: String) -> (entries: [Entry], totalFound: Int) {
        var entries: [Entry] = []
        var found = 0
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let parsed = QuarantineManagerSupport.parseQuarantineLine(String(line)) else { continue }
            found += 1
            guard entries.count < QuarantineManagerSupport.maxScanEntries else { continue }
            let name = (parsed.path as NSString).lastPathComponent
            let relative = parsed.path.hasPrefix(root + "/")
                ? String(parsed.path.dropFirst(root.count + 1))
                : name
            entries.append(Entry(path: parsed.path, name: name, relativePath: relative,
                                 quarantineValue: parsed.value.trimmingCharacters(in: .whitespaces),
                                 isApp: false))
        }
        return (entries, found)
    }

    private static func prettyParent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
