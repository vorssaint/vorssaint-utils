// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum URLCleanerTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            expect(actual == expected, "\(label): got \"\(actual)\", expected \"\(expected)\"")
        }

        // MARK: URL cleaning

        expectEqual(URLCleaning.clean("https://example.com/path?utm_source=news&id=42&fbclid=abc")?.url ?? "",
                    "https://example.com/path?id=42",
                    "URL cleaner removes tracking and preserves useful query")
        expectEqual(URLCleaning.clean(" https://example.com/?GCLID=one&utm_campaign=x#section ")?.url ?? "",
                    "https://example.com/#section",
                    "URL cleaner is case-insensitive and preserves fragments")
        expectEqual(URLCleaning.clean("https://example.com/?id=42")?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner leaves clean URLs alone")
        let customURLParameters = URLCleaning.customParameters(from: " Ref, source\nref,  ")
        expect(customURLParameters == ["ref", "source"],
               "URL cleaner normalizes comma-separated custom parameter names")
        let customURLRules = URLCleaning.rules(globalNames: " Ref, source\nref,  ",
                                               siteNames: nil, disabledNames: nil)
        expectEqual(URLCleaning.clean("https://example.com/?REF=one&id=42&source=two",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner removes custom parameters by exact case-insensitive name")
        expectEqual(URLCleaning.clean("https://example.com/?reference=one",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?reference=one",
                    "URL cleaner does not treat custom parameter names as prefixes")
        // A grouped Form keeps a label column even for an empty label, which
        // left every field on the right half of its row. The hint has to
        // travel as `prompt:` and the label has to be hidden for a field to
        // own its whole row.
        let urlCleanerSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/URLCleanerSettings.swift",
            encoding: .utf8)) ?? ""
        expect(!urlCleanerSettingsSource.contains("TextField(l10n.s."),
               "no Clean URL field spends its row on a label instead of the field")
        expect(urlCleanerSettingsSource.components(separatedBy: "TextField(").count
                == urlCleanerSettingsSource.components(separatedBy: ".labelsHidden()").count,
               "every Clean URL field hides its label so the field owns the row")

        // Rules are stored as a difference from the built-in tables, never as
        // a copy of them, so names a later version adds still reach someone
        // who has already edited their rules.
        let keptUTM = URLCleaning.rules(globalNames: nil, siteNames: nil, disabledNames: "|utm_*")
        expectEqual(URLCleaning.clean("https://example.com/?utm_source=news&fbclid=abc&id=1",
                                      rules: keptUTM)?.url ?? "",
                    "https://example.com/?utm_source=news&id=1",
                    "switching the utm row off keeps every utm name and leaves the rest cleaning")
        let keptShareToken = URLCleaning.rules(globalNames: nil, siteNames: nil,
                                               disabledNames: "youtube.com|si")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=1&si=x&feature=share",
                                      rules: keptShareToken)?.url ?? "",
                    "https://www.youtube.com/watch?v=1&si=x",
                    "a switched off site name stays in the link while its siblings still go")
        let addedSiteRule = URLCleaning.rules(globalNames: nil, siteNames: "weibo.com|sudaref",
                                              disabledNames: nil)
        expectEqual(URLCleaning.clean("https://weibo.com/a?sudaref=x&id=1", rules: addedSiteRule)?.url ?? "",
                    "https://weibo.com/a?id=1",
                    "a name added to one site cleans that site")
        expectEqual(URLCleaning.clean("https://example.com/?sudaref=x", rules: addedSiteRule)?.url ?? "",
                    "https://example.com/?sudaref=x",
                    "a name added to one site never reaches another")
        expect(URLCleaning.clean("https://example.com/?utm_source=a&fbclid=b&id=1")?.removed
                == ["utm_source", "fbclid"],
               "cleaning answers with the names it took out, in the order the link carried them")
        expect(URLCleaning.outcome(for: nil, input: "nope") == .notAURL,
               "text that is not a link reads as no URL")
        let paddedLink = " https://example.com/?id=1 "
        expect(URLCleaning.outcome(for: URLCleaning.clean(paddedLink), input: paddedLink) == .unchanged,
               "trimming alone does not count as a clean")

        let editedRules = URLCleaning.rules(globalNames: "ref", siteNames: "weibo.com|sudaref",
                                            disabledNames: "|fbclid")
        let ruleGroups = URLCleaning.ruleGroups(rules: editedRules)
        expect(ruleGroups.first?.site == URLCleaning.allSites,
               "the rules that apply everywhere lead the list")
        expect(ruleGroups.first?.entries.first?.name == URLCleaning.utmWildcard,
               "one row stands for every utm name")
        expect(ruleGroups.first?.entries.allSatisfy {
            $0.name == URLCleaning.utmWildcard || !$0.name.hasPrefix("utm_")
        } == true, "the utm names that row already covers are not listed again")
        expect(ruleGroups.first?.entries.contains { $0.name == "fbclid" && !$0.isEnabled } == true,
               "a switched off built-in stays listed so it can be switched back on")
        expect(ruleGroups.first?.entries.contains { $0.name == "ref" && !$0.isBuiltIn } == true,
               "names the user added share the list with the built-in ones")
        expect(ruleGroups.contains { $0.site == "weibo.com" },
               "a site the user added gets a row of its own")
        expect(ruleGroups.contains { $0.site == "youtube.com" },
               "every built-in site is listed")
        expectEqual(URLCleaning.siteKey(from: " https://WWW.Weibo.com/path?x=1 ") ?? "",
                    "weibo.com", "the site field takes a pasted link and keeps the host")
        expect(URLCleaning.siteKey(from: "not a host") == nil,
               "text that is not a host is refused rather than stored")
        expectEqual(URLCleaning.parameterName(from: " Ref ") ?? "", "ref",
                    "a parameter name is trimmed and lowercased")
        expect(URLCleaning.parameterName(from: "a=b") == nil,
               "a name a query cannot carry as one parameter is refused")
        expect(URLCleaning.tokens(from: "youtube.com|si, |ref") == ["youtube.com": ["si"], "": ["ref"]],
               "stored tokens read back as site and global names")
        expectEqual(URLCleaning.storageValue(forTokens: URLCleaning.tokens(from: "youtube.com|si, |ref")),
                    "|ref,youtube.com|si", "tokens are stored in a stable order")

        expect([DefaultsKey.urlCleanerCustomParameters,
                DefaultsKey.urlCleanerSiteParameters,
                DefaultsKey.urlCleanerDisabledParameters].allSatisfy {
                    Defaults.registeredDefaults[$0] as? String == ""
                        && SettingsBackupSupport.exportKeys().contains($0)
                },
               "URL cleaner rules start empty and travel in Settings backups")
        expect(URLCleaning.clean("not a url") == nil,
               "URL cleaner rejects plain text")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1TY8J67EUB/?spm_id_from=333.1007.tianma.1-1-1.click&vd_source=3b2eea5")?.url ?? "",
                    "https://www.bilibili.com/video/BV1TY8J67EUB/",
                    "URL cleaner strips Bilibili share tracking")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90&vd_source=abc")?.url ?? "",
                    "https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90",
                    "URL cleaner keeps the Bilibili part number and playback position")
        expectEqual(URLCleaning.clean("https://search.bilibili.com/all?keyword=swift&from_source=webtop_search")?.url ?? "",
                    "https://search.bilibili.com/all?keyword=swift",
                    "URL cleaner keeps the Bilibili search keyword")
        expectEqual(URLCleaning.clean("https://youtu.be/TImSMeurR84?si=Xq1&t=42")?.url ?? "",
                    "https://youtu.be/TImSMeurR84?t=42",
                    "URL cleaner strips the YouTube share token and keeps the timestamp")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=TImSMeurR84")?.url ?? "",
                    "https://www.youtube.com/watch?v=TImSMeurR84",
                    "URL cleaner leaves a bare YouTube watch link alone")
        expectEqual(URLCleaning.clean("https://x.com/user/status/1?s=20&t=abc")?.url ?? "",
                    "https://x.com/user/status/1",
                    "URL cleaner strips X share tracking")
        expectEqual(URLCleaning.clean("https://example.com/?si=keep&t=keep&s=keep")?.url ?? "",
                    "https://example.com/?si=keep&t=keep&s=keep",
                    "site rules never leak onto other hosts")
        expectEqual(URLCleaning.clean("https://open.spotify.com/track/abc?si=xyz")?.url ?? "",
                    "https://open.spotify.com/track/abc",
                    "site rules match subdomains")
        expectEqual(URLCleaning.clean("https://www.reddit.com/r/swift/comments/abc/?%24deep_link=true&%243p=x&share_id=y&sort=new")?.url ?? "",
                    "https://www.reddit.com/r/swift/comments/abc/?sort=new",
                    "URL cleaner strips Reddit's deep-link tracking in either spelling")
    }
}
