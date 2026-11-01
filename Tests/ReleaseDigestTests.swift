// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The post-update window's content: which versions an update covers, how
/// each changelog entry is sorted, and which features each one is about.
enum ReleaseDigestTests {
    static func run(_ suite: TestSuite) {
        checkSectionKinds(suite)
        checkSettingsPaths(suite)
        checkVersionRanges(suite)
        checkDigest(suite)
        checkClassifier(suite)
        checkPending(suite)
        checkNewFeatures(suite)
        checkSections(suite)
        checkRealChangelog(suite)
    }

    /// The repository's own CHANGELOG.md, as the next releases will ship it:
    /// entries the window can read, and every recent update turning into a
    /// window that keeps each entry once.
    private static func checkRealChangelog(_ suite: TestSuite) {
        guard let changelog = try? String(contentsOfFile: "CHANGELOG.md", encoding: .utf8) else {
            suite.expect(false, "CHANGELOG.md is readable from the repository root")
            return
        }
        let listed = ReleaseNotes.allVersions(changelog: changelog)
        suite.expect(listed.count > 12, "the changelog lists its releases")
        for version in ["Unreleased"] + listed.prefix(6) {
            for line in ReleaseNotes.rawNotes(for: version, changelog: changelog).components(separatedBy: .newlines)
            where line.hasPrefix("* ") || line.hasPrefix("+ ") || line.hasPrefix("#### ") {
                suite.expect(false, "\(version) writes entries as \"- \" under \"### \" headings: \(line.prefix(60))")
            }
        }
        let recent = Array(listed.prefix(13).reversed())
        for (from, to) in zip(recent, recent.dropFirst()) {
            let digest = ReleaseDigest.make(from: from, to: to, changelog: changelog)
            suite.expect(!digest.changes.isEmpty, "the update \(from) → \(to) has entries for What's New")
            let sections = WhatsNewSupport.sections(
                digest: digest, newFeatures: [], sidebarItems: [], isAvailable: { _ in true },
                title: { $0.rawValue }, generalTitle: "General")
            suite.expect(Set(sections.rows.flatMap(\.changes)) == Set(digest.changes),
                         "every entry of \(from) → \(to) lands in a row")
            suite.expect(sections.rows.allSatisfy { Set($0.changes).count == $0.changes.count },
                         "no row of \(from) → \(to) lists an entry twice")
        }
    }

    private static func checkSectionKinds(_ suite: TestSuite) {
        let expected: [(String, ReleaseChangeKind?)] = [
            ("Added", .new), ("Added (switcher)", .new), ("Highlights", .new), ("Highlight", .new),
            ("Feature highlights", .new), ("Changed", .changed), ("Performance", .changed),
            ("Removed", .changed), ("Dynamic Island", .changed), ("Migration", .changed),
            ("Fixed", .fixed), ("Hotfix", .fixed), ("Safety and reliability", .fixed),
            ("Summary", nil), ("Contributors", nil), ("Docs", nil), ("Details", nil),
            ("Everything from 3.3.3", nil), ("Website", nil),
        ]
        for (title, kind) in expected {
            suite.expect(ReleaseChangeKind(section: title) == kind, "section \(title) reads as \(String(describing: kind))")
        }
    }

    private static func checkSettingsPaths(_ suite: TestSuite) {
        let split = ReleaseChange.splitSettingsPath(
            "Dynamic Island can show the keyboard input source. Settings → Dynamic Island → Activity → Indicators.")
        suite.expect(split.text == "Dynamic Island can show the keyboard input source."
                        && split.settingsPath == "Settings → Dynamic Island → Activity → Indicators",
                     "a closing Settings path moves to its own line")
        let inline = "Clipboard history's filter now starts off. It can be enabled in Settings → Clipboard."
        suite.expect(ReleaseChange.splitSettingsPath(inline).settingsPath == nil,
                     "a path inside a sentence stays in the sentence")
        let alone = "Settings → Features no longer jumps."
        suite.expect(ReleaseChange.splitSettingsPath(alone).text == alone,
                     "an entry that starts with Settings keeps its text")
    }

