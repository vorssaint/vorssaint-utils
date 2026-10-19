// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production rule mutations and scan completion, with isolated preferences and
/// counters in place of scanning, scheduling and notifications.
enum AppUpdateRulesContract {
    enum UserDefaults {
        static let name = "vorss.tests.app-update-rules.\(UUID().uuidString)"
        static let standard = Foundation.UserDefaults(suiteName: name)!
    }

    struct AppFeature {
        static let appUpdates = AppFeature()
        var isAvailable: Bool { true }
    }

    class State {
        var rules: [AppUpdatesSupport.UpdateRule] = []
        var allItems: [AppUpdatesSupport.Item] = []
        var items: [AppUpdatesSupport.Item] = []
        var selection: Set<String> = []
        var knownIDs: Set<String> = []
        var isChecking = false
        var sourceRefreshPending = false
        var automaticCheckPending = false
        var packageManagerAvailable = true
        var onlineCatalogAvailable = true
        var appStoreAvailable = true
        var uncheckedAppNames: [String] = []
        var uncomparableAppNames: [String] = []
        var hasCheckedThisSession = false
        var lastCheck: Date?
        var scans = 0
        var notifications = 0
        func check(automatic: Bool = false) { scans += 1 }
        func scheduleNext() {}
        func notifyIfWanted(freshCount: Int, total: Int) -> Bool {
            notifications += freshCount
            return freshCount > 0
        }
    }

    typealias Support = AppUpdatesSupport

    static func item(_ version: String, source: Support.Source = .packageManager,
                     bundleID: String = "com.example.editor") -> Support.Item {
        .init(id: "\(source.rawValue):\(bundleID)", source: source, name: "Editor",
              installedVersion: "2.1.1", latestVersion: version,
              token: source == .packageManager ? "editor" : nil,
              bundlePath: "/Applications/Renamed.app", storePage: nil, bundleID: bundleID)
    }

