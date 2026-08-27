// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Everything the app update check decides, with no file system, no network
/// and no processes: version comparison, which findings are real, how the
/// the sources are merged and when the next background check is due. Kept
/// pure so `./build.sh --test` can pin the rules that matter.
enum AppUpdatesSupport {

    // MARK: - Model

    /// Where a pending update comes from, which is also what the app can do
    /// about it: the package manager can install it right here, the store
    /// can only be opened, and an online finding opens the installed app.
    enum Source: String, Hashable {
        case packageManager
        case appStore
        case onlineCatalog

        fileprivate var sortOrder: Int {
            switch self {
            case .packageManager: return 0
            case .appStore: return 1
            case .onlineCatalog: return 2
            }
        }
    }

    struct Item: Identifiable, Hashable {
        let id: String
        let source: Source
        /// Name as the person knows it, from the app bundle when there is one.
        let name: String
        let installedVersion: String
        let latestVersion: String
        /// Package token, present only for package-manager rows.
        let token: String?
        /// Path of the app bundle this row stands for, when one was matched.
        let bundlePath: String?
        /// Store page for this app, present only for store rows.
        let storePage: String?

        var canInstallInPlace: Bool { source == .packageManager && token != nil }
        var isSelectable: Bool { source != .onlineCatalog }
        var versionSummary: String { "\(installedVersion) → \(latestVersion)" }
    }

    /// An installed app as the scanner sees it.
    struct InstalledApp: Hashable {
        let name: String
        let bundleID: String
        let path: String
        let version: String
        let isFromAppStore: Bool
    }

    /// One app's current version in the store.
    struct StoreEntry: Hashable {
        let bundleID: String
        let version: String
        let minimumOSVersion: String?
        let page: String?
    }

    /// The small, stable subset of one public catalog entry needed to match
    /// an installed bundle without treating that catalog as installation
    /// ownership.
    struct CatalogEntry: Hashable {
        let token: String
        let version: String
        let appNames: [String]
        let bundleIDs: [String]
        let minimumOSVersions: [String]
        let exactOSVersions: [String]
        let hasUnsupportedOSConstraint: Bool
    }

    // MARK: - Version comparison

    /// Package versions carry a revision after a comma ("3.5.262,260717d");
    /// only the part in front of it lines up with what an app bundle reports.
    static func versionCore(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comma = trimmed.firstIndex(of: ",") else { return trimmed }
        return String(trimmed[trimmed.startIndex..<comma])
    }

    /// Versions that carry no version at all. A package pinned to "latest"
    /// has no number to compare, so it can never be reported honestly as an
    /// update and is left out instead of nagging forever.
    static func isUncomparable(_ version: String) -> Bool {
        let value = versionCore(version).lowercased()
        return value.isEmpty || value == "latest"
    }