    private static func checkVersionRanges(_ suite: TestSuite) {
        let listed = ["3.4.2-beta.1", "3.4.1", "3.4.1-beta.5", "3.4.1-beta.3", "3.4.1-beta.2", "3.4.1-beta.1",
                      "3.4.0", "3.4.0-beta.7", "3.4.0-beta.2.1", "3.3.5", "3.3.4"]
        let cases: [(String, String, [String])] = [
            ("3.4.0", "3.4.1", ["3.4.1"]),
            ("3.3.4", "3.4.1", ["3.4.1", "3.4.0", "3.3.5"]),
            ("3.4.1-beta.5", "3.4.1", ["3.4.1"]),
            ("3.4.0-beta.7", "3.4.1-beta.1", ["3.4.1-beta.1"]),
            ("3.4.0", "3.4.1-beta.3", ["3.4.1-beta.3", "3.4.1-beta.2", "3.4.1-beta.1"]),
            ("3.4.1-beta.3", "3.4.2-beta.1", ["3.4.2-beta.1", "3.4.1-beta.5"]),
            ("3.4.1-beta.5", "3.4.2-beta.1", ["3.4.2-beta.1"]),
            ("3.4.0", "3.4.2-beta.1", ["3.4.2-beta.1", "3.4.1-beta.5", "3.4.1-beta.3", "3.4.1-beta.2",
                                       "3.4.1-beta.1"]),
            ("3.4.1", "3.4.1", []), ("3.4.1", "3.4.0", []), ("dev", "3.4.1", []), ("3.4.0", "dev", []),
            ("Unreleased", "3.4.1", []),
        ]
        for (from, to, expected) in cases {
            let versions = ReleaseDigest.versions(from: from, to: to, among: listed)
            suite.expect(versions == expected, "\(from) → \(to) covers \(expected), got \(versions)")
        }
        let many = (0..<30).map { "2.\($0).0" }
        suite.expect(ReleaseDigest.versions(from: "1.0.0", to: "2.29.0", among: many)
                        == (20..<30).reversed().map { "2.\($0).0" },
                     "a long gap keeps the newest versions only")
    }

    /// Laid out like the real file: a highlights list that restates the
    /// release's own entries, a hotfix that repeats an entry word for word,
    /// and a stable release that restates an older one after "Everything from".
    private static let changelog = """
    # Changelog

    ## [Unreleased]

    ### Added
    - Port Manager lists listening ports.

    ## [3.4.2] - 2026-10-20

    ### Summary
    The window switcher wraps rows.

    ### Highlights
    - Rows wrap in the window switcher.

    ### Added
    - The window switcher can limit how many items sit in a row. Settings → Window switcher → Options → Maximum columns.

    ### Fixed
    - Settings → Features no longer jumps when a feature is installed.
    - Lyrics lookup handles differences in titles.
    - The menu bar panel lists tools one line each, and Keep Awake starts with one click.

    ### Contributors
    Thanks to @someone.

    ## [3.4.1] - 2026-10-08

    ### Summary
    Dynamic Island floats as a capsule.

    ### Dynamic Island
    - Calendar adds countdowns to the events you choose.
    - A companion can carry the Command Bar out of the island.

    ### Fixed
    - Lyrics lookup handles differences in titles.

    ### Everything from 3.4.0
    This release brings together 3.4.0.

    ### Fixed
    - Volume mixer sliders follow perceived loudness.

    ## [3.4.0] - 2026-09-27

    ### Fixed
    - Volume mixer sliders follow perceived loudness.
    """

