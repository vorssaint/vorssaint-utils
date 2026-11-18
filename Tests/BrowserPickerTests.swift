// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SQLite3

enum BrowserPickerTests {
    static func run(_ suite: TestSuite) {
        matching(suite)
        typedInput(suite)
        routing(suite)
        storage(suite)
        drafts(suite)
        chromiumProfiles(suite)
        firefoxProfiles(suite)
        backup(suite)
    }

    private static let arc = BrowserPickerTarget.application(bundleID: "company.thebrowser.Browser")
    private static let work = BrowserPickerTarget.profile(bundleID: "com.google.Chrome", id: "Profile 2", name: "Work")

    private static func url(_ text: String) -> URL { URL(string: text)! }

    private static func matched(_ link: String, _ rules: [BrowserPickerRule]) -> BrowserPickerTarget? {
        BrowserPickerRules.firstMatch(for: url(link), in: rules)?.target
    }

    private static func matching(_ suite: TestSuite) {
        let github = [BrowserPickerRule(site: "github.com", target: work)]
        suite.expect(matched("https://github.com/x", github) == work
                && matched("https://www.github.com/", github) == work
                && matched("http://gist.eu.github.com/a?b=1#c", github) == work,
            "a site rule covers the site and its subdomains on http and https")
        suite.expect(matched("https://notgithub.com/", github) == nil
                && matched("https://github.com.evil.test/", github) == nil,
            "a site rule never covers a lookalike host")
        suite.expect(matched("https://GitHub.COM./x", github) == work,
            "host case and a trailing dot do not matter")
        suite.expect(matched("mailto:a@github.com", github) == nil
                && matched("file:///github.com", github) == nil,
            "only web links are routed")

        let team = [BrowserPickerRule(site: "github.com", path: "/team", target: work)]
        suite.expect(matched("https://github.com/team", team) == work
                && matched("https://github.com/team/repo?x=1", team) == work,
            "a path rule covers the path and the pages below it")
        suite.expect(matched("https://github.com/teams", team) == nil
                && matched("https://github.com/Team", team) == nil
                && matched("https://github.com/", team) == nil,
            "a path rule stops at the path's own boundary, and paths are case-sensitive")
        let slash = [BrowserPickerRule(site: "github.com", path: "/team/", target: work)]
        suite.expect(matched("https://github.com/team", slash) == work,
            "a trailing slash in the rule's path still covers the path itself")

        let ordered = [
            BrowserPickerRule(site: "github.com", path: "/team", target: work, isEnabled: false),
            BrowserPickerRule(site: "github.com", target: arc),
            BrowserPickerRule(site: "github.com", path: "/team", target: work),
        ]
        suite.expect(matched("https://github.com/team/x", ordered) == arc,
            "the first enabled rule that matches wins, and a switched-off rule is skipped")

        let idn = BrowserPickerRules.normalizedSite("bücher.de").map {
            [BrowserPickerRule(site: $0.site, target: arc)]
        } ?? []
        suite.expect(matched("https://xn--bcher-kva.de/a", idn) == arc
                && matched("https://bücher.de/a", idn) == arc,
            "an international site matches its links in either spelling")
    }

    private static func typedInput(_ suite: TestSuite) {
        let site = { (text: String) in BrowserPickerRules.normalizedSite(text).map { "\($0.site)|\($0.path)" } }
        suite.expect(site("GitHub.com") == "github.com|"
                && site("  https://github.com/team  ") == "github.com|/team"
                && site("*.example.com") == "example.com|"
                && site("localhost") == "localhost|",
            "a typed site may carry a scheme, a path or a wildcard")
        suite.expect(site("") == nil && site("not a site") == nil && site("intranet") == nil,
            "text that names no site is rejected")
        suite.expect(BrowserPickerRules.normalizedPath("team") == "/team"
                && BrowserPickerRules.normalizedPath("/my docs") == "/my%20docs"
                && BrowserPickerRules.normalizedPath("/my%20docs") == "/my%20docs"
                && BrowserPickerRules.normalizedPath(" / ") == "",
            "a typed path is stored the way links carry it")
        suite.expect(BrowserPickerRules.suggestedSite(for: url("https://www.figma.com/file/x")) == "figma.com"
                && BrowserPickerRules.suggestedSite(for: url("https://docs.example.test/a")) == "docs.example.test",
            "a rule made from a link covers its site without the www prefix")
    }