    /// Numeric-aware comparison: each dot-separated part is compared as a
    /// number when both sides are digits, so 130 beats 129 and leading zeros
    /// do not lie. A shorter version only loses when the extra parts are not
    /// all zero, so "1.2" and "1.2.0" are the same release.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(of: lhs)
        let right = parts(of: rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : ""
            let b = index < right.count ? right[index] : ""
            let result = comparePart(a, b)
            if result != .orderedSame { return result }
        }
        return .orderedSame
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        compare(versionCore(candidate), versionCore(installed)) == .orderedDescending
    }

    private static func parts(of version: String) -> [String] {
        version
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0) }
    }

    private static func comparePart(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let leftDigits = lhs.allSatisfy(\.isNumber) && !lhs.isEmpty
        let rightDigits = rhs.allSatisfy(\.isNumber) && !rhs.isEmpty
        if leftDigits && rightDigits {
            return compareDigits(lhs, rhs)
        }
        // A missing part counts as zero, so "1.2" equals "1.2.0" but loses
        // to "1.2.1"; a missing part against a word loses (1.2 < 1.2beta is
        // never claimed, the word side simply wins the tie-break).
        if lhs.isEmpty { return rightDigits && stripLeadingZeros(rhs).isEmpty ? .orderedSame : .orderedAscending }
        if rhs.isEmpty { return leftDigits && stripLeadingZeros(lhs).isEmpty ? .orderedSame : .orderedDescending }
        if lhs == rhs { return .orderedSame }
        // "9a" against "10" must never fall to plain text, where "9…" would
        // outrank "10": the number in front decides first. With the numbers
        // tied, the bare part is the release and the suffixed one is what
        // came before it, so "5" beats "5beta".
        let leftNumber = String(lhs.prefix(while: \.isNumber))
        let rightNumber = String(rhs.prefix(while: \.isNumber))
        if leftNumber.isEmpty != rightNumber.isEmpty {
            return leftNumber.isEmpty ? .orderedAscending : .orderedDescending
        }
        if !leftNumber.isEmpty {
            let numbers = compareDigits(leftNumber, rightNumber)
            if numbers != .orderedSame { return numbers }
            let leftBare = leftNumber.count == lhs.count
            let rightBare = rightNumber.count == rhs.count
            if leftBare != rightBare {
                return leftBare ? .orderedDescending : .orderedAscending
            }
        }
        return lhs.lowercased() < rhs.lowercased() ? .orderedAscending : .orderedDescending
    }

    /// Compared as text after dropping leading zeros, so versions with more
    /// digits than an integer can hold still sort correctly.
    private static func compareDigits(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = stripLeadingZeros(lhs)
        let b = stripLeadingZeros(rhs)
        if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
        if a == b { return .orderedSame }
        return a < b ? .orderedAscending : .orderedDescending
    }

    private static func stripLeadingZeros(_ value: String) -> String {
        let trimmed = value.drop(while: { $0 == "0" })
        return String(trimmed)
    }

    // MARK: - Package manager source

    /// Turns what the package manager reports into rows a person can act on.
    ///
    /// Package receipts can outlive an app that was removed by hand, and
    /// plenty of apps update themselves without refreshing that receipt.
    /// A row therefore only survives when its app bundle is still on disk,
    /// and the version from that bundle is the truth.
    static func packageUpdates(outdated: [HomebrewPackageUpdate],
                               installed: [HomebrewCaskRecord],
                               ignoredTokens: Set<String> = [],
                               apps: [InstalledApp])
        -> [Item] {
        let recordsByToken = Dictionary(installed.map { ($0.token, $0) }, uniquingKeysWith: { first, _ in first })
        return outdated.compactMap { update -> Item? in
            guard update.kind == .cask, !update.isPinned else { return nil }
            guard !ignoredTokens.contains(update.name) else { return nil }
            guard !isUncomparable(update.currentVersion) else { return nil }
            guard let record = recordsByToken[update.name],
                  let bundle = packageBundle(for: record, apps: apps) else {
                return nil
            }
            let installedVersion = bundle.version
            guard !installedVersion.isEmpty else { return nil }
            guard isNewer(update.currentVersion, than: installedVersion) else { return nil }
            return Item(id: "\(Source.packageManager.rawValue):\(update.name)",
                        source: .packageManager,
                        name: bundle.name,
                        installedVersion: installedVersion,
                        latestVersion: versionCore(update.currentVersion),
                        token: update.name,
                        bundlePath: bundle.path,
                        storePage: nil)
        }
    }

    static func packageBundle(for record: HomebrewCaskRecord,
                              apps: [InstalledApp],
                              homeDirectory: String = NSHomeDirectory()) -> InstalledApp? {
        if !record.appPaths.isEmpty {
            let managedPaths = Set(record.appPaths.map {
                URL(fileURLWithPath: $0).standardizedFileURL.path
            })
            let exact = apps.filter {
                managedPaths.contains(URL(fileURLWithPath: $0.path).standardizedFileURL.path)
            }
            return exact.count == 1 ? exact[0] : nil
        }
        let names = Set(candidateBundleNames(for: record))
        let standardDirectories = Set([
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path,
            URL(fileURLWithPath: homeDirectory, isDirectory: true)
                .appendingPathComponent("Applications", isDirectory: true)
                .standardizedFileURL.path,
        ])
        let candidates = apps.filter {
            let url = URL(fileURLWithPath: $0.path).standardizedFileURL
            return names.contains(url.lastPathComponent)
                && standardDirectories.contains(url.deletingLastPathComponent().path)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// App bundles a package might have put in place. Some packages install
    /// through an installer instead of dropping a bundle, so they declare no
    /// app at all; for those the catalog name is tried as a bundle name.
    /// A name that matches nothing is left out because there is no installed
    /// app to update.
    private static func candidateBundleNames(for record: HomebrewCaskRecord) -> [String] {
        guard record.appFileNames.isEmpty else { return record.appFileNames }
        return record.displayName.isEmpty ? [] : ["\(record.displayName).app"]
    }

    // MARK: - App Store source

    /// Bundle identifiers worth asking the store about: store-installed apps
    /// only, minus anything the package manager already answers for, so no
    /// app can show up twice and no identifier leaves the Mac needlessly.
    static func appStoreCandidates(apps: [InstalledApp],
                                   coveredPaths: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return apps.filter { app in
            app.isFromAppStore
                && !app.bundleID.isEmpty
                && !app.version.isEmpty
                && !coveredPaths.contains(app.path)
                && seen.insert(app.bundleID).inserted
        }
    }

    /// The public store lookup takes several identifiers at once, so a whole
    /// Mac is a couple of requests instead of one per app.
    static let storeLookupBatchSize = 20

    static func storeLookupURL(bundleIDs: [String], country: String?) -> URL? {
        guard !bundleIDs.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var query = [URLQueryItem(name: "bundleId", value: bundleIDs.joined(separator: ",")),
                     URLQueryItem(name: "entity", value: "macSoftware")]
        if let country, !country.isEmpty {
            query.append(URLQueryItem(name: "country", value: country))
        }
        components?.queryItems = query
        return components?.url
    }

    static func parseStoreLookup(_ data: Data) -> [String: StoreEntry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [:] }
        var entries: [String: StoreEntry] = [:]
        for result in results {
            // A bundle-ID lookup can ignore `entity` and return another
            // platform's listing. Its version and minimum OS then describe
            // a different binary, so only accept records identified as Mac.
            guard result["kind"] as? String == "mac-software" else { continue }
            guard let bundleID = result["bundleId"] as? String,
                  let version = result["version"] as? String,
                  !version.isEmpty else { continue }
            entries[bundleID] = StoreEntry(bundleID: bundleID,
                                           version: version,
                                           minimumOSVersion: result["minimumOsVersion"] as? String,
                                           page: result["trackViewUrl"] as? String)
        }
        return entries
    }

    static func appStoreUpdates(apps: [InstalledApp],
                                storeVersions: [String: StoreEntry],
                                operatingSystemVersion: String) -> [Item] {
        apps.compactMap { app in
            guard let entry = storeVersions[app.bundleID] else { return nil }
            if let minimum = entry.minimumOSVersion,
               compare(operatingSystemVersion, minimum) == .orderedAscending { return nil }
            guard isNewer(entry.version, than: app.version) else { return nil }
            return Item(id: "\(Source.appStore.rawValue):\(app.bundleID)",
                        source: .appStore,
                        name: app.name,
                        installedVersion: app.version,
                        latestVersion: entry.version,
                        token: nil,
                        bundlePath: app.path,
                        storePage: entry.page)
        }
    }

    // MARK: - Online catalog source

    static let onlineCatalogURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    /// Decodes only catalog fields that can prove an exact app-bundle match,
    /// a comparable version and macOS compatibility. Unknown fields remain
    /// ignored, while an unknown macOS constraint makes that entry ineligible.
    static func parseOnlineCatalog(_ data: Data) -> [CatalogEntry]? {
        guard let rawEntries = try? JSONDecoder().decode([RawCatalogEntry].self, from: data) else {
            return nil
        }
        return rawEntries.compactMap { raw in
            var appNames: [String] = []
            var bundleIDs: [String] = []
            for artifact in raw.artifacts {
                if let app = artifact.app {
                    let targets = app.compactMap(\.target)
                    let finalNames: [String]
                    if let target = artifact.target, target.hasSuffix(".app") {
                        finalNames = [target]
                    } else {
                        finalNames = targets.isEmpty ? app.compactMap(\.source) : targets
                    }
                    appNames.append(contentsOf: finalNames.map(bundleName))
                }
                bundleIDs.append(contentsOf: artifact.uninstall?.flatMap(\.quit) ?? [])
            }
            appNames = uniqueNonempty(appNames)
            guard !appNames.isEmpty else { return nil }
            let constraints = raw.dependsOn?.macOS ?? [:]
            return CatalogEntry(
                token: raw.token,
                version: raw.version,
                appNames: appNames,
                bundleIDs: uniqueNonempty(bundleIDs),
                minimumOSVersions: constraints[">="] ?? [],
                exactOSVersions: constraints["=="] ?? [],
                hasUnsupportedOSConstraint: constraints.keys.contains { $0 != ">=" && $0 != "==" })
        }
    }

    /// A missing body, failed HTTP response or malformed document all mean
    /// incomplete coverage, never an empty-but-successful catalog.
    static func parseOnlineCatalogResponse(_ data: Data?, statusCode: Int?) -> [CatalogEntry]? {
        guard let data, let statusCode, (200..<300).contains(statusCode) else { return nil }
        return parseOnlineCatalog(data)
    }

    /// Apps the online catalog may answer for. Store receipts and anything
    /// already owned by the package source never cross into this source.
    static func onlineCatalogCandidates(apps: [InstalledApp],
                                        coveredPaths: Set<String>) -> [InstalledApp] {
        apps.filter {
            !$0.isFromAppStore
                && !$0.bundleID.isEmpty
                && !$0.version.isEmpty
                && !coveredPaths.contains($0.path)
        }
    }

    /// Matches the exact installed bundle filename. A unique name is enough;
    /// when more than one catalog entry claims it, exactly one explicit bundle
    /// identifier must disambiguate the result.
    static func onlineCatalogUpdates(apps: [InstalledApp],
                                     catalog: [CatalogEntry],
                                     operatingSystemVersion: String,
                                     ignoredTokens: Set<String> = []) -> [Item] {
        var entriesByName: [String: [CatalogEntry]] = [:]
        for entry in catalog where !ignoredTokens.contains(entry.token) {
            for name in entry.appNames {
                entriesByName[name, default: []].append(entry)
            }
        }

        return apps.compactMap { app in
            let installedName = URL(fileURLWithPath: app.path).lastPathComponent
            let named = entriesByName[installedName] ?? []
            let matches: [CatalogEntry]
            if named.count <= 1 {
                matches = named
            } else {
                matches = named.filter { $0.bundleIDs.contains(app.bundleID) }
            }
            guard matches.count == 1, let entry = matches.first else { return nil }
            guard !isUncomparable(entry.version),
                  isCompatible(entry,
                               operatingSystemVersion: operatingSystemVersion) else { return nil }
            let latest = versionCore(entry.version)
            guard isNewer(latest, than: app.version) else { return nil }
            return Item(id: "\(Source.onlineCatalog.rawValue):\(app.path)",
                        source: .onlineCatalog,
                        name: app.name,
                        installedVersion: app.version,
                        latestVersion: latest,
                        token: nil,
                        bundlePath: app.path,
                        storePage: nil)
        }
    }

    private static func isCompatible(_ entry: CatalogEntry,
                                     operatingSystemVersion: String) -> Bool {
        guard !entry.hasUnsupportedOSConstraint else { return false }
        guard entry.minimumOSVersions.allSatisfy({
            compare(operatingSystemVersion, $0) != .orderedAscending
        }) else { return false }
        guard !entry.exactOSVersions.isEmpty else { return true }
        return entry.exactOSVersions.contains {
            compare(operatingSystemVersion, $0) == .orderedSame
                || operatingSystemVersion.hasPrefix("\($0).")
        }
    }

    private static func bundleName(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func uniqueNonempty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private struct RawCatalogEntry: Decodable {
        let token: String
        let version: String
        let artifacts: [RawCatalogArtifact]
        let dependsOn: RawCatalogDependencies?

        enum CodingKeys: String, CodingKey {
            case token, version, artifacts
            case dependsOn = "depends_on"
        }
    }

    private struct RawCatalogDependencies: Decodable {
        let macOS: [String: [String]]?

        enum CodingKeys: String, CodingKey {
            case macOS = "macos"
        }
    }

    private struct RawCatalogArtifact: Decodable {
        let app: [RawCatalogApp]?
        let target: String?
        let uninstall: [RawCatalogUninstall]?
    }

    private struct RawCatalogApp: Decodable {
        let source: String?
        let target: String?

        enum CodingKeys: String, CodingKey { case target }

        init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(String.self) {
                source = value
                target = nil
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = nil
            target = try container.decode(String.self, forKey: .target)
        }
    }

    private struct RawCatalogUninstall: Decodable {
        let quit: [String]

        enum CodingKeys: String, CodingKey { case quit }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let values = try? container.decode([String].self, forKey: .quit) {
                quit = values
            } else if let value = try? container.decode(String.self, forKey: .quit) {
                quit = [value]
            } else {
                quit = []
            }
        }
    }

    /// One list for the panel: apps that can be updated on the spot first,
    /// then store and online findings, each group alphabetical.
    static func merged(_ groups: [Item]...) -> [Item] {
        var seen = Set<String>()
        let all = groups.flatMap { $0 }.filter { seen.insert($0.id).inserted }
        return all.sorted { lhs, rhs in
            if lhs.source.sortOrder != rhs.source.sortOrder {
                return lhs.source.sortOrder < rhs.source.sortOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Package tokens for the rows the person ticked, in list order.
    static func tokens(in items: [Item], selection: Set<String>) -> [String] {
        items.filter { selection.contains($0.id) }.compactMap(\.token)
    }

    static func hasStoreSelection(in items: [Item], selection: Set<String>) -> Bool {
        items.contains { selection.contains($0.id) && $0.source == .appStore }
    }

    /// The page a store hand-off can land on. With one store row ticked that is
    /// its product page, the same place the row's own button goes; the store
    /// shows one product at a time, so several rows have no such page and the
    /// hand-off falls back to the updates page.
    static func singleStorePage(in items: [Item], selection: Set<String>) -> String? {
        let store = items.filter { selection.contains($0.id) && $0.source == .appStore }
        guard store.count == 1 else { return nil }
        return store[0].storePage
    }

    /// Selection kept honest against a list that just changed: rows that are
    /// gone drop out, and rows that appeared arrive already ticked, which is
    /// what "update everything" expects without any extra click.
    static func reconciledSelection(previous: Set<String>,
                                    knownIDs: Set<String>,
                                    items: [Item]) -> Set<String> {
        let selectable = items.filter(\.isSelectable)
        var next = previous.intersection(Set(selectable.map(\.id)))
        for item in selectable where !knownIDs.contains(item.id) {
            next.insert(item.id)
        }
        return next
    }

    // MARK: - Background schedule

    enum CheckFrequency: String, CaseIterable, Identifiable {
        case off, daily, weekly

        var id: String { rawValue }

        static func sanitized(_ raw: String?) -> CheckFrequency {
            CheckFrequency(rawValue: raw ?? "") ?? .off
        }

        var interval: TimeInterval {
            switch self {
            case .off: return 0
            case .daily: return 24 * 60 * 60
            case .weekly: return 7 * 24 * 60 * 60
            }
        }
    }

    /// A check that came due while the Mac was asleep or off runs shortly
    /// after launch instead of the instant the app comes up, so starting the
    /// app never waits on the package manager.
    static let catchUpDelay: TimeInterval = 180

    /// How old a finished check can be before a surface opening again is
    /// worth a fresh scan. Short enough that coming back from the store shows
    /// the truth, long enough that flipping between panel and Settings does
    /// not run the package manager over and over.
    static let staleAfter: TimeInterval = 10 * 60

    /// Whether opening a surface should scan again. The list is a claim about
    /// the Mac right now, so it re-reads after an update was installed
    /// somewhere else (the store), after nothing has been scanned in this
    /// process, and once the last answer is simply old.
    static func shouldRecheck(hasCheckedThisSession: Bool,
                              handoffPending: Bool,
                              lastCheck: Date?,
                              now: Date) -> Bool {
        if handoffPending { return true }
        guard hasCheckedThisSession, let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= staleAfter
    }

    static func nextCheckDate(lastCheck: Date?,
                              frequency: CheckFrequency,
                              now: Date) -> Date? {
        guard frequency != .off else { return nil }
        guard let lastCheck else { return now.addingTimeInterval(catchUpDelay) }
        let due = lastCheck.addingTimeInterval(frequency.interval)
        return due <= now ? now.addingTimeInterval(catchUpDelay) : due
    }
}