    private static func checkDigest(_ suite: TestSuite) {
        let digest = ReleaseDigest.make(from: "3.4.0", to: "3.4.2", changelog: changelog)
        suite.expect(digest.versions == ["3.4.2", "3.4.1"], "the digest covers the versions after the previous one")
        suite.expect(digest.summary == "The window switcher wraps rows.", "the newest summary leads")
        suite.expect(digest.changes.map(\.version) == ["3.4.2", "3.4.2", "3.4.2", "3.4.2", "3.4.1", "3.4.1"],
                     "credits, restated highlights, repeated entries and restated releases are left out")
        suite.expect(digest.changes.map(\.kind) == [.new, .fixed, .fixed, .fixed, .changed, .changed],
                     "each entry keeps its section's kind")
        suite.expect(digest.changes.map(\.features)
                        == [[.switcher], [], [.notchLyrics], [.keepAwake], [.notch, .notchCalendar], [.notch, .notchMascot]],
                     "entries are sorted into their features, app-wide ones into none")
        suite.expect(digest.changes.map(\.isAppWide) == [false, true, false, true, false, false],
                     "an entry that also changes the menu bar panel concerns everyone")
        let preview = ReleaseDigest.make(from: "3.4.2", to: "3.4.2", changelog: changelog, includeUnreleased: true)
        suite.expect(preview.versions == ["Unreleased"] && preview.changes.first?.features == [.portManager],
                     "the Developer preview reads the unreleased notes")
        suite.expect(ReleaseDigest.make(from: nil, to: "3.4.2", changelog: changelog).changes.isEmpty,
                     "an unknown previous version covers nothing")
        let highlightsOnly = """
        ## [2.0.0] - 2026-01-02

        ### Highlights
        - Command Bar remembers your choices.

        ### Fixed
        - Cleaner keeps preferences.

        ## [1.0.0] - 2026-01-01
        """
        let kept = ReleaseDigest.make(from: "1.0.0", to: "2.0.0", changelog: highlightsOnly)
        suite.expect(kept.changes.map(\.kind) == [.new, .fixed] && kept.changes.map(\.features) == [[.commandBar], [.cleaner]],
                     "highlights with no other list of additions are the release's news")
    }

    private static func checkClassifier(_ suite: TestSuite) {
        // Real entries from the 3.4.x notes.
        let cases: [(String, String, [AppFeature])] = [
            ("Added", "The window switcher can limit how many items sit in a row and wraps the rest. Settings → Window switcher → Options → Maximum columns.", [.switcher]),
            ("Fixed", "Dock clicks and Dock Preview act on the right instance when an app runs as several processes.", [.dockPreview, .dockClick]),
            ("Fixed", "Settings → Features no longer jumps or goes blank when a feature is installed or removed while scrolled down.", []),
            ("Fixed", "AI Agents follows OpenCode 2, including databases upgraded from OpenCode 1 and the cost of compactions.", [.notchAgents]),
            ("Changed", "App sliders in the Volume mixer follow perceived loudness, so 50% sounds clearly quieter. Saved levels keep how loud each app plays.", [.mixer]),
            ("Changed", "Command Bar opens and searches faster, with the same matching and ranking rules.", [.commandBar]),
            ("Changed", "Save as GIF and Copy as GIF work for recordings of any length.", [.screenRecorder]),
            ("Fixed", "Mouse navigation handles quick changes between Back and Forward when the app's menu state has not caught up.", [.mouseNavigation]),
            ("Fixed", "Watch reads the complete percentage, including values above 999%, spaces between thousands and negative signs.", [.notchWatch]),
            ("Dynamic Island", "Calendar adds countdowns to the events you choose, the time left in the current event, week numbers and a choice of calendars.", [.notch, .notchCalendar]),
            ("Fixed", "Uninstalling the last copy of an app clears its Command Bar shortcuts, aliases, pins and hidden entries.", [.commandBar]),
            ("Fixed", "Brightness keys keep their press and release together when displays reconnect or the pointer changes displays.", [.brightness]),
        ]
        for (section, text, expected) in cases {
            let found = ReleaseChangeAliases.features(inBullet: text, section: section)
            suite.expect(found == expected, "\"\(text.prefix(48))…\" is about \(expected), got \(found)")
        }
        suite.expect(ReleaseChangeAliases.features(inBullet: "Downloads keep a calendar of timers.", section: "Fixed").isEmpty,
                     "common words name an island extension only in an island context")
        suite.expect(ReleaseChangeAliases.features(inBullet: "You can watch the wheel notch turn.", section: "Fixed").isEmpty,
                     "plain words and ignored phrases are not features")
        suite.expect(ReleaseChangeAliases.features(
                        inBullet: "A companion rests beside the camera and can carry the Command Bar out of the island.",
                        section: "Dynamic Island") == [.notch, .notchMascot],
                     "tools named as part of the island are not what changed")
        suite.expect(ReleaseChangeAliases.mentionsAppWide("The menu bar panel lists tools one line each.")
                        && !ReleaseChangeAliases.mentionsAppWide("The menu bar battery icon shows the time left."),
                     "only parts every person has make an entry app-wide")
        for feature in AppFeature.allCases {
            suite.expect(!ReleaseChangeAliases.aliases(for: feature).isEmpty, "\(feature.rawValue) has a name to match")
        }
    }