    private static func routing(_ suite: TestSuite) {
        let rules = [BrowserPickerRule(site: "github.com", target: work),
                     BrowserPickerRule(site: "github.com", target: arc)]
        let link = url("https://github.com/x")
        suite.expect(BrowserPickerRoute.of(link, rules: rules, isInstalled: { _ in true }) == .open(work),
            "a matching rule opens its target without asking")
        suite.expect(BrowserPickerRoute.of(url("https://example.com"), rules: rules, isInstalled: { _ in true })
                == .ask(missing: nil),
            "a link no rule covers shows the picker")
        suite.expect(BrowserPickerRoute.of(link, rules: rules, isInstalled: { $0 != work }) == .ask(missing: work),
            "a rule whose target is gone asks instead of falling through to a lower rule")

        let personal = BrowserPickerTarget.profile(bundleID: "com.google.Chrome", id: "Default", name: "Me")
        suite.expect(!BrowserPickerRules.isAvailable(work, appInstalled: true, knownProfiles: ["com.google.Chrome": ["Default"]])
                && BrowserPickerRules.isAvailable(personal, appInstalled: true, knownProfiles: ["com.google.Chrome": ["Default"]])
                && BrowserPickerRules.isAvailable(work, appInstalled: true, knownProfiles: [:])
                && !BrowserPickerRules.isAvailable(arc, appInstalled: false, knownProfiles: [:]),
            "a removed profile is gone even when its browser has one profile left; an unread list is not held against it")

        let teamLink = url("https://www.github.com/team/x")
        let parent = BrowserPickerRule(site: "github.com", target: work)
        let other = BrowserPickerRule(site: "figma.com", target: arc)
        let added = BrowserPickerRules.remembering(arc, for: url("https://docs.github.com/x"), in: [other, parent])
        suite.expect(added.count == 3 && added[1].site == "docs.github.com" && added[1].target == arc && added[2] == parent,
            "⌥ adds the remembered site above the rule that sent the link to a missing target")
        var off = BrowserPickerRule(site: "github.com", target: work)
        off.isEnabled = false
        let pathRule = BrowserPickerRule(site: "github.com", path: "/team", target: work)
        let repointed = BrowserPickerRules.remembering(arc, for: teamLink, in: [pathRule, off])
        suite.expect(repointed.count == 2 && repointed[0].id == off.id && repointed[0].target == arc
                && repointed[0].isEnabled && repointed[1] == pathRule,
            "⌥ repoints and switches on the existing rule for the site, moving it above the rule that matched")
        suite.expect(BrowserPickerRules.remembering(arc, for: url("https://example.com/"), in: []).map(\.site) == ["example.com"],
            "⌥ with no rules adds one for the site")
    }

