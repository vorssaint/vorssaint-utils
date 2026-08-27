// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The Mac's own Settings panes, as rows.
///
/// System Settings is a dozen clicks deep and its search is its own; a person
/// who wants Displays should be able to type "displays" into the bar they
/// already have open. Every pane on this Mac is read once, from the extensions
/// macOS ships them as, so a new pane in a new macOS appears without the app
/// being told about it.
///
/// Nothing here runs while the bar is closed, and the scan happens once per
/// launch, off the main thread, behind the same background load as the apps.
enum CommandBarSystemSettings {
    struct Pane: Equatable {
        let bundleID: String
        let name: String
        /// The words this pane answers to, in the app's language.
        let keywords: String
    }

    /// Where macOS keeps them. A pane that lives anywhere else is not a pane
    /// System Settings would show either.
    private static let extensionsPath = "/System/Library/ExtensionKit/Extensions"

    /// The older preference panes several of them still keep their translated
    /// index words in.
    private static let legacyPanesRoot = URL(fileURLWithPath: "/System/Library/PreferencePanes",
                                             isDirectory: true)

    private static let lock = NSLock()
    private static var cached: (language: AppLanguage, panes: [Pane])?

    /// Every pane, read from disk the first time and reused after. Panes only
    /// change when macOS itself does, so a second scan in one launch would buy
    /// nothing; a change of language rereads, because the words a pane answers
    /// to are the part that is translated.
    static func panes(language: AppLanguage) -> [Pane] {
        if let cached = lock.withLock({ cached }), cached.language == language {
            return cached.panes
        }
        let found = scan(language: language)
        lock.withLock { cached = (language, found) }
        return found
    }

    /// Forgets the scan, for the uninstall path: a switched-off feature holds
    /// nothing in memory.
    static func clearCache() {
        lock.withLock { cached = nil }
    }

    /// The address that opens one pane. It is the same scheme the app already
    /// uses to send people to a specific privacy or notifications page.
    static func url(for bundleID: String) -> URL? {
        URL(string: "x-apple.systempreferences:\(bundleID)")
    }

    private static func scan(language: AppLanguage) -> [Pane] {
        let root = URL(fileURLWithPath: extensionsPath, isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }

        let folder = CommandBarSystemSettingsSupport.resourceFolder(for: language)
        var panes: [Pane] = []
        var seen = Set<String>()
        for url in contents where url.pathExtension == "appex" {
            // The bundle, not the raw plist: macOS resolves display names that
            // the file itself does not carry, and those are the names System
            // Settings shows.
            guard let bundle = Bundle(url: url),
                  let info = bundle.infoDictionary,
                  CommandBarSystemSettingsSupport.isOpenablePane(info: info),
                  let bundleID = bundle.bundleIdentifier,
                  seen.insert(bundleID).inserted
            else { continue }
            let name = CommandBarSystemSettingsSupport.paneName(
                localizedDisplayName: bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
                displayName: info["CFBundleDisplayName"] as? String,
                bundleName: info["CFBundleName"] as? String,
                fileName: url.lastPathComponent)
            var keywords = searchTerms(in: url, folder: folder)
            if keywords.isEmpty,
               let legacy = CommandBarSystemSettingsSupport.legacyPaneName(info: info) {
                keywords = searchTerms(in: legacyPanesRoot.appendingPathComponent(legacy),
                                       folder: folder)
            }
            panes.append(Pane(bundleID: bundleID, name: name, keywords: keywords))
        }
        return panes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The translated index Apple ships beside a pane, in the app's language,
    /// falling back to English. A pane without one simply answers to its name.
    private static func searchTerms(in bundle: URL, folder: String) -> String {
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        for candidate in [folder, "en"] {
            let directory = resources.appendingPathComponent("\(candidate).lproj", isDirectory: true)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }
            for file in files where file.pathExtension == "searchTerms" {
                guard let terms = NSDictionary(contentsOf: file) as? [String: Any] else { continue }
                let words = CommandBarSystemSettingsSupport.keywords(fromSearchTerms: terms)
                if !words.isEmpty { return words }
            }
        }
        return ""
    }
}