    private static func checkPending(_ suite: TestSuite) {
        let cases: [(String, String?, String?, String?, String?)] = [
            ("3.4.1", "3.4.0", nil, nil, "3.4.0"),
            ("3.4.1", nil, nil, nil, nil),
            ("3.4.1", "dev", nil, nil, nil),
            ("3.4.1", "3.4.1", nil, nil, nil),
            ("3.4.0", "3.4.1", nil, nil, nil),
            ("3.4.2", "3.4.1", nil, "3.4.0", "3.4.0"),
            ("3.4.0", "3.4.1", nil, "3.4.0", nil),
            ("3.4.2", "3.3.5", "3.4.1", nil, "3.4.1"),
            ("3.4.1", "3.3.5", "3.4.1", nil, nil),
            ("dev", "3.4.0", nil, nil, nil),
        ]
        for (current, previous, seen, pending, expected) in cases {
            suite.expect(WhatsNewInfo.pendingVersion(current: current, previous: previous, seen: seen, pending: pending)
                            == expected,
                         "pending for \(current) from \(previous ?? "nil"), seen \(seen ?? "nil"), waiting \(pending ?? "nil")")
        }
    }

    private static func checkNewFeatures(_ suite: TestSuite) {
        let names = Set(AppFeature.allCases.map(\.rawValue))
        suite.expect(WhatsNewInfo.featuresBeforeTracking.isSubset(of: names),
                     "the frozen list names only real features")
        suite.expect(WhatsNewInfo.newFeatures(known: WhatsNewInfo.knownFeaturesValue, isSupported: { _ in true }).isEmpty,
                     "a recorded list of every feature leaves nothing new")
        let known = AppFeature.allCases.filter { $0 != .portManager && $0 != .fanControl }.map(\.rawValue)
            .joined(separator: ",")
        suite.expect(WhatsNewInfo.newFeatures(known: known, isSupported: { $0 != .fanControl }) == [.portManager],
                     "features missing from the record are new unless this Mac cannot run them")
        let untracked = AppFeature.allCases.filter { !WhatsNewInfo.featuresBeforeTracking.contains($0.rawValue) }
        suite.expect(WhatsNewInfo.newFeatures(known: nil, isSupported: { _ in true }) == untracked,
                     "without a record, features added after tracking began are new")
    }

