// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DefaultBrowserTests {
    static func run(_ suite: TestSuite) {
        let zen = URL(fileURLWithPath: "/Applications/Zen.app")
        let safari = URL(fileURLWithPath: "/Applications/Safari.app")
        let terminal = URL(fileURLWithPath: "/Applications/cmux.app")
        let hidden = URL(fileURLWithPath: "/Users/me/.cache/ms-playwright/chromium/Chromium.app")
        let viewers: Set<URL> = [zen, safari, terminal, hidden]
        func web(_ schemes: [String], rank: String? = nil) -> [String: Any] {
            var type: [String: Any] = ["CFBundleURLSchemes": schemes]
            type["LSHandlerRank"] = rank
            return type
        }

        suite.expect(DefaultBrowserSupport.isBrowser(
            at: zen, info: ["CFBundleURLTypes": [web(["http"]), web(["https"]), web(["file"])]],
            htmlViewers: viewers),
            "a browser that opens web links and HTML files is offered")
        // Safari ranks some private schemes None; only its web schemes count.
        suite.expect(DefaultBrowserSupport.isBrowser(
            at: safari, info: ["CFBundleURLTypes": [web(["http", "https"], rank: "Default"),
                                                    web(["prefs"], rank: "None")]],
            htmlViewers: viewers),
            "a None rank on an unrelated scheme keeps a browser")
        suite.expect(!DefaultBrowserSupport.isBrowser(
            at: terminal, info: ["CFBundleURLTypes": [web(["http", "https"], rank: "Alternate")]],
            htmlViewers: viewers),
            "an app that ranks itself Alternate for web links is not a browser")
        suite.expect(!DefaultBrowserSupport.isBrowser(
            at: zen, info: ["CFBundleURLTypes": [web(["HTTPS"], rank: "None")]], htmlViewers: viewers),
            "web schemes are compared without case")
        suite.expect(!DefaultBrowserSupport.isBrowser(
            at: zen, info: ["CFBundleURLTypes": [web(["https"])]], htmlViewers: []),
            "an app that does not open HTML files is not a browser")
        suite.expect(!DefaultBrowserSupport.isBrowser(
            at: hidden, info: ["CFBundleURLTypes": [web(["https"])]], htmlViewers: viewers),
            "a test browser kept in a hidden folder is not offered")

        for lang in AppLanguage.allCases {
            let s = FeatureStrings.defaultBrowser(lang)
            suite.expect([s.title, s.hubDescription, s.current, s.none, s.makeDefault, s.isDefault,
                          s.empty, s.confirmNote].allSatisfy { !$0.isEmpty },
                   "default browser strings are filled in for \(lang)")
        }
    }
}
