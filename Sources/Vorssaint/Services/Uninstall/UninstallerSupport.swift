// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Pure ownership and leftover-matching rules for the Uninstaller. Bundle
/// identifiers never become paths by concatenation with a display name;
/// names are only compared against directory listings that already exist.
enum UninstallerSupport {
    enum Kind: Equatable {
        case support, caches, preferences, containers, logs, state, other
    }

    struct FileIdentity: Equatable, Hashable {
        let device: UInt64
        let inode: UInt64
    }

    /// Tokens that identify one selected app. Bundle identifiers stay exact;
    /// display names are compared after stripping punctuation so "App Name"
    /// and "AppName.plist" can meet without turning the name into a path.
    struct Identity: Equatable {
        var bundleIDs: Set<String>
        var nameTokens: Set<String>
        var teamIDs: Set<String>
        var groupIDs: Set<String>
    }

    enum LeftoverMatch: Equatable {
        case none
        /// Signed group or owned bundle identifier. Starts checked.
        case exact
        /// Related by a longer name fragment or team prefix. Starts unchecked.
        case related
    }

    struct DirListing: Equatable {
        let name: String
        let children: [DirListing]
        let bundleIdentifier: String?

        init(name: String, children: [DirListing], bundleIdentifier: String? = nil) {
            self.name = name
            self.children = children
            self.bundleIdentifier = bundleIdentifier
        }
    }

    struct Hit: Equatable {
        let path: String
        let confidence: LeftoverMatch
        let bundleIdentifier: String?
    }

    struct SearchFolder: Equatable {
        let url: URL
        let kind: Kind
        /// Unmatched directories are opened this many levels to catch
        /// vendor/app nesting such as Application Support/Vendor/App.
        let extraChildDepth: Int
        let crashReporter: Bool
        let readsContainerMetadata: Bool
        /// Display names are useful but ambiguous. Sensitive and Unix-style
        /// roots only accept signed group or bundle identifiers.
        let allowsNameMatches: Bool
        /// Shared group containers require an exact group from the selected
        /// app's valid signature; its bundle identifier alone is not proof.
        let requiresSignedGroup: Bool
    }