    private static func checkSections(_ suite: TestSuite) {
        func item(_ id: SettingsSidebarItem.ID, _ title: String) -> SettingsSidebarItem {
            let destination: FeatureSettingsDestination
            switch id {
            case .feature(let feature): destination = feature.settingsDestination
            case .page(let page): destination = FeatureSettingsDestination(page)
            case .setting(let anchor): destination = FeatureSettingsDestination(anchor.page, sectionAnchor: anchor)
            }
            return SettingsSidebarItem(id: id, destination: destination, title: title, icon: "circle")
        }
        let items = [item(.page(.general), "General"), item(.page(.features), "Features"),
                     item(.page(.notch), "Dynamic Island"), item(.page(.monitor), "System Monitor"),
                     item(.feature(.switcher), "Window switcher"), item(.feature(.mixer), "Volume mixer")]
        func change(_ text: String, _ kind: ReleaseChangeKind, _ features: [AppFeature]) -> ReleaseChange {
            ReleaseChange(text: text, kind: kind, version: "3.4.2", features: features)
        }
        let switcher = change("switcher", .new, [.switcher])
        let lyrics = change("lyrics", .fixed, [.notchLyrics])
        let island = change("island", .changed, [.notch, .notchCalendar])
        let general = change("general", .fixed, [])
        let gpu = change("gpu", .fixed, [.monitorGPU])
        let fans = change("fans", .fixed, [.fanControl])
        let ports = change("ports", .new, [.portManager, .switcher])
        let installer = change("installer", .fixed, [.diskImageInstaller])
        var panel = change("panel", .changed, [.keepAwake])
        panel.alsoAppWide = true
        let digest = ReleaseDigest(previousVersion: "3.4.1", version: "3.4.2", versions: ["3.4.2"], summary: nil,
                                   changes: [switcher, lyrics, island, general, gpu, fans, ports, installer, panel])
        let installed: Set<AppFeature> = [.switcher, .notch, .notchLyrics, .monitorGPU, .diskImageInstaller]
        let sections = WhatsNewSupport.sections(
            digest: digest, newFeatures: [.portManager], sidebarItems: items,
            isAvailable: { installed.contains($0) }, title: { $0.rawValue }, generalTitle: "General")
        suite.expect(sections.newFeatures.map(\.id) == [.newFeature(.portManager)]
                        && sections.newFeatures.first?.changes == [ports],
                     "new features come first with the entries that name them")
        suite.expect(sections.yourFeatures.map(\.id) == [.settings(.page(.notch)), .settings(.page(.monitor)),
                                                         .settings(.feature(.switcher)),
                                                         .feature(.diskImageInstaller), .general],
                     "installed features follow the Settings order, app-wide changes last")
        suite.expect(sections.yourFeatures.first?.changes == [lyrics, island],
                     "Dynamic Island's row gathers its installed extensions")
        suite.expect(sections.yourFeatures.first { $0.id == .settings(.feature(.switcher)) }?.changes == [switcher, ports],
                     "an entry naming a new feature still shows under the installed one beside it")
        suite.expect(sections.notInstalled.map(\.id)
                        == [.notInstalled(.keepAwake), .notInstalled(.notchCalendar), .notInstalled(.fanControl)],
                     "features this Mac does not have are listed one by one")
        suite.expect(sections.yourFeatures.last?.changes == [general, panel],
                     "an entry about a missing feature that also changes the whole app stays in General")
        suite.expect(sections.hasContentForYou && sections.changesForYou.count == 8,
                     "the overview counts each entry for this Mac once")
        let withoutIsland = WhatsNewSupport.sections(
            digest: ReleaseDigest(previousVersion: "3.4.1", version: "3.4.2", versions: ["3.4.2"], summary: nil,
                                  changes: [lyrics]),
            newFeatures: [], sidebarItems: items, isAvailable: { $0 == .notchLyrics }, title: { $0.rawValue },
            generalTitle: "General")
        suite.expect(!withoutIsland.hasContentForYou && withoutIsland.notInstalled.map(\.id) == [.notInstalled(.notchLyrics)],
                     "an island extension left installed without the island is not one of this Mac's features")
        let elsewhere = WhatsNewSupport.sections(
            digest: ReleaseDigest(previousVersion: "3.4.1", version: "3.4.2", versions: ["3.4.2"], summary: nil,
                                  changes: [fans]),
            newFeatures: [], sidebarItems: items, isAvailable: { _ in false }, title: { $0.rawValue },
            generalTitle: "General")
        suite.expect(!elsewhere.hasContentForYou && elsewhere.notInstalled.count == 1,
                     "an update only about missing features has nothing for this Mac")

        suite.expect(WhatsNewSupport.rowID(for: .notchMascot, in: items) == .settings(.page(.notch)),
                     "the companion belongs to the island's row")
        suite.expect(WhatsNewSupport.rowID(for: .soundOutputSwitcher, in: items) == .general,
                     "a tool Settings keeps on its General page joins the General row")
        suite.expect(WhatsNewSupport.representedFeature(of: .page(.notch)) == .notch
                        && WhatsNewSupport.representedFeature(of: .page(.monitor)) == nil
                        && WhatsNewSupport.representedFeature(of: .feature(.mixer)) == .mixer,
                     "a row stands for one feature only when it has one")
        suite.expect(WhatsNewSupport.grouped([gpu, switcher, island]).map(\.kind) == [.new, .changed, .fixed],
                     "a feature's page lists new, then changed, then fixed")
    }
}
