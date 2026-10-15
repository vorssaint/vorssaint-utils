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

        let installed = ["zen", "chrome", "safari"]
        suite.expect(DefaultBrowserSupport.next(after: "zen", chosen: ["zen", "safari"], installed: installed) == "safari"
                && DefaultBrowserSupport.next(after: "safari", chosen: ["zen", "safari"], installed: installed) == "zen",
               "the shortcut moves to the next chosen browser and wraps around")
        suite.expect(DefaultBrowserSupport.next(after: "chrome", chosen: ["zen", "safari"], installed: installed) == "zen"
                && DefaultBrowserSupport.next(after: nil, chosen: ["zen", "safari"], installed: installed) == "zen",
               "a default outside the chosen browsers switches to the first chosen one")
        suite.expect(DefaultBrowserSupport.next(after: "zen", chosen: [], installed: installed) == "chrome",
               "with nothing chosen the shortcut goes through every installed browser")
        suite.expect(DefaultBrowserSupport.next(after: "zen", chosen: ["zen", "tor", "safari"], installed: installed) == "safari",
               "a chosen browser that is no longer installed is skipped")
        suite.expect(DefaultBrowserSupport.next(after: "zen", chosen: ["zen"], installed: installed) == nil
                && DefaultBrowserSupport.next(after: "zen", chosen: ["tor"], installed: installed) == nil,
               "with no other chosen browser installed there is nothing to switch to")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.defaultBrowserShortcutEnabled] as? Bool == false
                && (Defaults.registeredDefaults[DefaultsKey.defaultBrowserRotation] as? [String])?.isEmpty == true
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.defaultBrowserRotation),
               "the shortcut starts off and the chosen browsers travel with settings backup")

        let island = UserDefaults(suiteName: "com.vorssaint.tests.default-browser-island")!
        island.removePersistentDomain(forName: "com.vorssaint.tests.default-browser-island")
        island.register(defaults: Defaults.registeredDefaults)
        island.set(true, forKey: DefaultsKey.notchEnabled)
        island.set(true, forKey: AppFeature.notch.availabilityKey)
        island.set(true, forKey: AppFeature.defaultBrowser.availabilityKey)
        let announces = NotchSupport.routes(.defaultBrowser, in: island)
        island.set(false, forKey: DefaultsKey.notchDefaultBrowser)
        let silenced = !NotchSupport.routes(.defaultBrowser, in: island)
        island.set(true, forKey: DefaultsKey.notchDefaultBrowser)
        island.set(false, forKey: AppFeature.defaultBrowser.availabilityKey)
        suite.expect(announces && silenced && !NotchSupport.routes(.defaultBrowser, in: island),
               "the island shows a switch only with its toggle and the feature on")
        island.removePersistentDomain(forName: "com.vorssaint.tests.default-browser-island")

        for lang in AppLanguage.allCases {
            let s = FeatureStrings.defaultBrowser(lang)
            suite.expect([s.title, s.hubDescription, s.current, s.none, s.makeDefault, s.isDefault,
                          s.empty, s.confirmNote, s.nextBrowser, s.inRotation, s.rotationCaption, s.panelCaption, s.islandNotice].allSatisfy { !$0.isEmpty },
                   "default browser strings are filled in for \(lang)")
        }
    }
}
