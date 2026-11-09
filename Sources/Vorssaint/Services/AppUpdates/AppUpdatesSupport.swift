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
        /// Stable across sources, app renames and settings restores on another Mac.
        var bundleID: String? = nil

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
        var buildVersion: String = ""
        var storeID: String? = nil
        var updateFeed: AppUpdateFeedSupport.Feed? = nil
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

    // MARK: - Update rules

    /// One choice per app: skip exactly this release, or stop checking until removed.
    /// Names are display metadata; neither a path nor a source-specific row ID is portable.
    struct UpdateRule: Codable, Identifiable, Equatable {
        let bundleID: String
        let name: String
        let version: String?

        var id: String { bundleID }

        func hides(_ item: Item) -> Bool {
            guard item.bundleID == bundleID else { return false }
            guard let version else { return true }
            return versionCore(version) == versionCore(item.latestVersion)
        }
    }

    static func decodedRules(_ raw: String?) -> [UpdateRule] {
        guard let data = raw?.data(using: .utf8),
              let rules = try? JSONDecoder().decode([UpdateRule].self, from: data) else { return [] }
        var seen = Set<String>()
        return rules.filter { rule in
            !rule.bundleID.isEmpty && !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && rule.bundleID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
                && !rule.bundleID.contains("/")
                && (rule.version.map { !isUncomparable($0) } ?? true)
                && seen.insert(rule.bundleID).inserted
        }
    }

    static func encodedRules(_ rules: [UpdateRule]) -> String? {
        (try? JSONEncoder().encode(rules)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func checkedApps(_ apps: [InstalledApp], rules: [UpdateRule]) -> [InstalledApp] {
        let excluded = Set(rules.filter { $0.version == nil }.map(\.bundleID))
        return apps.filter { !excluded.contains($0.bundleID) }
    }

    static func visibleItems(_ items: [Item], rules: [UpdateRule]) -> [Item] {
        items.filter { item in !rules.contains { $0.hides(item) } }
    }

    // MARK: - Version comparison

    /// Package versions carry a revision after a comma ("3.5.262,260717d");
    /// only the part in front of it lines up with what an app bundle reports.
    static func versionCore(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        var comparable = trimmed
        if (comparable.first == "v" || comparable.first == "V"),
           comparable.dropFirst().first?.isNumber == true {
            comparable.removeFirst()
        }
        guard let comma = comparable.firstIndex(of: ",") else { return comparable }
        return String(comparable[comparable.startIndex..<comma])
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
        // The text tie-break folds case, so two spellings of one release are
        // equal here. Returning descending for both directions made the
        // result antisymmetric and left isNewer true against itself.
        let left = lhs.lowercased(), right = rhs.lowercased()
        if left == right { return .orderedSame }
        // A number after the letters is still a number: as text, "beta10"
        // sorts before "beta9" and the tenth beta is never offered.
        let leftRuns = runs(of: left), rightRuns = runs(of: right)
        for (a, b) in zip(leftRuns, rightRuns) where a != b {
            if a.allSatisfy(\.isNumber) && b.allSatisfy(\.isNumber) {
                let numbers = compareDigits(a, b)
                if numbers != .orderedSame { return numbers }
            } else {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        if leftRuns.count == rightRuns.count { return .orderedSame }
        return leftRuns.count < rightRuns.count ? .orderedAscending : .orderedDescending
    }

    /// "beta10" as ["beta", "10"]: stretches of digits and of everything else.
    private static func runs(of part: String) -> [String] {
        var runs: [String] = []
        for character in part {
            if let last = runs.last?.last, last.isNumber == character.isNumber {
                runs[runs.count - 1].append(character)
            } else {
                runs.append(String(character))
            }
        }
        return runs
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

    /// Positron's bundle shows the version of the editor it is built on
    /// (Code - OSS "1.134.0"). Its own release and build are in the product
    /// file beside its code, the numbers the catalog lists as "2026.10.0-297".
    static func productRelease(_ product: Data?) -> (version: String, build: String)? {
        guard let product,
              let fields = try? JSONSerialization.jsonObject(with: product) as? [String: Any],
              let version = fields["positronVersion"] as? String,
              version.contains(where: \.isNumber) else { return nil }
        return (version, fields["positronBuildNumber"].map { "\($0)" } ?? "")
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
                  let bundle = packageBundle(for: record, apps: apps),
                  !bundle.isFromAppStore else {
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
                        storePage: nil,
                        bundleID: bundle.bundleID)
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

    static func storeIDLookupURL(ids: [String], country: String?) -> URL? {
        guard !ids.isEmpty, ids.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        var components = URLComponents(string: "https://uclient-api.itunes.apple.com/WebObjects/MZStorePlatform.woa/wa/lookup")
        var query = [URLQueryItem(name: "id", value: ids.joined(separator: ",")),
                     URLQueryItem(name: "version", value: "2"),
                     URLQueryItem(name: "p", value: "mdm-lockup"),
                     URLQueryItem(name: "caller", value: "MDM"),
                     URLQueryItem(name: "platform", value: "macappstore")]
        if let country, !country.isEmpty { query.append(URLQueryItem(name: "cc", value: country)) }
        components?.queryItems = query
        return components?.url
    }

    /// The platform-specific lookup supplies the Mac build and Mac minimum
    /// OS even for a universal listing whose generic result describes mobile.
    static func storeMetadataResponse(_ data: Data?, statusCode: Int?) -> [String: StoreEntry] {
        guard let data, let statusCode, (200..<300).contains(statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [String: [String: Any]] else { return [:] }
        var entries: [String: StoreEntry] = [:]
        for result in results.values {
            guard let families = result["deviceFamilies"] as? [String], families.contains("mac"),
                  let bundleID = result["bundleId"] as? String, !bundleID.isEmpty,
                  let minimum = result["minimumOSVersion"] as? String, !minimum.isEmpty,
                  let offers = result["offers"] as? [[String: Any]] else { continue }
            let versions = offers.compactMap { offer -> String? in
                guard let assets = offer["assets"] as? [[String: Any]],
                      assets.contains(where: { $0["flavor"] as? String == "macSoftware" }),
                      let version = offer["version"] as? [String: Any],
                      let display = version["display"] as? String, !display.isEmpty else { return nil }
                return display
            }
            guard let version = versions.max(by: { compare($0, $1) == .orderedAscending }) else { continue }
            entries[bundleID] = StoreEntry(bundleID: bundleID, version: version,
                                           minimumOSVersion: minimum, page: result["url"] as? String)
        }
        return entries
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

    static func storeLookupResponse(_ data: Data?, statusCode: Int?) -> [String: StoreEntry] {
        guard let data, let statusCode, (200..<300).contains(statusCode) else {
            return [:]
        }
        return parseStoreLookup(data)
    }

    /// A successful request can still omit apps unavailable in this catalog
    /// or region. Only the combined answer can establish complete coverage.
    static func hasStoreCoverage(bundleIDs: [String], entries: [String: StoreEntry]) -> Bool {
        bundleIDs.allSatisfy { entries[$0] != nil }
    }

    /// Keep partial source failures visible without listing apps whose own
    /// publisher already answered, or repeating one app for several sources.
    static func uncheckedAppNames(_ apps: [InstalledApp], checkedPaths: Set<String>) -> [String] {
        Set(apps.filter { !checkedPaths.contains($0.path) }.map(\.name))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
                        storePage: entry.page,
                        bundleID: app.bundleID)
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
                appNames.append(contentsOf: artifact.uninstall?.flatMap(\.appNames) ?? [])
            }
            appNames = uniqueNonempty(appNames)
            bundleIDs = uniqueNonempty(bundleIDs)
            guard !appNames.isEmpty || !bundleIDs.isEmpty else { return nil }
            let constraints = raw.dependsOn?.macOS ?? [:]
            return CatalogEntry(
                token: raw.token,
                version: raw.version,
                appNames: appNames,
                bundleIDs: bundleIDs,
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

    /// Some catalog versions end in a build after a dash ("3.8-08539"), the
    /// way others carry one after a comma. A bundle that reports only its
    /// release ("3.8.0") lines up with the part in front of the dash, unless
    /// its own build is numbered like the catalog's and is older: that is a
    /// newer build of the same release ("4.0.4" build 4900 before "4.0.4-4926").
    ///
    /// Everything else is compared whole: a bundle with a dash of its own or
    /// a further number of its own may be reporting that part, a short number
    /// can be a fix release ("4.10-8" after "4.10-7"), and a dated version
    /// ("2024-01-15") has no dotted release in front of its last dash.
    static func catalogRelease(_ catalogVersion: String, installedVersion: String,
                               installedBuild: String = "") -> String {
        let catalogVersion = withoutBuildLabel(catalogVersion)
        let installed = versionCore(installedVersion)
        guard !installed.contains("-"),
              let dash = catalogVersion.lastIndex(of: "-") else { return catalogVersion }
        let release = catalogVersion[..<dash]
        let build = catalogVersion[catalogVersion.index(after: dash)...]
        let releaseParts = release.split(separator: ".", omittingEmptySubsequences: false)
        func isNumber(_ part: Substring) -> Bool {
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard build.count >= 3, isNumber(build),
              releaseParts.count > 1, releaseParts.allSatisfy(isNumber),
              parts(of: installed).dropFirst(releaseParts.count).allSatisfy({
                  $0.allSatisfy(\.isNumber) && stripLeadingZeros($0).isEmpty
              }) else { return catalogVersion }
        // Only a build with as many digits as the catalog's counts the same
        // way; a shorter or longer one ("21", a 13-digit timestamp) is some
        // other number. A build written out in full ("4.0.4.4900") is this
        // release followed by its build.
        var ownBuild = installedBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownParts = ownBuild.split(separator: ".", omittingEmptySubsequences: false)
        if ownParts.count == releaseParts.count + 1, ownParts.allSatisfy(isNumber),
           zip(releaseParts, ownParts).allSatisfy({ compareDigits(String($0), String($1)) == .orderedSame }) {
            ownBuild = String(ownParts[releaseParts.count])
        }
        if isNumber(Substring(ownBuild)),
           stripLeadingZeros(ownBuild).count == stripLeadingZeros(String(build)).count,
           compareDigits(String(build), ownBuild) == .orderedDescending {
            return catalogVersion
        }
        return String(release)
    }

    /// A commit hash after the last dash ("3.6.7-dbc92f97") or build metadata
    /// after a plus ("3.11.1108+next.727501f") names a build without placing
    /// it, the way the part after a comma does, so only the version in front
    /// of it counts. A plain number after a plus ("3.22.3+105") is a build and
    /// is compared like one after a dash.
    private static func withoutBuildLabel(_ version: String) -> String {
        var version = version
        if let plus = version.firstIndex(of: "+"), version[..<plus].contains(where: \.isNumber) {
            let metadata = version[version.index(after: plus)...]
            version = !metadata.isEmpty && metadata.allSatisfy({ $0.isASCII && $0.isNumber })
                ? String(version[..<plus]) + "-" + metadata : String(version[..<plus])
        }
        guard let dash = version.lastIndex(of: "-") else { return version }
        let label = version[version.index(after: dash)...]
        let isHash = label.count >= 7 && label.allSatisfy { "0123456789abcdef".contains($0) }
            && label.contains(where: \.isLetter) && label.contains(where: \.isNumber)
        return isHash ? String(version[..<dash]) : version
    }

    /// The version and build a new project starts with, or a version of only
    /// zeros ("0.0.0") that was never set. A bundle that still carries them
    /// says nothing about which release it holds, so only a catalog at that
    /// same version can vouch for it. The build must be exactly 1: one that
    /// repeats the version ("1.0.0" twice, as Electron apps are built) belongs
    /// to a real first release.
    static func reportsPlaceholderVersion(_ app: InstalledApp) -> Bool {
        compare(versionCore(app.version), "0") == .orderedSame
            || (compare(versionCore(app.version), "1") == .orderedSame
            && app.buildVersion.trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    }

    /// A bundle whose build is the catalog's own number holds that release,
    /// whatever version it shows: Sonos shows 17.2.5 and builds 90.0.82050 for
    /// "90.0-82050", 4K Video Downloader+ shows 26.3 and builds 26.3.5. Only an
    /// exact match counts, of three or more parts or of one number with five or
    /// more digits (a date or a build count), or with three or more that the
    /// bundle also shows ("Build 4215"). A build counter ("2", "183") or a short
    /// pair ("1.5") never stands in for a release by chance, and a newer catalog
    /// number is still compared with the version the bundle shows.
    static func buildMatchesCatalog(_ app: InstalledApp, catalogVersion: String) -> Bool {
        let shown = parts(of: versionCore(app.version))
        func isSpecific(_ version: String) -> Bool {
            let numbers = parts(of: version)
            guard numbers.count == 1 else { return numbers.count >= 3 }
            let digits = stripLeadingZeros(numbers[0]).count
            return numbers[0].allSatisfy(\.isNumber)
                && (digits >= 5 || (digits >= 3 && shown.contains(numbers[0])))
        }
        let build = versionCore(app.buildVersion)
        return isSpecific(build) && isSpecific(catalogVersion)
            && compare(build, catalogVersion) == .orderedSame
    }

    /// The bundle's number in the catalog's form. Some catalog versions write
    /// the build as one more dotted number ("2.19.0.2258" for a bundle that
    /// shows 2.19.0 and builds 2258). A build with as many digits as that
    /// number completes the bundle's version, so the same build is current and
    /// an older one is a newer build of the same release. A build already
    /// written in that form ("2.19.0.2201") is that number. Otherwise this is
    /// the version the bundle shows.
    static func installedNumber(_ app: InstalledApp, against release: String) -> String {
        let shown = versionCore(app.version)
        let build = app.buildVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let shownParts = numericParts(shown), let releaseParts = numericParts(release),
              releaseParts.count == shownParts.count + 1,
              zip(shownParts, releaseParts).allSatisfy({ compareDigits($0, $1) == .orderedSame }),
              let catalogBuild = releaseParts.last, stripLeadingZeros(catalogBuild).count >= 3,
              let buildParts = numericParts(build) else { return app.version }
        if buildParts.count == releaseParts.count,
           zip(shownParts, buildParts).allSatisfy({ compareDigits($0, $1) == .orderedSame }),
           let ownBuild = buildParts.last,
           stripLeadingZeros(ownBuild).count == stripLeadingZeros(catalogBuild).count {
            return build
        }
        guard buildParts.count == 1,
              stripLeadingZeros(build).count == stripLeadingZeros(catalogBuild).count else { return app.version }
        return "\(shown).\(build)"
    }

    /// Whether a catalog number goes past the bundle's only in parts the
    /// bundle never reports, so the bundle cannot say which of those releases
    /// it holds: "2026.1" stands for every "2026.1.x.y" an app numbered that
    /// way ships, "2026.5.1" for every build "2026.5.1.N" whose N has three or
    /// more digits, and "5.17" for every "5.17-N". One more short dotted part
    /// ("1.2" before "1.2.1") is the usual next release and still counts, and
    /// so does a bundle that reports a dash of its own.
    static func catalogOnlyAddsUnreportedParts(_ catalogVersion: String, installedVersion: String) -> Bool {
        let installed = versionCore(installedVersion)
        guard !installed.contains("-"), let installedParts = numericParts(installed) else { return false }
        guard let dash = catalogVersion.lastIndex(of: "-") else {
            guard let catalogParts = numericParts(catalogVersion) else { return false }
            let addsBuild = catalogParts.count == installedParts.count + 1
                && stripLeadingZeros(catalogParts[installedParts.count]).count >= 3
            return (catalogParts.count >= installedParts.count + 2 || addsBuild)
                && zip(installedParts, catalogParts).allSatisfy { compareDigits($0, $1) == .orderedSame }
        }
        let release = String(catalogVersion[..<dash])
        let suffix = catalogVersion[catalogVersion.index(after: dash)...]
        return (1...2).contains(suffix.count) && suffix.allSatisfy { $0.isASCII && $0.isNumber }
            && (numericParts(release)?.count ?? 0) > 1
            && compare(release, installed) == .orderedSame
    }

    /// A catalog number the bundle cannot be placed against: a version with
    /// no number in it ("??.??", "lazer"), a template bundle that does not
    /// match it, or a newer number that only adds parts the bundle never reports.
    static func cannotCompare(_ app: InstalledApp, with release: String) -> Bool {
        guard versionCore(app.version).contains(where: \.isNumber) else { return true }
        if reportsPlaceholderVersion(app) {
            return compare(release, versionCore(app.version)) != .orderedSame
        }
        let installed = installedNumber(app, against: release)
        return isNewer(release, than: installed)
            && catalogOnlyAddsUnreportedParts(release, installedVersion: installed)
    }

    /// "2026.1.4" as its numbers, or nil when any part is not a plain number.
    private static func numericParts(_ version: String) -> [String]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } } ? parts : nil
    }

    /// Exact names take priority; a single identity also finds renamed apps
    /// and installer packages without confusing companion apps with the owner.
    /// Apps whose version cannot be compared come back on their own, so they
    /// are named instead of reported as updates or as current.
    static func onlineCatalogFindings(apps: [InstalledApp],
                                      catalog: [CatalogEntry],
                                      operatingSystemVersion: String,
                                      ignoredTokens: Set<String> = [])
        -> (items: [Item], checkedPaths: Set<String>, uncomparableApps: [InstalledApp]) {
        var entriesByName: [String: [CatalogEntry]] = [:]
        var entriesByID: [String: [CatalogEntry]] = [:]
        for entry in catalog where !ignoredTokens.contains(entry.token) {
            for name in entry.appNames {
                entriesByName[name, default: []].append(entry)
            }
            // An uninstall list can also name companion apps it must quit.
            // Only a single declared identity can stand in for a filename.
            if entry.bundleIDs.count == 1, let id = entry.bundleIDs.first {
                entriesByID[id, default: []].append(entry)
            }
        }

        var checkedPaths = Set<String>()
        var uncomparableApps: [InstalledApp] = []
        let items = apps.compactMap { app -> Item? in
            let installedName = URL(fileURLWithPath: app.path).lastPathComponent
            let named = entriesByName[installedName] ?? []
            let matches = named.isEmpty
                ? entriesByID[app.bundleID] ?? []
                : named.filter { $0.bundleIDs.isEmpty || $0.bundleIDs.contains(app.bundleID) }
            guard matches.count == 1, let entry = matches.first else { return nil }
            guard !isUncomparable(entry.version),
                  isCompatible(entry,
                               operatingSystemVersion: operatingSystemVersion) else { return nil }
            let latest = versionCore(entry.version)
            if buildMatchesCatalog(app, catalogVersion: latest) {
                checkedPaths.insert(app.path)
                return nil
            }
            let release = catalogRelease(latest, installedVersion: app.version, installedBuild: app.buildVersion)
            if cannotCompare(app, with: release) {
                uncomparableApps.append(app)
                return nil
            }
            // Current versions are covered too; absence of a row alone proves nothing.
            if !isUncomparable(app.version) { checkedPaths.insert(app.path) }
            guard isNewer(release, than: installedNumber(app, against: release)) else { return nil }
            return Item(id: "\(Source.onlineCatalog.rawValue):\(app.path)",
                        source: .onlineCatalog,
                        name: app.name,
                        installedVersion: app.version,
                        latestVersion: latest,
                        token: nil,
                        bundlePath: app.path,
                        storePage: nil,
                        bundleID: app.bundleID)
        }
        return (items, checkedPaths, uncomparableApps)
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
        let appNames: [String]

        enum CodingKeys: String, CodingKey { case quit, delete }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func strings(_ key: CodingKeys) -> [String] {
                if let values = try? container.decode([String].self, forKey: key) { return values }
                if let value = try? container.decode(String.self, forKey: key) { return [value] }
                return []
            }
            quit = strings(.quit)
            // Installer packages often declare their app only in removal
            // metadata. Accept a literal app in a standard application folder.
            appNames = strings(.delete).filter {
                let parent = ($0 as NSString).deletingLastPathComponent
                return (parent == "/Applications" || parent == "~/Applications")
                    && $0.hasSuffix(".app") && !$0.contains(where: { "*?[]".contains($0) })
            }.map { ($0 as NSString).lastPathComponent }
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