    static func run(_ suite: TestSuite) {
        defer { UserDefaults.standard.removePersistentDomain(forName: UserDefaults.name) }
        let app = Support.InstalledApp(name: "Editor", bundleID: "com.example.editor",
                                      path: "/Applications/Editor.app", version: "2.1.1", isFromAppStore: false)
        let skip = Support.UpdateRule(bundleID: app.bundleID, name: app.name, version: "v2.1.2")
        let exclude = Support.UpdateRule(bundleID: app.bundleID, name: app.name, version: nil)
        let unrelated = item("2.1.2", bundleID: "com.example.other")
        for source in [Support.Source.packageManager, .appStore, .onlineCatalog] {
            suite.expect(Support.visibleItems([item("2.1.2", source: source)], rules: [skip]).isEmpty,
                         "a version pin follows bundle identity across update sources and app renames")
            suite.expect(Support.visibleItems([item("2.1.3", source: source)], rules: [skip]).count == 1,
                         "skipping 2.1.2 never hides 2.1.3")
            suite.expect(Support.visibleItems([item("2.1.3", source: source)], rules: [exclude]).isEmpty,
                         "app exclusions cover future releases in every source")
        }
        suite.expect(Support.visibleItems([unrelated], rules: [skip, exclude]) == [unrelated],
                     "rules never match another app by display name or version alone")
        suite.expect(Support.visibleItems([item("2.1.2beta"), item("2.1.20")], rules: [skip]).count == 2,
                     "version pins are exact, not prefixes or ranges")
        suite.expect(Support.checkedApps([app], rules: [skip]) == [app],
                     "version-skipped apps are still queried for new releases")
        suite.expect(Support.checkedApps([app], rules: [exclude]).isEmpty,
                     "permanent exclusions leave scan candidates before source lookups")
        let raw = Support.encodedRules([skip])!
        suite.expect(Support.decodedRules(raw) == [skip] && Support.decodedRules("broken").isEmpty,
                     "rules round-trip and corrupt preferences do not hide updates")
        let invalid = [Support.UpdateRule(bundleID: "", name: "Empty", version: nil),
                       Support.UpdateRule(bundleID: app.bundleID, name: app.name, version: ""),
                       Support.UpdateRule(bundleID: app.bundleID, name: app.name, version: "latest")]
        suite.expect(Support.decodedRules(Support.encodedRules(invalid)).isEmpty,
                     "invalid exact versions never become permanent exclusions")
        suite.expect(Support.decodedRules(Support.encodedRules([skip, exclude])).count == 1,
                     "duplicate imported identities produce only one editable rule")

        let backup = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.appUpdatesRules ? raw : nil
        }
        let restored = SettingsBackupSupport.sanitizedSettings(from: backup)
        suite.expect(Support.decodedRules(restored?[DefaultsKey.appUpdatesRules] as? String) == [skip],
                     "version pins travel through real settings backup export and import")
        suite.expect(!SettingsBackupSupport.valueLooksRight(DefaultsKey.appUpdatesRules, 42),
                     "backup refuses wrong-shaped rule preferences")
        let excludedRaw = Support.encodedRules([exclude])!
        let excludedBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.appUpdatesRules ? excludedRaw : nil
        }
        suite.expect(Support.decodedRules(SettingsBackupSupport.sanitizedSettings(from: excludedBackup)?[
            DefaultsKey.appUpdatesRules] as? String) == [exclude], "app exclusions are portable too")

        serviceRules(suite, excludedRaw: excludedRaw)
        pickedExclusions(suite)
        listControls(suite)
        sourceIdentity(suite, app: app)
    }

    /// The add button reads the picked bundle itself, so an app that is up to
    /// date or never matched by a source can still be left out.
    private static func pickedExclusions(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-app-update-rules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func bundle(_ name: String, _ info: [String: Any]) -> URL {
            let url = folder.appendingPathComponent("\(name).app", isDirectory: true)
            let contents = url.appendingPathComponent("Contents", isDirectory: true)
            try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try? data?.write(to: contents.appendingPathComponent("Info.plist"))
            return url
        }
        let other = Support.UpdateRule(bundleID: "com.example.other", name: "Other", version: nil)
        let excluded = Support.UpdateRule(bundleID: "com.example.picked", name: "Picked", version: nil)
        let picked = bundle("Picked", ["CFBundleIdentifier": excluded.bundleID, "CFBundleShortVersionString": "1.0"])
        let service = Service()
        service.addExclusion(appAt: picked)
        suite.expect(service.rules == [excluded], "a picked app bundle becomes an exclusion with its identity and name")

        service.saveRules([Support.UpdateRule(bundleID: excluded.bundleID, name: excluded.name, version: "1.1"), other])
        service.addExclusion(appAt: picked)
        suite.expect(service.rules == [other, excluded], "picking an app with a skipped version turns it into an exclusion")

        let kept = service.rules
        service.addExclusion(appAt: bundle("Anonymous", ["CFBundleShortVersionString": "1.0"]))
        suite.expect(service.rules == kept, "a picked bundle without an identifier adds no rule")
        service.addExclusion(appAt: bundle("Empty", ["CFBundleIdentifier": ""]))
        suite.expect(service.rules == kept, "a picked bundle with an empty identifier adds no rule")
        service.addExclusion(appAt: bundle("Vorssaint", ["CFBundleIdentifier": "com.vorssaint.utils"]))
        suite.expect(service.rules == kept, "Vorssaint's own bundles never become exclusions")
        service.addExclusion(appAt: bundle("Spaced", ["CFBundleIdentifier": "com.example two"]))
        suite.expect(service.rules == kept, "a picked identifier with whitespace that a reload would drop adds no rule")
        service.addExclusion(appAt: bundle("Slashed", ["CFBundleIdentifier": "com.example/two"]))
        suite.expect(service.rules == kept, "a picked identifier with a slash that a reload would drop adds no rule")
        service.addExclusion(appAt: bundle("Blank", ["CFBundleIdentifier": "com.example.blank", "CFBundleDisplayName": " "]))
        suite.expect(service.rules == kept, "a picked app without a usable name adds no rule a reload would drop")
        service.addExclusion(appAt: folder.appendingPathComponent("Missing.app", isDirectory: true))
        suite.expect(service.rules == kept, "a picked path without a bundle adds no rule")

        service.isChecking = true
        service.addExclusion(appAt: bundle("Later", ["CFBundleIdentifier": "com.example.later"]))
        suite.expect(service.rules == kept, "picking an app cannot race an active scan")
        service.isChecking = false
        service.addExclusion(appAt: bundle("Later", ["CFBundleIdentifier": "com.example.later"]))
        suite.expect(service.rules.last?.bundleID == "com.example.later" && service.rules.count == 3,
                     "the same pick is saved once the scan is over")
        suite.expect(Support.decodedRules(UserDefaults.standard.string(forKey: DefaultsKey.appUpdatesRules)) == service.rules,
                     "picked exclusions are saved in the restorable rule preference")
        UserDefaults.standard.removeObject(forKey: DefaultsKey.appUpdatesRules)
    }

    private static func listControls(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/UI/AppUpdates/AppUpdatesListView.swift",
                                  encoding: .utf8)) ?? ""
        suite.expect(source.contains("guard !inNotch else {")
                     && source.contains("guard panel.runAboveIsland() == .OK, let url = panel.url else { return }"),
                     "inside the island the app picker opens above it instead of below it")
        suite.expect(source.contains(".help(moreOptions)")
                     && source.contains(".accessibilityLabel(\"\\(moreOptions): \\(item.name)\")")
                     && !source.contains(".help(text.excludeApp)"),
                     "the row menu is named for both rule actions and says which app it belongs to")
        suite.expect(source.contains("private var coveragePartial: Bool { coverageIncomplete || versionsUncompared }")
                     && source.contains("Label(coveragePartial ? text.partialUpToDate")
                     && source.contains("if versionsUncompared {")
                     && source.contains("Text(updates.uncomparableAppNames.joined(separator: \", \"))"),
                     "apps named as not compared get their own note and keep an empty list from reading as current")

        // Settings hosts the full list and the menu bar panel the compact one,
        // whose rows have no width to spare for the visible menu.
        let settings = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Settings/AppUpdatesSettings.swift",
                                    encoding: .utf8)) ?? ""
        let panel = (try? String(contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/PanelAppUpdatesView.swift",
                                 encoding: .utf8)) ?? ""
        let row = (source.components(separatedBy: "private func row(_ item: AppUpdatesSupport.Item) -> some View {")
            .dropFirst().first ?? "").components(separatedBy: "private func ruleActions(").first ?? ""
        let glyph = "Image(systemName: \"ellipsis.circle\")"
        let gated = row.components(separatedBy: "if !compact, item.bundleID != nil {")
        suite.expect(source.contains("var compact = false")
                     && settings.contains("AppUpdatesListView()") && panel.contains("AppUpdatesListView(compact: true)")
                     && gated.count == 2 && !gated[0].contains(glyph) && gated[1].contains(glyph)
                     && row.contains(".contextMenu { ruleActions(for: item) }"),
                     "Settings rows show the menu button and panel rows keep only the context menu with the same actions")
        // A borderless popup draws its label through AppKit, which ignores a
        // foreground style there; only the menu's tint greys the glyph.
        let label = (row.components(separatedBy: glyph).dropFirst().first ?? "")
            .components(separatedBy: ".menuStyle(").first ?? ""
        let menuChain = (row.components(separatedBy: ".menuStyle(.borderlessButton)").dropFirst().first ?? "")
            .components(separatedBy: ".help(moreOptions)").first ?? ""
        suite.expect(menuChain.contains(".tint(.secondary)") && !label.contains(".foregroundStyle("),
                     "the row menu glyph is secondary like the other small row and header icons")
    }

    private static func serviceRules(_ suite: TestSuite, excludedRaw: String) {
        let current = item("2.1.2")
        let next = item("2.1.3")
        let unrelated = item("2.1.2", bundleID: "com.example.other")
        let service = Service()
        func finish(_ items: [Support.Item], automatic: Bool = false, uncomparable: [String] = []) {
            service.isChecking = true
            service.finishCheck(items: items, packageManagerAvailable: true,
                                onlineCatalogAvailable: true, appStoreAvailable: true,
                                uncheckedAppNames: [], uncomparableAppNames: uncomparable,
                                automatic: automatic)
        }
        finish([], automatic: true, uncomparable: ["Unified Remote"])
        suite.expect(service.uncomparableAppNames == ["Unified Remote"] && service.items.isEmpty
                     && service.notifications == 0 && service.onlineCatalogAvailable
                     && UserDefaults.standard.integer(forKey: DefaultsKey.appUpdatesLastCount) == 0,
                     "an app whose version cannot be compared is named without a row, a count or a notice")
        finish([current, unrelated])
        suite.expect(service.uncomparableAppNames.isEmpty, "the next scan replaces the named apps")
        service.skipVersion(current)
        suite.expect(service.items == [unrelated] && service.selection == [unrelated.id],
                     "skip removes the row and its bulk-update selection immediately")
        suite.expect(UserDefaults.standard.integer(forKey: DefaultsKey.appUpdatesLastCount) == 1,
                     "summary counts visible updates only")
        let reloaded = Service()
        reloaded.reloadRules()
        suite.expect(reloaded.rules == service.rules, "new service restores the saved choice")
        finish([current, unrelated], automatic: true)
        suite.expect(service.notifications == 1 && service.items == [unrelated],
                     "scan completion and notifications exclude the skipped release")
        service.removeRule(service.rules[0])
        suite.expect(service.items == [current, unrelated] && service.scans == 0,
                     "removing a version rule restores cached results without any scan")
        service.skipVersion(current)
        finish([next], automatic: true)
        suite.expect(service.items == [next] && service.selection == [next.id] && service.notifications == 2,
                     "the next release returns selected and can notify normally")
        service.skipVersion(next)
        suite.expect(service.rules.count == 1 && service.rules[0].version == "2.1.3",
                     "a new skip replaces the previous pin for that app")
        service.removeRule(service.rules[0])
        service.excludeApp(next)
        suite.expect(service.items.isEmpty && service.selection.isEmpty, "exclusion removes the visible app")
        finish([])
        service.removeRule(service.rules[0])
        suite.expect(service.rules.isEmpty && service.items.isEmpty && !service.hasCheckedThisSession
                     && service.scans == 0, "removing an exclusion neither fabricates a current result nor scans everything")
        finish([next])
        suite.expect(service.items == [next], "the next explicit scan includes the restored app")
        service.isChecking = true
        service.skipVersion(next)
        suite.expect(service.rules.isEmpty, "rule actions cannot race an active scan")
        UserDefaults.standard.set(excludedRaw, forKey: DefaultsKey.appUpdatesRules)
        service.reloadRules()
        suite.expect(service.items.isEmpty && service.sourceRefreshPending,
                     "settings restore invalidates an in-flight scan using older candidate rules")
        finish([next])
        suite.expect(service.scans == 1 && service.items.isEmpty, "obsolete scan is discarded after settings restore")
        UserDefaults.standard.removeObject(forKey: DefaultsKey.appUpdatesRules)
        service.reloadRules()
        suite.expect(service.rules.isEmpty, "settings reset also removes rules from the live service")

    }

    private static func sourceIdentity(_ suite: TestSuite, app: Support.InstalledApp) {
        let entry = Support.StoreEntry(bundleID: app.bundleID, version: "2.1.2", minimumOSVersion: nil, page: nil)
        suite.expect(Support.appStoreUpdates(apps: [app], storeVersions: [app.bundleID: entry],
                     operatingSystemVersion: "15.0").first?.bundleID == app.bundleID,
                     "store findings preserve portable app identity")
        let catalog = Support.CatalogEntry(token: "editor", version: "2.1.2", appNames: ["Editor.app"],
            bundleIDs: [app.bundleID], minimumOSVersions: [], exactOSVersions: [], hasUnsupportedOSConstraint: false)
        suite.expect(Support.onlineCatalogFindings(apps: [app], catalog: [catalog],
                     operatingSystemVersion: "15.0").items.first?.bundleID == app.bundleID,
                     "catalog findings preserve portable app identity")
        let release = AppUpdateFeedSupport.releases(data: Data("version: 2.1.2\npath: app.zip\n".utf8), format: .manifest)!
        suite.expect(AppUpdateFeedSupport.update(app: app, releases: release, format: .manifest,
                     operatingSystemVersion: "15.0", kernelVersion: "24.0", architecture: "arm64")?.bundleID == app.bundleID,
                     "publisher findings preserve portable app identity")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.appUpdates(language)
            suite.expect([text.skipVersionFormat, text.excludeApp, text.rulesTitle, text.addException, text.skippedVersionFormat,
                          text.excludedApp, text.removeRule, text.rulesHint, text.noVisibleUpdates,
                          FeatureStrings.mouseClickDebounce(language).moreOptions].allSatisfy { !$0.isEmpty },
                         "update rule controls are localized for \(language)")
            suite.expect(!text.uncomparableVersions.isEmpty && !text.uncomparableVersionsNote.isEmpty
                         && (language == .enUS || text.uncomparableVersionsNote != AppUpdateStrings.enUS.uncomparableVersionsNote),
                         "the note for versions that cannot be compared is translated for \(language)")
            suite.expect(text.skipVersionFormat.contains("%@") && text.skippedVersionFormat.contains("%@"),
                         "localized skip actions identify the exact release")
        }
    }
}
