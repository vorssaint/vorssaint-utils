// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement

/// Launch at login, remembered and self-repairing.
///
/// All UI goes through here so the choice stored in preferences and the real
/// registration never drift apart. `LaunchAtLoginSupport` explains why the
/// system record alone cannot be trusted across relaunches.
enum LaunchAtLogin {
    /// What the system will actually do at the next login.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Thrown when the app runs from a place whose registration cannot
    /// survive a relaunch; the message tells the user how to fix it.
    struct UnstableLocationError: LocalizedError {
        var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApplications }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled, locationIsUnstable { throw UnstableLocationError() }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.launchAtLoginWanted)
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Only surface failures that leave the system out of step with
            // the user's choice. Unregistering an item that was already gone
            // reports an error even though the end state is exactly what the
            // user asked for.
            if isEnabled != enabled {
                // The stored intent must match what the user actually got;
                // keeping the failed wish would make the startup repair
                // register an item the UI showed as off.
                UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.launchAtLoginWanted)
                throw error
            }
        }
    }

    /// Redoes a registration the system lost and adopts an enable made in
    /// the system's own settings. Called once at startup.
    static func repairAtStartup() {
        let defaults = UserDefaults.standard
        switch LaunchAtLoginSupport.startupAction(
            wanted: defaults.bool(forKey: DefaultsKey.launchAtLoginWanted),
            systemEnabled: isEnabled,
            locationIsUnstable: locationIsUnstable) {
        case .none:
            break
        case .adoptEnabled:
            defaults.set(true, forKey: DefaultsKey.launchAtLoginWanted)
        case .register:
            try? SMAppService.mainApp.register()
        }
    }

    private static var locationIsUnstable: Bool {
        UpdateInstallerSupport.runsFromImmutableLocation(
            appPath: Bundle.main.bundlePath,
            volumeIsReadOnly: { path in
                let values = try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.volumeIsReadOnlyKey])
                return values?.volumeIsReadOnly ?? true
            })
    }
}
