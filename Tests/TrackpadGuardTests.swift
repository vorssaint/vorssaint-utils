// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TrackpadGuardTests {
    private final class Lease: TrackpadGuardLeaseHandle {
        var alive = true
        var restores = true
        var stopCount = 0
        var beats = 0
        func heartbeat() -> Bool { beats += 1; return alive }
        func stop() -> Bool { stopCount += 1; return restores }
    }

    static func run(_ suite: TestSuite) {
        let native = "com.example.Editor"
        let java = "/Games/JDK/bin/java"
        let wine = "/private/tmp/winetemp-123/WorldOfTanks.exe"
        let apps = [native, java, wine]
        func matches(_ selected: String, bundleID: String?, path: String?) -> Bool {
            TrackpadGuardSupport.matches(apps: [selected], identities: MouseAppExceptionSupport.identities(
                bundleID: bundleID, executablePath: path, readsPath: selected.hasPrefix("/")),
                executablePath: path)
        }
        suite.expect(matches(native, bundleID: native, path: "/different/path"),
                     "a native app matches by bundle ID across install locations")
        suite.expect(!matches(native, bundleID: "com.example.Other", path: "/Apps/Editor"),
                     "a selected bundle cannot match an unrelated app by path")
        suite.expect(matches(java, bundleID: "org.lwjgl.glfw", path: java),
                     "an unbundled game runtime uses the same executable identity as the shared app picker")
        suite.expect(!matches(java, bundleID: nil, path: "/Other/JDK/bin/java"),
                     "selecting one Java runtime does not match another runtime")
        suite.expect(matches(wine, bundleID: nil, path: "/private/tmp/winetemp-999/worldoftanks.EXE"),
                     "a Wine game survives changing temporary executable directories and case")
        suite.expect(!matches(wine, bundleID: nil, path: "/tmp/WargamingErrorMonitor.exe"),
                     "a Wine game does not match its launcher or helpers")
        suite.expect(!TrackpadGuardSupport.matches(apps: apps, identities: [], executablePath: nil)
                     && !TrackpadGuardSupport.matches(apps: [], identities: [native], executablePath: wine),
                     "unknown apps and empty selections never disable input")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trackpad-guard-identity-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let executable = folder.appendingPathComponent("java")
            let link = folder.appendingPathComponent("launcher-java")
            try Data().write(to: executable)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
            let selectedLink = MouseAppExceptionSupport.executablePathIdentity(link.path)!
            suite.expect(matches(selectedLink, bundleID: nil, path: executable.path),
                         "a launcher-picked symlink matches the real Java executable reported by macOS")
            suite.expect(matches(selectedLink, bundleID: nil, path: link.path),
                         "the same selection also matches a process reported through its symlink")
        } catch {
            suite.expect(false, "executable symlink fixture can be created: \(error)")
        }
        for enabled in [false, true] {
            for selected in [false, true] {
                for mouse in [false, true] {
                    for active in [false, true] {
                        for awake in [false, true] {
                            suite.expect(TrackpadGuardSupport.shouldIgnore(enabled: enabled,
                                selectedAppInFront: selected, mousePresent: mouse, sessionActive: active, awake: awake)
                                == (enabled && selected && mouse && active && awake),
                                "all five activation conditions are necessary")
                        }
                    }
                }
            }
        }
        for transport in ["USB", "Bluetooth", "Bluetooth Low Energy"] {
            suite.expect(TrackpadGuardSupport.isExternalMouse(conformsToMouse: true, builtIn: false,
                         accelerationType: "HIDMouseAcceleration", transport: transport),
                         "physical \(transport) mice can activate trackpad guard")
        }
        for (mouse, builtIn, type, transport) in [
            (true, true, "HIDMouseAcceleration", "USB"),
            (true, false, "HIDTrackpadAcceleration", "Bluetooth"),
            (true, false, "HIDMouseAcceleration", "Virtual"),
            (true, false, "HIDTrackpadAcceleration", "SPI"),
            (false, false, "HIDMouseAcceleration", "USB"),
        ] {
            suite.expect(!TrackpadGuardSupport.isExternalMouse(conformsToMouse: mouse, builtIn: builtIn,
                         accelerationType: type, transport: transport),
                         "trackpads, internal devices and virtual pointers do not disable the only trackpad")
        }
        suite.expect(TrackpadGuardSupport.restorationTarget(original: 0, current: 1,
                     savedAtCapture: 0, savedNow: 0) == 0,
                     "normal restoration returns the captured runtime value")
        suite.expect(TrackpadGuardSupport.restorationTarget(original: 1, current: 1,
                     savedAtCapture: 1, savedNow: 1) == 1,
                     "a pre-existing global ignore setting remains enabled")
        suite.expect(TrackpadGuardSupport.restorationTarget(original: 0, current: 1,
                     savedAtCapture: 0, savedNow: 1) == 1,
                     "a user enabling macOS's global ignore setting during a lease keeps that choice")
        suite.expect(TrackpadGuardSupport.restorationTarget(original: 1, current: 1,
                     savedAtCapture: 1, savedNow: 0) == 0,
                     "a user disabling the saved global setting takes precedence over the original value")
        suite.expect(TrackpadGuardSupport.restorationTarget(original: 1, current: 0,
                     savedAtCapture: 1, savedNow: 1) == nil,
                     "input already restored by another runtime change is never disabled again on release")
        let lease = Lease()
        var acquisitions = 0
        let session = TrackpadGuardSession { acquisitions += 1; return lease }
        session.update(shouldIgnore: false)
        suite.expect(acquisitions == 0 && !session.isIgnoring, "idle notifications do not acquire a lease")
        session.update(shouldIgnore: true)
        session.update(shouldIgnore: true)
        session.heartbeat()
        suite.expect(acquisitions == 1 && lease.beats == 1 && session.isIgnoring,
                     "repeated app/device events share one active lease and heartbeat")
        session.update(shouldIgnore: false)
        session.update(shouldIgnore: false)
        suite.expect(lease.stopCount == 1 && !session.isIgnoring,
                     "leaving any activation condition restores once and tears down the lease")
        session.update(shouldIgnore: true)
        lease.alive = false
        session.heartbeat()
        session.update(shouldIgnore: true)
        suite.expect(session.failed && !session.isIgnoring && acquisitions == 2 && lease.stopCount == 2,
                     "a watchdog failure restores and latches instead of immediately disabling input again")
        session.retry()
        lease.alive = true
        session.update(shouldIgnore: true)
        suite.expect(!session.failed && session.isIgnoring && acquisitions == 3,
                     "an explicit retry can acquire a fresh lease")
        lease.restores = false
        suite.expect(!session.stop() && session.failed && !session.isIgnoring,
                     "a failed restoration cannot be reported as a successful stop")
        let refused = TrackpadGuardSession { nil }
        refused.update(shouldIgnore: true)
        suite.expect(refused.failed && !refused.isIgnoring, "an unavailable or occupied backend stays hands off")
        suite.expect(refused.stop(), "a backend that never acquired input does not block app teardown")

        suite.expect(AppFeature.trackpadGuard.group == .mouseKeyboard
                     && !AppFeature.trackpadGuard.installedByDefault
                     && AppFeature.trackpadGuard.permissions.isEmpty,
                     "the feature is opt-in and asks for no unrelated permissions")
        suite.expect(AppFeature.trackpadGuard.enabledKeys == [DefaultsKey.trackpadGuardEnabled]
                     && AppFeature.trackpadGuard.settingsDestination == FeatureSettingsDestination(.mouse, sectionAnchor: .trackpadGuard),
                     "availability, enable state and Settings routing share the feature identity")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.trackpadGuardEnabled)
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.trackpadGuardApps),
                     "the enable choice and portable app rules participate in backup")
        let payload = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.trackpadGuardApps ? apps : nil
        }
        let settings = payload[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        suite.expect((settings[DefaultsKey.trackpadGuardApps] as? [String]) == [native],
                     "backup exports bundle IDs and keeps executable paths on this Mac")
        let restored = SettingsBackupSupport.restoredExceptionList(
            restored: settings[DefaultsKey.trackpadGuardApps] as? [String] ?? [],
            carried: SettingsBackupSupport.pathIdentities(in: apps))
        suite.expect(restored == apps,
                     "restoring a backup preserves this Mac's local executable selections")
        let imported = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: [DefaultsKey.trackpadGuardApps: apps],
        ])
        suite.expect((imported?[DefaultsKey.trackpadGuardApps] as? [String]) == [native],
                     "a caller-supplied backup cannot inject executable paths from another Mac")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.trackpadGuard(language)
            suite.expect(!text.title.isEmpty && !text.description.isEmpty && !text.unavailable.isEmpty,
                         "trackpad guard has visible and failure text in \(language.rawValue)")
        }
    }
}