    /// The symbol a finished removal shows. A tick is for a removal that took
    /// everything; anything left behind gets a warning, so a done state cannot
    /// report success over its own survivors.
    static func doneSymbol(hasLeftovers: Bool) -> String {
        hasLeftovers ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    static func verifiedBundleID(_ rawValue: String?) -> String? {
        guard let rawValue,
              CleanerSupport.looksLikeBundleID(rawValue),
              !CleanerSupport.isProtectedBundleID(rawValue) else { return nil }
        return rawValue
    }

    static func fileIdentity(at url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    /// A removal path must still exist below the root that produced it and no
    /// component from the item through that root may have become a symlink.
    static func removalPathIsSafe(_ url: URL, within root: URL) -> Bool {
        var current = url.standardizedFileURL
        let root = root.standardizedFileURL
        guard current.path.hasPrefix(root.path + "/") else { return false }
        while current.path.count >= root.path.count {
            guard fileIdentity(at: current) != nil, !isSymbolicLink(current) else { return false }
            if current.path == root.path { return true }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { return false }
            current = parent
        }
        return false
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFLNK
    }

    static func isNestedBundle(_ candidateURL: URL?, in appURL: URL) -> Bool {
        guard let candidateURL else { return false }
        let appPath = appURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        return candidatePath.hasPrefix(appPath + "/")
    }

    static func sharedDataIsExclusive(selectedURL: URL,
                                      bundleID: String,
                                      knownApplications: [(url: URL, bundleID: String)]) -> Bool {
        let selectedPath = selectedURL.resolvingSymlinksInPath().standardizedFileURL.path
        return !knownApplications.contains { application in
            let applicationPath = application.url.resolvingSymlinksInPath().standardizedFileURL.path
            return application.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame
                && applicationPath != selectedPath
                && !applicationPath.hasPrefix(selectedPath + "/")
        }
    }

    static func exclusiveBundleIDs(_ candidates: Set<String>,
                                   selectedURL: URL,
                                   knownApplications: [(url: URL, bundleID: String)]) -> Set<String> {
        Set(candidates.filter {
            sharedDataIsExclusive(selectedURL: selectedURL,
                                  bundleID: $0,
                                  knownApplications: knownApplications)
        })
    }

    static func applicationIsInTrustedInstallRoot(_ url: URL, home: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        return roots.contains { path.hasPrefix($0 + "/") }
    }

    static func strippedAppName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".app") {
            name.removeLast(4)
        }
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func displayNames(localizedName: String,
                             fileName: String,
                             bundleName: String?,
                             bundleDisplayName: String?) -> [String] {
        [localizedName, fileName, bundleName, bundleDisplayName]
            .compactMap { $0 }
            .map(strippedAppName)
            .filter { !$0.isEmpty && !$0.contains("$") && !$0.contains("/") && !$0.contains("..") }
    }

    /// Lowercased letters and digits only, so "Example App 2" and "exampleapp2"
    /// compare as the same token. Punctuation never becomes a path.
    static func normalizedToken(_ raw: String) -> String {
        String(strippedAppName(raw).lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func identity(primaryBundleID: String? = nil,
                         bundleIDs: Set<String>,
                         displayNames: [String],
                         teamIDs: Set<String> = [],
                         groupIDs: Set<String> = []) -> Identity {
        var names = Set<String>()
        for name in displayNames {
            let token = normalizedToken(name)
            if token.count >= 3, !ignoredLastComponents.contains(token) { names.insert(token) }
            let withoutVersion = normalizedToken(nameWithoutTrailingVersion(name))
            if withoutVersion.count >= 3, !ignoredLastComponents.contains(withoutVersion) { names.insert(withoutVersion) }
        }
        let primary = primaryBundleID ?? (bundleIDs.count == 1 ? bundleIDs.first : nil)
        if let primary, let last = primary.split(separator: ".").last {
            let token = normalizedToken(String(last))
            if token.count >= 4, !ignoredLastComponents.contains(token) {
                names.insert(token)
            }
        }
        let teams = Set(teamIDs.map { $0.uppercased() }.filter(CleanerSupport.isTeamIdentifier))
        return Identity(bundleIDs: bundleIDs, nameTokens: names, teamIDs: teams, groupIDs: groupIDs)
    }

    static func technicalIdentity(_ identity: Identity) -> Identity {
        Identity(bundleIDs: identity.bundleIDs, nameTokens: [],
                 teamIDs: identity.teamIDs, groupIDs: identity.groupIDs)
    }

    static func leftoverMatch(_ rawName: String,
                              identity: Identity,
                              crashReporter: Bool = false) -> LeftoverMatch {
        guard !rawName.hasPrefix("."),
              !rawName.contains(".."),
              !rawName.contains("/") else { return .none }
        let stripped = stripKnownSuffix(rawName)
        if identity.groupIDs.contains(stripped) || identity.groupIDs.contains(rawName) {
            return .exact
        }
        let lowerRaw = rawName.lowercased()
        let lowerStripped = stripped.lowercased()
        for id in identity.bundleIDs {
            let lowerID = id.lowercased()
            if lowerStripped == lowerID || lowerRaw == lowerID { return .exact }
            if byHostPreference(rawName, belongsTo: id) { return .exact }
            if hasTeamPrefix(stripped, remainder: id, teamIDs: identity.teamIDs)
                || hasTeamPrefix(rawName, remainder: id, teamIDs: identity.teamIDs) {
                return .exact
            }
        }
        for id in identity.bundleIDs {
            let lowerID = id.lowercased()
            if lowerStripped.hasPrefix(lowerID + ".") || lowerRaw.hasPrefix(lowerID + ".") {
                return .related
            }
        }
        let normalizedStripped = normalizedToken(stripped)
        if normalizedStripped.count >= 3, identity.nameTokens.contains(normalizedStripped) {
            return .related
        }
        let normalizedRaw = normalizedToken(rawName)
        if normalizedRaw.count >= 3, identity.nameTokens.contains(normalizedRaw) {
            return .related
        }
        if crashReporter {
            let prefix = rawName.split { $0 == "_" || $0 == "-" }.first.map(String.init) ?? ""
            let prefixToken = normalizedToken(prefix)
            if prefixToken.count >= 3, identity.nameTokens.contains(prefixToken) { return .related }
            if identity.bundleIDs.contains(where: { rawName.hasPrefix($0) }) { return .exact }
        }
        // A reverse-DNS name is never claimed by a display-name fragment:
        // com.vendor.editor2 must not follow from uninstalling Editor.
        // Crash dumps are handled only in crash-reporter folders, by prefix.
        let looksLikeIdentifier = CleanerSupport.looksLikeBundleID(stripped)
            || CleanerSupport.looksLikeBundleID(rawName)
        let looksLikeCrashDump = rawName.range(of: #"_\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
            || rawName.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
        if !looksLikeIdentifier, !looksLikeCrashDump {
            for token in identity.nameTokens where token.count >= 5 {
                if normalizedStripped.hasPrefix(token) || normalizedRaw.hasPrefix(token) {
                    return .related
                }
            }
        }
        for team in identity.teamIDs {
            let upperStripped = stripped.uppercased()
            let upperRaw = rawName.uppercased()
            if upperStripped == team
                || upperStripped.hasPrefix(team + ".")
                || upperRaw.hasPrefix(team + ".") {
                return .related
            }
        }
        return .none
    }

    static func matchingGroupID(_ rawName: String, identity: Identity) -> String? {
        let stripped = stripKnownSuffix(rawName)
        return identity.groupIDs.first { $0 == rawName || $0 == stripped }
    }

    static func leftoverEntryMatches(_ rawName: String,
                                     identity: Identity,
                                     crashReporter: Bool = false) -> Bool {
        leftoverMatch(rawName, identity: identity, crashReporter: crashReporter) != .none
    }

    static func containerMetadataMatches(_ identifier: String, identity: Identity) -> LeftoverMatch {
        let match = leftoverMatch(identifier, identity: identity)
        if match != .none { return match }
        if let owner = CleanerSupport.bundleIDCandidate(fromEntryName: identifier) {
            return leftoverMatch(owner, identity: identity)
        }
        return .none
    }

    /// The most specific owned identifier that claims this entry, or the
    /// shortest identifier when only a display name matched.
    static func ownerBundleID(for entry: String,
                              identity: Identity,
                              crashReporter: Bool = false) -> String? {
        let byLength = identity.bundleIDs.sorted { $0.count > $1.count }
        for id in byLength {
            if leftoverEntryMatches(entry,
                                    identity: Identity(bundleIDs: [id], nameTokens: [],
                                                       teamIDs: [], groupIDs: []),
                                    crashReporter: crashReporter) {
                return id
            }
        }
        guard leftoverEntryMatches(entry, identity: identity, crashReporter: crashReporter) else {
            return nil
        }
        return identity.bundleIDs.min(by: { $0.count < $1.count })
    }

    /// Relative leftover names from one folder listing. Extra depth records
    /// `Vendor/App` when the vendor folder itself is not a match.
    static func leftoverHitRecords(listings: [DirListing],
                                   identity: Identity,
                                   extraChildDepth: Int,
                                   crashReporter: Bool = false,
                                   prefix: String = "") -> [Hit] {
        var hits: [Hit] = []
        for listing in listings {
            let path = prefix.isEmpty ? listing.name : prefix + "/" + listing.name
            let identifierMatch = listing.bundleIdentifier.map {
                leftoverMatch($0, identity: identity, crashReporter: crashReporter)
            } ?? .none
            let nameMatch = leftoverMatch(listing.name, identity: identity,
                                          crashReporter: crashReporter)
            let match: LeftoverMatch
            if identifierMatch == .exact || nameMatch == .exact {
                match = .exact
            } else if identifierMatch == .related || nameMatch == .related {
                match = .related
            } else {
                match = .none
            }
            if match == .related, extraChildDepth > 0, !listing.children.isEmpty {
                let nested = leftoverHitRecords(
                    listings: listing.children,
                    identity: identity,
                    extraChildDepth: extraChildDepth - 1,
                    crashReporter: crashReporter,
                    prefix: path)
                if !nested.isEmpty {
                    hits.append(contentsOf: nested)
                    continue
                }
            }
            if match != .none {
                hits.append(Hit(path: path, confidence: match,
                                bundleIdentifier: identifierMatch == .none
                                    ? nil : listing.bundleIdentifier))
                continue
            }
            if extraChildDepth > 0 {
                hits.append(contentsOf: leftoverHitRecords(
                    listings: listing.children,
                    identity: identity,
                    extraChildDepth: extraChildDepth - 1,
                    crashReporter: crashReporter,
                    prefix: path))
            }
        }
        return hits
    }

    static func searchFolders(home: URL,
                              darwinCache: URL?,
                              darwinTemp: URL?) -> [SearchFolder] {
        var result: [SearchFolder] = []
        let userLibrary = home.appendingPathComponent("Library", isDirectory: true)
        let systemLibrary = URL(fileURLWithPath: "/Library", isDirectory: true)
        for spec in sharedLibraryFolders {
            result.append(folder(spec, under: userLibrary))
            result.append(folder(spec, under: systemLibrary))
        }
        for spec in userLibraryFolders {
            result.append(folder(spec, under: userLibrary))
        }
        for spec in systemLibraryFolders {
            result.append(folder(spec, under: systemLibrary))
        }
        result.append(SearchFolder(url: home.appendingPathComponent(".config", isDirectory: true),
                                   kind: .support, extraChildDepth: 0, crashReporter: false,
                                   readsContainerMetadata: false, allowsNameMatches: false,
                                   requiresSignedGroup: false))
        result.append(SearchFolder(url: home.appendingPathComponent(".cache", isDirectory: true),
                                   kind: .caches, extraChildDepth: 0, crashReporter: false,
                                   readsContainerMetadata: false, allowsNameMatches: false,
                                   requiresSignedGroup: false))
        result.append(SearchFolder(
            url: home.appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true),
            kind: .support, extraChildDepth: 0, crashReporter: false,
            readsContainerMetadata: false, allowsNameMatches: false,
            requiresSignedGroup: false))
        if let darwinCache {
            result.append(SearchFolder(url: darwinCache, kind: .caches,
                                       extraChildDepth: 0, crashReporter: false,
                                       readsContainerMetadata: false, allowsNameMatches: false,
                                       requiresSignedGroup: false))
        }
        if let darwinTemp {
            result.append(SearchFolder(url: darwinTemp, kind: .caches,
                                       extraChildDepth: 0, crashReporter: false,
                                       readsContainerMetadata: false, allowsNameMatches: false,
                                       requiresSignedGroup: false))
        }
        result.append(SearchFolder(url: URL(fileURLWithPath: "/private/var/db/receipts",
                                            isDirectory: true),
                                   kind: .other, extraChildDepth: 0, crashReporter: false,
                                   readsContainerMetadata: false, allowsNameMatches: false,
                                   requiresSignedGroup: false))
        result.append(SearchFolder(
            url: URL(fileURLWithPath: "/Users/Shared/Library/Application Support", isDirectory: true),
            kind: .support, extraChildDepth: 2, crashReporter: false,
            readsContainerMetadata: false, allowsNameMatches: true,
            requiresSignedGroup: false))
        return result
    }

    /// Spotlight query scoped later to Library-like roots. Bundle identifiers
    /// and display-name tokens match as prefixes so `.plist` siblings and
    /// app containers come back. Never queries personal folders.
    static func leftoverSpotlightExpression(identity: Identity) -> String? {
        var clauses: [String] = []
        for id in identity.bundleIDs.sorted() {
            clauses.append("kMDItemFSName == \"\(spotlightEscape(id))*\"cd")
            if clauses.count >= 16 { break }
        }
        for token in identity.nameTokens.sorted() where token.count >= 4 {
            clauses.append("kMDItemFSName == \"\(spotlightEscape(token))*\"cd")
            if clauses.count >= 24 { break }
        }
        guard !clauses.isEmpty else { return nil }
        return clauses.joined(separator: " || ")
    }

    static func leftoverSpotlightPathIsAllowed(_ path: String, roots: [URL]) -> Bool {
        let forbidden = ["/Desktop/", "/Documents/", "/Downloads/",
                         "/Movies/", "/Music/", "/Pictures/", "/Public/"]
        if forbidden.contains(where: { path.contains($0) }) { return false }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let matchingRoot = roots.first(where: { standardized.hasPrefix($0.path + "/") }) else { return false }
        let relative = String(standardized.dropFirst(matchingRoot.path.count + 1))
        let components = relative.split(separator: "/")
        // Leftovers never live deeper than a vendor/app folder or root entry
        return components.count <= 2
    }

    /// Spotlight spans the whole Library and must preserve the stricter rules
    /// used by direct scans for shared containers and privileged locations.
    static func spotlightIdentity(for path: String, identity: Identity) -> Identity {
        if path.contains("/Group Containers/") {
            return Identity(bundleIDs: [], nameTokens: [], teamIDs: [],
                            groupIDs: identity.groupIDs)
        }
        let technicalSegments = [
            "/Application Scripts/", "/Containers/", "/Preferences/ByHost/",
            "/SyncedPreferences/", "/LaunchAgents/", "/LaunchDaemons/",
            "/PrivilegedHelperTools/", "/Extensions/", "/StartupItems/",
        ]
        if technicalSegments.contains(where: path.contains) {
            return technicalIdentity(identity)
        }
        return identity
    }

    static func nameWithoutTrailingVersion(_ raw: String) -> String {
        let stripped = strippedAppName(raw)
        let suffixes = #"\d+(\.\d+)*|nightly|beta|alpha|dev|canary|preview|insider|stable|release|rc|lts|developer edition|technology preview"#
        guard let regex = try? NSRegularExpression(
            pattern: "\\s+(?:\(suffixes))\\s*$", options: [.caseInsensitive]) else {
            return stripped
        }
        let range = NSRange(stripped.startIndex..., in: stripped)
        return regex.stringByReplacingMatches(in: stripped, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private struct LibraryFolderSpec: Equatable {
        let relative: String
        let kind: Kind
        let extraChildDepth: Int
        let crashReporter: Bool
        let readsContainerMetadata: Bool
        let allowsNameMatches: Bool
        let requiresSignedGroup: Bool
    }

    /// Last bundle-id components that name a role, not the app. Matching
    /// those as folder names would claim helpers that belong to everyone.
    private static let ignoredLastComponents: Set<String> = [
        "app", "mac", "macos", "osx", "helper", "agent", "daemon", "service",
        "desktop", "client", "launcher", "plugin", "extension", "web", "free",
        "pro", "lite", "plus", "ui", "xpc", "login", "updater", "installer",
        "renderer", "gpu", "worker", "crashpad", "broker", "utility", "alert",
        "network", "audio", "server", "shared", "core", "common", "framework",
        "bundle", "process", "handler", "tool", "runtime", "electron", "java",
        "python", "node", "mono", "wine",
    ]

    private static let leftoverSuffixes = [
        ".plist", ".savedState", ".binarycookies", ".prefPane", ".qlgenerator",
        ".mdimporter", ".service", ".appex", ".plugin", ".webplugin", ".saver",
        ".colorPicker", ".wdgt", ".bundle", ".sfl", ".sfl2", ".sfl3", ".bom",
        ".action", ".workflow", ".app", ".framework", ".component", ".vst",
        ".vst3", ".clap", ".dpm", ".aaxplugin", ".dictionary", ".safariextz",
        ".mailbundle",
    ]

    private static let sharedLibraryFolders: [LibraryFolderSpec] = [
        spec("Application Support", .support, depth: 2),
        spec("Application Support/CrashReporter", .logs, crash: true),
        spec("Caches", .caches, depth: 1),
        spec("Preferences", .preferences),
        spec("Logs", .logs, depth: 1),
        spec("Logs/DiagnosticReports", .logs, crash: true),
        spec("LaunchAgents", .other, names: false),
        spec("PreferencePanes", .other),
        spec("Internet Plug-Ins", .other),
        spec("Services", .other),
        spec("QuickLook", .other),
        spec("Spotlight", .other),
        spec("Input Methods", .other),
        spec("Screen Savers", .other),
        spec("ColorPickers", .other),
        spec("Audio/Plug-Ins", .other, depth: 1),
        spec("PrivilegedHelperTools", .other, names: false),
        spec("Frameworks", .other),
        spec("Automator", .other),
        spec("CoreImage", .other),
        spec("Dictionaries", .other),
        spec("Components", .other),
    ]

    private static let userLibraryFolders: [LibraryFolderSpec] = [
        spec("Preferences/ByHost", .preferences, names: false),
        spec("Saved Application State", .state),
        spec("Autosave Information", .state),
        spec("SyncedPreferences", .preferences, names: false),
        spec("HTTPStorages", .caches),
        spec("WebKit", .caches),
        spec("WebKit/com.apple.WebKit.WebContent", .caches, names: false),
        spec("Containers", .containers, metadata: true, names: false),
        spec("Group Containers", .containers, metadata: true, names: false, signedGroup: true),
        spec("Application Scripts", .containers, names: false),
        spec("Application Support/FileProvider", .support, names: false),
        spec("Caches/com.apple.nsurlsessiond/Downloads", .caches, names: false),
        spec("Cookies", .caches),
        spec("Widgets", .other),
        spec("Address Book Plug-Ins", .other),
        spec("Contextual Menu Items", .other),
        spec("Safari/Extensions", .other),
        spec("Accessibility", .other),
        spec("Mail/Bundles", .other),
        spec("Workflows", .other),
        spec("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments",
             .preferences),
    ]

    private static let systemLibraryFolders: [LibraryFolderSpec] = [
        spec("LaunchDaemons", .other, names: false),
        spec("Extensions", .other, names: false),
        spec("StartupItems", .other, names: false),
    ]

    private static func spec(_ relative: String,
                             _ kind: Kind,
                             depth: Int = 0,
                             crash: Bool = false,
                             metadata: Bool = false,
                             names: Bool = true,
                             signedGroup: Bool = false) -> LibraryFolderSpec {
        LibraryFolderSpec(relative: relative, kind: kind, extraChildDepth: depth,
                          crashReporter: crash, readsContainerMetadata: metadata,
                          allowsNameMatches: names, requiresSignedGroup: signedGroup)
    }

    private static func folder(_ spec: LibraryFolderSpec, under root: URL) -> SearchFolder {
        SearchFolder(url: url(root, spec.relative),
                     kind: spec.kind,
                     extraChildDepth: spec.extraChildDepth,
                     crashReporter: spec.crashReporter,
                     readsContainerMetadata: spec.readsContainerMetadata,
                     allowsNameMatches: spec.allowsNameMatches,
                     requiresSignedGroup: spec.requiresSignedGroup)
    }

    private static func url(_ root: URL, _ relative: String) -> URL {
        relative.split(separator: "/").reduce(root) {
            $0.appendingPathComponent(String($1), isDirectory: true)
        }
    }

    private static func stripKnownSuffix(_ rawName: String) -> String {
        let lowered = rawName.lowercased()
        for suffix in leftoverSuffixes where lowered.hasSuffix(suffix.lowercased()) {
            return String(rawName.dropLast(suffix.count))
        }
        return rawName
    }

    private static func hasTeamPrefix(_ rawName: String,
                                      remainder: String,
                                      teamIDs: Set<String>) -> Bool {
        guard let dot = rawName.firstIndex(of: ".") else { return false }
        let prefix = String(rawName[..<dot])
        let suffix = String(rawName[rawName.index(after: dot)...])
        return CleanerSupport.isTeamIdentifier(prefix)
            && teamIDs.contains(where: { $0.caseInsensitiveCompare(prefix) == .orderedSame })
            && suffix.caseInsensitiveCompare(remainder) == .orderedSame
    }

    private static func byHostPreference(_ rawName: String, belongsTo bundleID: String) -> Bool {
        guard rawName.lowercased().hasSuffix(".plist") else { return false }
        let withoutPlist = String(rawName.dropLast(".plist".count))
        guard let dot = withoutPlist.lastIndex(of: ".") else { return false }
        let owner = String(withoutPlist[..<dot])
        let host = String(withoutPlist[withoutPlist.index(after: dot)...])
        return host.count == 36
            && CleanerSupport.containsUUIDComponent(host)
            && owner.caseInsensitiveCompare(bundleID) == .orderedSame
    }

    private static func spotlightEscape(_ word: String) -> String {
        var result = ""
        for character in word {
            if character == "\\" || character == "\"" || character == "*" || character == "?" {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