    private static func storage(_ suite: TestSuite) {
        let rules = [BrowserPickerRule(site: "github.com", path: "/team", target: work, isEnabled: false),
                     BrowserPickerRule(site: "figma.com", target: arc)]
        suite.expect(BrowserPickerRules.decode(BrowserPickerRules.encode(rules)) == rules,
            "saved rules come back in order with their targets and switches")
        suite.expect(BrowserPickerRules.decode(nil).isEmpty
                && BrowserPickerRules.decode(Data("{".utf8)).isEmpty
                && BrowserPickerRules.decode(Data(#"{"version":2,"rules":[]}"#.utf8)).isEmpty,
            "missing, damaged or newer data reads as no rules")
    }

    private static func drafts(_ suite: TestSuite) {
        var draft = BrowserPickerRuleDraft(site: "https://GitHub.com/team", path: "", target: work)
        suite.expect(draft.rule.map { "\($0.site)|\($0.path)" } == "github.com|/team",
            "a path pasted with the site is kept when the path field is empty")
        draft.path = "docs"
        suite.expect(draft.rule?.path == "/docs", "the path field wins over a path in the site field")
        draft.target = nil
        suite.expect(draft.rule == nil, "a rule needs a target")

        let saved = BrowserPickerRule(site: "figma.com", path: "/my%20files", target: arc, isEnabled: false)
        let edited = BrowserPickerRuleDraft(saved)
        suite.expect(edited.path == "/my files" && edited.rule == saved,
            "editing an untouched rule keeps its identity, path and switch")
    }

    private static func chromiumProfiles(_ suite: TestSuite) {
        let localState = Data(#"""
        {"profile": {"profiles_order": ["Profile 2", "Default"],
          "info_cache": {"Default": {"name": "Personal"}, "Profile 2": {"name": "Work"},
                         "Profile 3": {"name": "Archive"}, "../evil": {"name": "Escape"},
                         "-flag": {"name": "Flag"}, "Profile 4": {"name": " "}, "Profile 5": {}}}}
        """#.utf8)
        let profiles = BrowserPickerBrowsers.profiles(fromLocalState: localState)
        let directories: [String] = profiles.map(\.directory)
        let names: [String] = profiles.map(\.name)
        suite.expect(directories == ["Profile 2", "Default", "Profile 3"] && names == ["Work", "Personal", "Archive"],
            "profiles follow the browser's own order, then by name, and unsafe or unnamed entries are skipped")
        suite.expect(BrowserPickerBrowsers.profiles(fromLocalState: Data("not json".utf8)).isEmpty
                && BrowserPickerBrowsers.profiles(fromLocalState: Data(#"{"profile":{}}"#.utf8)).isEmpty,
            "an unreadable Local State lists no profiles")
        let folder = URL(fileURLWithPath: "/Users/me/Library/Application Support/Firefox", isDirectory: true)
        let chromium: [String]? = BrowserPickerBrowsers.profileArguments(kind: .chromium, id: "Profile 2", in: folder,
                                                                         url: url("https://a.test/x?y=1"))
        let escaping: [String]? = BrowserPickerBrowsers.profileArguments(kind: .chromium, id: "../Profile 2", in: folder,
                                                                         url: url("https://a.test/"))
        let expectedChromium: [String] = ["--profile-directory=Profile 2", "https://a.test/x?y=1"]
        suite.expect(chromium == expectedChromium && escaping == nil,
            "a Chromium profile opens with its folder and the untouched link as separate arguments")
        let firefoxArguments: [String]? = BrowserPickerBrowsers.profileArguments(kind: .firefox, id: "Profiles/ab12.work",
                                                                                 in: folder, url: url("https://a.test/x?y=1"))
        let expectedFirefox: [String] = ["--profile", folder.path + "/Profiles/ab12.work", "-new-tab", "https://a.test/x?y=1"]
        suite.expect(firefoxArguments == expectedFirefox,
            "a Firefox profile opens the way Firefox's own profile manager opens one")
        let firefox = URL(fileURLWithPath: "/Applications/Firefox.app")
        let terminal = URL(fileURLWithPath: "/Applications/Terminal Plus.app")
        let testing = URL(fileURLWithPath: "/Users/me/.cache/browsers/Chrome for Testing.app")
        let web: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["http", "https"]]]]
        let fallback: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLSchemes": ["https"], "LSHandlerRank": "Alternate"]]]
        let viewers: Set<URL> = [firefox, terminal, testing]
        suite.expect(BrowserPickerBrowsers.isBrowser(at: firefox, info: web, htmlViewers: viewers)
                && !BrowserPickerBrowsers.isBrowser(at: firefox, info: web, htmlViewers: [])
                && !BrowserPickerBrowsers.isBrowser(at: terminal, info: fallback, htmlViewers: viewers)
                && !BrowserPickerBrowsers.isBrowser(at: testing, info: web, htmlViewers: viewers),
            "only apps that open web pages as a browser are offered, not fallbacks or hidden test builds")
        suite.expect(BrowserPickerBrowsers.isVorssaint("com.vorssaint.utils")
                && BrowserPickerBrowsers.isVorssaint("com.vorssaint.utils.dev")
                && !BrowserPickerBrowsers.isVorssaint("com.apple.Safari"),
            "no build of this app is offered as a destination")
    }

    private static func firefoxProfiles(_ suite: TestSuite) {
        let ini = """
        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/aa11.default
        Default=1

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/bb22.default-release

        [General]
        StartWithLastProfile=1

        [Install2656FF1E876E9973]
        Default=Profiles/bb22.default-release
        Locked=1

        [Profile2]
        Name=Elsewhere
        IsRelative=0
        Path=/Volumes/Data/Firefox Work
        """
        let listed = BrowserPickerBrowsers.firefoxProfiles(fromIni: ini)
        let listedNames: [String] = listed.map(\.name)
        let listedPaths: [String] = listed.map(\.path)
        suite.expect(listedNames == ["default", "default-release", "Elsewhere"]
                && listedPaths == ["Profiles/aa11.default", "Profiles/bb22.default-release", "/Volumes/Data/Firefox Work"],
            "every profile section of profiles.ini is read in file order, install sections are not")

        let folder = URL(fileURLWithPath: "/Users/me/Library/Application Support/Firefox", isDirectory: true)
        let managed = [(path: "Profiles/cc33.Work", name: "Work"), (path: "Profiles/bb22.default-release", name: "Personal")]
        let used: Set<String> = ["bb22.default-release", "cc33.Work", "Firefox Work"]
        let offered = BrowserPickerBrowsers.firefoxProfiles(
            listed: listed, managed: managed, in: folder,
            wasUsed: { used.contains($0.lastPathComponent) }, exists: { _ in true })
        let offeredNames: [String] = offered.map(\.name)
        let offeredIDs: [String] = offered.map(\.id)
        suite.expect(offeredNames == ["Work", "Personal", "Elsewhere"]
                && offeredIDs == ["Profiles/cc33.Work", "Profiles/bb22.default-release", "/Volumes/Data/Firefox Work"],
            "managed profiles come first under their own names, the never-used install profile is left out")

        // The profile manager's own database, read the way Firefox writes it.
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-firefox-\(UUID().uuidString)", isDirectory: true)
        let groups = temporary.appendingPathComponent("Profile Groups", isDirectory: true)
        try? FileManager.default.createDirectory(at: groups, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var connection: OpaquePointer?
        if sqlite3_open(groups.appendingPathComponent("ab12cd34.sqlite").path, &connection) == SQLITE_OK {
            sqlite3_exec(connection, """
                CREATE TABLE "Profiles" (id INTEGER NOT NULL, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
                  avatar TEXT NOT NULL, themeId TEXT NOT NULL, themeFg TEXT NOT NULL, themeBg TEXT NOT NULL, PRIMARY KEY(id));
                INSERT INTO Profiles VALUES (2, 'Profiles/cc33.Work', 'Work', 'briefcase', 'x', 'x', 'x');
                INSERT INTO Profiles VALUES (1, 'Profiles/bb22.default-release', 'Personal', 'flower', 'x', 'x', 'x');
                """, nil, nil, nil)
        }
        sqlite3_close(connection)
        let rows = BrowserPickerBrowsers.managedFirefoxProfiles(in: temporary)
        let rowNames: [String] = rows.map(\.name)
        let rowPaths: [String] = rows.map(\.path)
        suite.expect(rowNames == ["Personal", "Work"] && rowPaths == ["Profiles/bb22.default-release", "Profiles/cc33.Work"],
            "profiles from Firefox's profile manager are read from its group database in its own order")
    }

    private static func backup(_ suite: TestSuite) {
        let exported = SettingsBackupSupport.exportKeys()
        suite.expect(exported.contains(DefaultsKey.browserPickerRules),
            "rules travel with a settings backup")
        suite.expect(!exported.contains(DefaultsKey.browserPickerPreviousBrowser),
            "the previous browser stays on this Mac")
    }
}
