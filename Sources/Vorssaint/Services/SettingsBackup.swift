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
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Reads and validates a backup; nil when the file is not one of ours.
    static func readSettings(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? PropertyListSerialization.propertyList(from: data,
                                                                        options: [],
                                                                        format: nil) as? [String: Any]
        else { return nil }
        return SettingsBackupSupport.sanitizedSettings(from: payload)
    }

    /// Clears the exportable keys (unset ones fall back to their registered
    /// defaults), writes the file's values and relaunches.
    static func applyAndRelaunch(settings: [String: Any]) {
        let defaults = UserDefaults.standard
        for key in SettingsBackupSupport.exportKeys() {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings {
            defaults.set(value, forKey: key)
        }
        FeatureRuntime.shared.relaunchApp()
    }
}
