// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Emre Aribulan

import Foundation

@main
struct LauncherTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let entry = IslandLauncherEntry(
            name: "Steam", path: "/Users/test/Applications/CrossOver/Steam/Steam.app", bookmark: Data([1, 2]))
        check(
            IslandLauncherSupport.decode(try JSONEncoder().encode([entry])) == [entry],
            "saved identities and bookmark data round-trip")
        let samePath = IslandLauncherEntry(
            name: "Duplicate", path: "/Users/test/Applications/CrossOver/Steam/../Steam/Steam.app")
        check(
            IslandLauncherSupport.sanitized([entry, samePath]).count == 1,
            "normalised duplicate paths do not create extra launchers")
        let sameID = IslandLauncherEntry(id: entry.id, name: "Other", path: "/Applications/Other.app")
        check(IslandLauncherSupport.sanitized([entry, sameID]).count == 1, "duplicate row IDs are rejected")
        check(
            IslandLauncherSupport.sanitized([IslandLauncherEntry(name: "bad", path: "relative.app")]).isEmpty,
            "relative paths rejected")
        check(
            IslandLauncherSupport.sanitized([IslandLauncherEntry(name: "bad", path: "/tmp/run.sh")]).isEmpty,
            "arbitrary executable scripts are not app entries")
        check(IslandLauncherSupport.decode(Data("broken".utf8)).isEmpty, "malformed preferences are safe")
        check(
            IslandLauncherSupport.decode(Data(repeating: 0, count: 1_048_577)).isEmpty,
            "oversized preferences are bounded")
        check(
            IslandLauncherSupport.sanitized([
                IslandLauncherEntry(
                    name: "bad", path: "/Applications/Test.app", bookmark: Data(repeating: 0, count: 65_537))
            ]).isEmpty, "oversized bookmarks rejected")
        let many = (0..<130).map { IslandLauncherEntry(name: "App \($0)", path: "/Applications/App\($0).app") }
        check(IslandLauncherSupport.sanitized(many).count == 100, "list capacity bounded")
        let clean = IslandLauncherSupport.sanitized([
            IslandLauncherEntry(name: "\nGame\tName\r", path: "/Applications/Game.app")
        ])[0]
        check(clean.name == "GameName", "control characters removed from menu names")
        let empty = IslandLauncherSupport.sanitized([
            IslandLauncherEntry(name: "  ", path: "/Applications/Some Game.app")
        ])[0]
        check(empty.name == "Some Game", "empty names fall back to app name")
        let spaces = IslandLauncherEntry(
            name: "Everything is Crab 🦀", path: "/Users/test/Applications/CrossOver/Steam/Everything is Crab.app")
        check(
            IslandLauncherSupport.decode(try JSONEncoder().encode([spaces])) == [spaces],
            "spaces and Unicode preserved without shell escaping")
        let legacy = Data(
            "[{\"id\":\"\(entry.id.uuidString)\",\"name\":\"Steam\",\"path\":\"/Applications/Steam.app\",\"bookmark\":\"AQI=\"}]"
                .utf8)
        let restored = IslandLauncherSupport.decode(legacy)
        check(
            restored.first?.id == entry.id && restored.first?.bookmark == Data([1, 2])
                && restored.first?.website == nil,
            "pre-website preferences preserve IDs/bookmarks without a migration reset")
        let website = IslandLauncherEntry(name: "", path: "", website: "HTTPS://Example.COM:443/docs?q=a#section")
        let normalized = IslandLauncherSupport.sanitized([website])[0]
        check(
            normalized.website == "https://example.com/docs?q=a#section" && normalized.name == "example.com",
            "website URL and fallback name normalized")
        check(
            IslandLauncherSupport.websiteURL("example.com")?.absoluteString == "https://example.com/",
            "missing scheme defaults to https")
        for invalid in [
            "javascript:alert(1)", "file:///tmp/script", "data:text/html,bad", "mailto:a@example.com",
            "https://user:secret@example.com", "https://", "https://examp\nle.com", "https://example.com:99999",
        ] {
            check(IslandLauncherSupport.websiteURL(invalid) == nil, "unsafe or malformed website rejected: \(invalid)")
        }
        let duplicateWebsite = IslandLauncherEntry(
            name: "Other name", path: "", website: "https://EXAMPLE.com:443/docs?q=a#section")
        check(
            IslandLauncherSupport.sanitized([entry, website, duplicateWebsite]).count == 2,
            "mixed apps/sites deduplicate normalized URLs")
        let otherPage = IslandLauncherEntry(name: "Other page", path: "", website: "https://example.com/other")
        check(
            IslandLauncherSupport.sanitized([website, otherPage]).count == 2,
            "different pages remain separate shortcuts")
        let mixed = IslandLauncherSupport.sanitized([entry, website])
        check(
            IslandLauncherSupport.decode(try JSONEncoder().encode(mixed)) == mixed, "mixed app/site entries round-trip")
        check(
            IslandLauncherSupport.sanitized([
                IslandLauncherEntry(name: "bad", path: "/Applications/Good.app", website: "javascript:bad")
            ]).isEmpty,
            "invalid website never falls through to app launching")
        let page = URL(string: "https://example.com/landing/")!
        let html = """
            <!-- <link rel=icon href='/comment.png'> -->
            <script>let x = '<link rel=icon href="/script.png">';</script>
            <BASE href='/assets/'>
            <LINK HREF='icons/main.png?a=1&amp;b=2' SIZES='64x64' REL='shortcut ICON'>
            <link rel=apple-touch-icon href=/touch.png sizes=180x180>
            <link rel=icon href='javascript:bad'>
            <link rel=icon href='https://user:secret@example.com/no.png'>
            """
        let candidates = WebsiteShortcutSupport.iconCandidates(html: html, pageURL: page)
        check(
            candidates.prefix(2).map(\.absoluteString) == [
                "https://example.com/touch.png", "https://example.com/assets/icons/main.png?a=1&b=2",
            ],
            "base URL, attribute order/case, tokenized rel, sizes and entities respected")
        check(
            candidates.count == 4,
            "script/comment declarations and unsafe icon URLs ignored; standard fallbacks included")
        check(
            WebsiteShortcutSupport.origin(of: URL(string: "https://example.com/private?token=secret#fragment")!)?
                .absoluteString == "https://example.com/",
            "discovery origin excludes private page paths, queries and fragments")
        let largeBookmarks = (0..<100).map {
            IslandLauncherEntry(
                name: "App \($0)", path: "/Applications/App\($0).app", bookmark: Data(repeating: 7, count: 65_536))
        }
        let bounded = IslandLauncherSupport.sanitized(largeBookmarks)
        let boundedData = try JSONEncoder().encode(bounded)
        check(
            !bounded.isEmpty && boundedData.count <= IslandLauncherSupport.maximumDataSize
                && IslandLauncherSupport.decode(boundedData) == bounded,
            "accepted bookmark collections remain within the decode limit and survive restart")
        check(
            IslandLauncherSupport.websiteURL("example.com:8443/docs")?.absoluteString
                == "https://example.com:8443/docs",
            "a hostname with an explicit port defaults to https")
        check(
            IslandLauncherSupport.websiteURL("http://localhost:8080/") != nil
                && IslandLauncherSupport.websiteURL("https://[::1]:8443/") != nil,
            "explicit local hosts and IPv6 remain valid web targets")
        print("PASS: \(checks) launcher persistence and validation checks")
    }
}
