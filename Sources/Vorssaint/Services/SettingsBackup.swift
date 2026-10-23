// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// Settings backup: writes the exportable preferences to a plist and brings
/// one back in. Importing replaces the current preferences and relaunches, so
/// every service, panel and status item comes back from a clean state instead
/// of chasing 25 live re-syncs.
enum SettingsBackup {
    /// Shows the save panel and writes the file. nil = user cancelled.
    @discardableResult
    static func runExportPanel() -> Bool? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Vorssaint Settings.plist"
        panel.allowedContentTypes = [.propertyList]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        ScratchpadService.shared.prepareForSettingsBackup()
        let defaults = UserDefaults.standard
        // object(forKey:) sees through to registered defaults, so the file is
        // a complete snapshot: importing it reproduces this exact setup even
        // where the user never touched a control.
        let payload = SettingsBackupSupport.payload(appVersion: AppInfo.version) {
            defaults.object(forKey: $0)
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: payload,
                                                          format: .xml,
                                                          options: 0)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Shows the open panel; nil = user cancelled.
    static func runImportPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList, .xml]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Reads and validates a backup; nil when the file is not one of ours.
    static func readSettings(at url: URL) -> [String: Any]? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var coordinatedData: Data?
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { readURL in
            coordinatedData = try? Data(contentsOf: readURL)
        }
        guard let data = coordinatedData ?? (try? Data(contentsOf: url)),
              let payload = try? PropertyListSerialization.propertyList(from: data,
                                                                        options: [],
                                                                        format: nil) as? [String: Any]
        else { return nil }
        return SettingsBackupSupport.sanitizedSettings(from: payload)
    }

    /// Writes the file's values and relaunches.
    static func applyAndRelaunch(settings: [String: Any]) {
        ScratchpadService.shared.prepareForSettingsRestore()
        apply(settings: settings)
        FeatureRuntime.shared.relaunchApp()
    }

    /// Clears the exportable keys (unset ones fall back to their registered
    /// defaults) and writes the file's values.
    private static func apply(settings: [String: Any]) {
        let defaults = UserDefaults.standard
        let localRecorderPresets = defaults.data(forKey: DefaultsKey.recorderEditorPresets)
        let localWatermark = defaults.string(forKey: DefaultsKey.screenshotWatermarkStyle)
        let localWatermarkPresets = defaults.string(forKey: DefaultsKey.screenshotWatermarkPresets)
        // A backup carries only the portable half of an exception list: the
        // path of a program that is not an app is authority on one Mac and is
        // filtered out on export (issue #1009). The clear below covers every
        // exported key, so without carrying that half across by hand, applying
        // a backup would delete those entries outright -- including on the Mac
        // the file was written on, where nothing about them was ever wrong.
        // The thumbnail pause lists take such paths too (issue #3033).
        let carried = (MouseExceptionScope.allCases.map(\.defaultsKey)
                       + SettingsBackupSupport.thumbnailPauseListKeys)
            .reduce(into: [String: [String]]()) { out, key in
                out[key] = SettingsBackupSupport.pathIdentities(in: defaults.stringArray(forKey: key) ?? [])
            }
        let windowLayoutPaths = SettingsBackupSupport.pathIdentities(
            in: defaults.stringArray(forKey: DefaultsKey.windowLayoutIgnoredApps) ?? [])
        for key in SettingsBackupSupport.keysToClear(whenImporting: settings) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings {
            defaults.set(value, forKey: key)
        }
        if let shared = SettingsBackupSupport.sharedSwitcherPauseList(in: settings) {
            defaults.set(shared, forKey: DefaultsKey.switcherPreviewExcludedApps)
        }
        if let restored = settings[DefaultsKey.recorderEditorPresets] as? Data {
            defaults.set(SettingsBackupSupport.preservingLocalPresetImages(
                restored: restored, local: localRecorderPresets), forKey: DefaultsKey.recorderEditorPresets)
        }
        defaults.set(SettingsBackupSupport.restoredScreenshotWatermark(
            restored: settings[DefaultsKey.screenshotWatermarkStyle] as? String,
            local: localWatermark), forKey: DefaultsKey.screenshotWatermarkStyle)
        defaults.set(SettingsBackupSupport.restoredScreenshotWatermarkPresets(
            restored: settings[DefaultsKey.screenshotWatermarkPresets] as? String,
            local: localWatermarkPresets), forKey: DefaultsKey.screenshotWatermarkPresets)
        for (key, paths) in carried where !paths.isEmpty {
            defaults.set(SettingsBackupSupport.restoredExceptionList(
                restored: defaults.stringArray(forKey: key) ?? [],
                carried: paths), forKey: key)
        }
        if !windowLayoutPaths.isEmpty {
            defaults.set(SettingsBackupSupport.restoredExceptionList(
                restored: defaults.stringArray(forKey: DefaultsKey.windowLayoutIgnoredApps) ?? [],
                carried: windowLayoutPaths), forKey: DefaultsKey.windowLayoutIgnoredApps)
        }
    }

    // MARK: - Settings file (issue #497)

    private static var pendingConfigFileWrite: DispatchWorkItem?

    /// nil for the bare binary (`--selftest`), whose preferences are not the app's.
    private static var configFileURL: URL? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return SettingsBackupSupport.configFileURL(
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser,
            isDeveloperBuild: AppInfo.isDeveloperBuild)
    }

    /// Applies the settings file when it differs from the preferences. Runs
    /// before the defaults are registered and migrated, so the file's values
    /// go through the same migrations as an imported backup after its relaunch.
    static func loadConfigFile() {
        guard let url = configFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let settings = readSettings(at: url) else { return }
        let defaults = UserDefaults.standard
        let availability = AppFeature.availabilityDefaults
        // Nothing is registered yet, so fall back to the registered values the
        // file was written with; otherwise every launch would look like a change.
        let current = SettingsBackupSupport.payload(appVersion: AppInfo.version) {
            defaults.object(forKey: $0) ?? Defaults.registeredDefaults[$0] ?? availability[$0]
        }
        guard NSDictionary(dictionary: settings)
                != NSDictionary(dictionary: SettingsBackupSupport.sanitizedSettings(from: current) ?? [:])
        else { return }
        apply(settings: settings)
    }

    /// Writes the settings file now and again shortly after each change, so it
    /// always holds what Export settings would.
    static func startMirroringConfigFile() {
        guard configFileURL != nil else { return }
        writeConfigFile()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                               object: nil, queue: .main) { _ in
            pendingConfigFileWrite?.cancel()
            let work = DispatchWorkItem { writeConfigFile() }
            pendingConfigFileWrite = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in
            pendingConfigFileWrite?.cancel()
            writeConfigFile()
        }
    }

    /// Follows a symlink so a dotfiles link stays a link, and leaves alone a
    /// read-only file (a Nix store link) or one that does not parse, so a
    /// hand edit with a typo is not overwritten before it can be fixed.
    private static func writeConfigFile() {
        guard let url = configFileURL?.resolvingSymlinksInPath() else { return }
        let defaults = UserDefaults.standard
        let payload = SettingsBackupSupport.payload(appVersion: AppInfo.version) {
            defaults.object(forKey: $0)
        }
        let fileManager = FileManager.default
        let existing = try? Data(contentsOf: url)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: payload,
                                                             format: .xml,
                                                             options: 0),
              data != existing else { return }
        if existing != nil {
            guard fileManager.isWritableFile(atPath: url.path),
                  readSettings(at: url) != nil else { return }
        }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
