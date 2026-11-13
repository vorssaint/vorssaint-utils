// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The generator supplies the production reader, writer, launch and restore
/// methods. Only the bundle, arguments, running-instance query and defaults
/// domain are supplied by the fixture.
enum SettingsFileTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let domain = "vorss.tests.settings-file.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "can create settings file preferences fixture")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? manager.removeItem(at: root)
        }
        let link = root.appendingPathComponent("settings.plist")
        let target = root.appendingPathComponent("repo/settings.plist")
        func launch(_ arguments: [String] = ["Vorssaint"], bundle: String? = "fixture",
                    running: Bool = false) -> Set<String> {
            Backup.applyConfigFileAtLaunch(arguments: arguments, bundleID: bundle, url: link,
                                          defaults: defaults, running: { _ in running })
        }
        func plist(_ values: [String: Any], version: Any = 1) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: [
                SettingsBackupSupport.formatVersionKey: version,
                SettingsBackupSupport.settingsKey: values,
            ], format: .xml, options: 0)
        }
        let snippets = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"Greeting","trigger":";hi","replacement":"Hello","expansion":"immediate","enabled":true}]"#.utf8)
        do {
            defaults.set(snippets, forKey: DefaultsKey.textSnippets)
            defaults.set("light", forKey: DefaultsKey.appearance)
            suite.expect(Backup.write(to: target, from: defaults),
                         "an explicit export bootstraps its parent folder and snapshot")
            let permissions = try manager.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
            suite.expect(permissions?.intValue == 0o600, "a new backup containing snippets is owner-only")
            try manager.createSymbolicLink(at: link, withDestinationURL: target)
            defaults.set("dark", forKey: DefaultsKey.appearance)
            suite.expect(Backup.write(to: link, from: defaults)
                         && Backup.readSettings(at: target)?[DefaultsKey.appearance] as? String == "dark",
                         "explicit export through a writable link updates the dotfiles target")
            let destination = try manager.destinationOfSymbolicLink(atPath: link.path)
            suite.expect(destination == target.path, "export leaves the user's link in place")
            if let exported = Backup.readSettings(at: link) {
                defaults.removeObject(forKey: DefaultsKey.textSnippets)
                Backup.apply(settings: exported, in: defaults)
                let restored = TextSnippetSupport.decode(defaults.data(forKey: DefaultsKey.textSnippets))
                suite.expect(restored.count == 1 && restored[0].replacement == "Hello"
                             && restored[0].showsInLibrary && restored[0].folder.isEmpty,
                             "the existing backup path restores a snippet from before library options existed")
            } else { suite.expect(false, "explicit export can be read as a backup") }

            let featureKey = AppFeature.textSnippets.availabilityKey
            let partial = try plist([DefaultsKey.appearance: "dark", featureKey: true,
                                     "futureSetting": ["new": "value"]], version: " 1 ")
            try partial.write(to: target, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: target.path)
            defaults.set("light", forKey: DefaultsKey.appearance)
            defaults.set("unrelated", forKey: DefaultsKey.screenshotWatermarkStyle)
            let pathsOnly = ["path:/local/editor"]
            defaults.set(pathsOnly, forKey: DefaultsKey.windowLayoutIgnoredApps)
            let features = launch()
            FeaturePreset.prepareFirstRunAvailability(in: defaults, preserving: features)
            suite.expect(defaults.string(forKey: DefaultsKey.appearance) == "dark"
                         && defaults.data(forKey: DefaultsKey.textSnippets) == snippets
                         && defaults.string(forKey: DefaultsKey.screenshotWatermarkStyle) == "unrelated"
                         && defaults.stringArray(forKey: DefaultsKey.windowLayoutIgnoredApps) == pathsOnly,
                         "a partial linked plist changes only declared settings and keeps local snippets")
            suite.expect(features == [featureKey] && defaults.bool(forKey: featureKey)
                         && defaults.bool(forKey: AppFeature.mixer.availabilityKey),
                         "first-run onboarding keeps both the declared choice and unspecified essential features")
            defaults.set("light", forKey: DefaultsKey.appearance)
            for flag in ["--export-settings", "--import-settings", "--selftest", "--uninstall",
                         SuperKeyMappingGuard.cleanupArgument, "--mouse-acceleration-cleanup"] {
                suite.expect(launch(["Vorssaint", flag]).isEmpty, "\(flag) leaves the declarative file alone")
            }
            suite.expect(launch(bundle: nil).isEmpty && launch(running: true).isEmpty
                         && defaults.string(forKey: DefaultsKey.appearance) == "light",
                         "a bare binary and a second app instance leave local preferences alone")
            _ = launch()
            let afterLaunch = try Data(contentsOf: target)
            suite.expect(afterLaunch == partial && defaults.object(forKey: "futureSetting") == nil
                         && defaults.string(forKey: DefaultsKey.appearance) == "dark",
                         "a read-only source reasserts declared settings and preserves unknown keys on disk")
            if geteuid() != 0 {
                suite.expect(!Backup.write(to: link, from: defaults), "explicit export respects a read-only linked target")
                try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: target.path)
                defaults.set("light", forKey: DefaultsKey.appearance)
                suite.expect(launch().isEmpty && defaults.string(forKey: DefaultsKey.appearance) == "light",
                             "a failed read cannot authorize any settings changes")
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                let afterFailure = try Data(contentsOf: target)
                suite.expect(afterFailure == partial, "an unreadable original survives the failed load")
            } else {
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            }
            try exerciseProfiles(at: target, defaults: defaults, launch: { _ = launch() }, suite: suite)
            defaults.set("pointer", forKey: DefaultsKey.notchDisplay)
            let old = try plist([DefaultsKey.appVolumes: ["fixture.app": 0.25], DefaultsKey.smoothScrollStep: 60])
            try old.write(to: target, options: .atomic)
            defaults.set(true, forKey: DefaultsKey.appVolumesArePositions)
            _ = launch()
            let position = defaults.dictionary(forKey: DefaultsKey.appVolumes)?["fixture.app"] as? Double
            suite.expect(position == MixerRoutingSupport.volume(forGain: 0.25)
                         && defaults.data(forKey: DefaultsKey.textSnippets) == snippets,
                         "an old gain-based backup migrates on an upgraded Mac without clearing its snippets")
            defaults.set(true, forKey: DefaultsKey.hasOnboarded)
            let invalid = try plist([DefaultsKey.appearance: 123, DefaultsKey.textSnippets: Data("broken".utf8),
                                     DefaultsKey.hasOnboarded: "broken"])
            try invalid.write(to: target, options: .atomic)
            defaults.set("light", forKey: DefaultsKey.appearance)
            _ = launch()
            suite.expect(defaults.string(forKey: DefaultsKey.appearance) == "light"
                         && defaults.data(forKey: DefaultsKey.textSnippets) == snippets
                         && defaults.bool(forKey: DefaultsKey.hasOnboarded),
                         "wrong types cannot replace local libraries or restart onboarding")

            let localPresets = try JSONEncoder().encode([RecorderEditPreset(name: "Work", document: RecorderEditDocument())])
            defaults.set(localPresets, forKey: DefaultsKey.recorderEditorPresets)
            let malformedPresets: [Any] = ["broken", Data("broken".utf8)]
            for invalidPresets in malformedPresets {
                try plist([DefaultsKey.recorderEditorPresets: invalidPresets]).write(to: target, options: .atomic)
                _ = launch()
                suite.expect(defaults.data(forKey: DefaultsKey.recorderEditorPresets) == localPresets,
                             "invalid recorder presets in a settings file preserve the saved collection")
            }

            for oldVertical in [false, true] {
                defaults.set(oldVertical, forKey: DefaultsKey.scrollInverterEnabled)
                defaults.removeObject(forKey: DefaultsKey.scrollInverterHorizontalEnabled)
                Defaults.migrateScrollInverterAxes(in: defaults)
                try plist([DefaultsKey.scrollInverterEnabled: !oldVertical]).write(to: target, options: .atomic)
                _ = launch()
                suite.expect(defaults.bool(forKey: DefaultsKey.scrollInverterEnabled) == !oldVertical
                             && defaults.bool(forKey: DefaultsKey.scrollInverterHorizontalEnabled) == oldVertical,
                             "a vertical-only declaration preserves the horizontal direction migrated from this Mac")
            }

            try plist([DefaultsKey.switcherShowWindowlessFinder: false,
                       DefaultsKey.screenshotOpenEditorDirectly: true]).write(to: target, options: .atomic)
            _ = launch()
            suite.expect(defaults.string(forKey: DefaultsKey.switcherWindowlessApps) ==
                            SwitcherWindowlessApps.migrated(showsWindowlessFinder: false).rawValue
                         && defaults.string(forKey: DefaultsKey.screenshotDefaultAction) == ScreenshotDefaultAction.edit.rawValue,
                         "a settings file using the former Finder and capture options configures the current pickers")

            try exerciseExternalEdits(of: target, defaults: defaults, launch: { _ = launch() }, suite: suite)
            try partial.write(to: target, options: .atomic)
            if let imported = Backup.readSettings(at: target) {
                Backup.apply(settings: imported, in: defaults)
                suite.expect(defaults.data(forKey: DefaultsKey.textSnippets) == nil,
                             "an explicit full restore still clears omitted exportable settings")
                suite.expect(defaults.string(forKey: DefaultsKey.notchDisplay) == "pointer",
                             "an explicit backup from before Dynamic Island preserves the local island")
            } else { suite.expect(false, "old string-version backup remains readable") }
            try manager.removeItem(at: target)
            suite.expect(launch().isEmpty && !Backup.write(to: link, from: defaults),
                         "a dangling managed link is neither imported nor replaced on export")
            let danglingTarget = try manager.destinationOfSymbolicLink(atPath: link.path)
            suite.expect(danglingTarget == target.path && !manager.fileExists(atPath: target.path),
                         "an external deletion remains a deletion")
        } catch { suite.expect(false, "settings file fixture failed: \(error)") }
    }

    private static func exerciseProfiles(at target: URL, defaults: UserDefaults,
                                         launch: () -> Void, suite: TestSuite) throws {
        var options = MediaImageOptions(quality: 0.8, maxDimension: 1200, format: .png, stripMetadata: true)
        options.watermark = MediaImageWatermark(kind: .logo, logoPath: "/local/logo.png")
        let logo = MediaImageProfile(id: "logo", name: "Logo", options: options)
        options.watermark = .off
        var other = MediaImageProfile(id: "other", name: "Other", options: options)
        let saved = try JSONEncoder().encode([logo, other])
        defaults.set(String(decoding: saved, as: UTF8.self), forKey: DefaultsKey.mediaImageProfiles)
        other.name = "Renamed"
        let reordered = try JSONEncoder().encode([other, logo])
        let payload = SettingsBackupSupport.payload(appVersion: "3.4.3") {
            $0 == DefaultsKey.mediaImageProfiles ? String(decoding: reordered, as: UTF8.self) : nil
        }
        let data = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        try data.write(to: target, options: .atomic)
        launch()
        let raw = defaults.string(forKey: DefaultsKey.mediaImageProfiles) ?? ""
        let profiles = try JSONDecoder().decode([MediaImageProfile].self, from: Data(raw.utf8))
        suite.expect(profiles == [other, logo], "a renamed and reordered profile keeps the other profile's local logo by id")
    }

    private static func exerciseExternalEdits(of target: URL, defaults: UserDefaults,
                                               launch: () -> Void, suite: TestSuite) throws {
        func revision(_ step: Int) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: [
                SettingsBackupSupport.formatVersionKey: 1,
                SettingsBackupSupport.settingsKey: [DefaultsKey.smoothScrollStep: step, "future": step],
            ], format: .xml, options: 0)
        }
        let first = try revision(44), second = try revision(64), last = try revision(84)
        try first.write(to: target, options: .atomic)
        launch()
        suite.expect(defaults.integer(forKey: DefaultsKey.smoothScrollStep) == 44,
                     "the stable revision is applied before the external editor starts")
        let editor = DispatchGroup()
        DispatchQueue.global().async(group: editor) {
            do {
                for _ in 0..<8 {
                    try second.write(to: target, options: .atomic)
                    try first.write(to: target, options: .atomic)
                }
                try last.write(to: target, options: .atomic)
            } catch { return } // The final byte-for-byte assertion detects a failed edit.
        }
        for _ in 0..<4 {
            launch()
            suite.expect([44, 64, 84].contains(defaults.integer(forKey: DefaultsKey.smoothScrollStep)),
                         "a launch racing a plain file writer reads one complete revision")
        }
        editor.wait()
        launch()
        let final = try Data(contentsOf: target)
        suite.expect(final == last && defaults.integer(forKey: DefaultsKey.smoothScrollStep) == 84,
                     "the last external replacement is kept byte-for-byte and applied on the next launch")
    }
}
