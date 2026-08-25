// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement

/// `Vorssaint --uninstall`: cleanly detaches the app from the system
/// before its bundle is removed. It unregisters the fan helper daemon and the
/// login item — so no dead entry lingers in System Settings › General › Login
/// Items — and restores normal sleep if a closed-lid session left it disabled.
///
/// Used by `Tools/uninstall.sh`. Must run from the installed bundle, since
/// `SMAppService.mainApp` is scoped to the running app's bundle identifier.
enum Uninstaller {
    static func runAndExit() -> Never {
        // The fan helper is a daemon service of its own, so unregistering the
        // main app as a login item never reaches it. Without this its root
        // registration outlives the bundle that carried its executable.
        let detached = FanControlService.restoreAndUnregisterForRemoval()
        print(detached
              ? "UNINSTALL: fan helper daemon unregistered"
              : "UNINSTALL: fan helper daemon still registered")
        if UserDefaults.standard.bool(forKey: DefaultsKey.sleepDisabledFlag) {
            _ = Sudoers.pmsetDisableSleep(false)
        }
        do {
            try SMAppService.mainApp.unregister()
            print("UNINSTALL: login item unregistered")
        } catch {
            print("UNINSTALL: login item was not registered")
        }
        // Only the daemon decides the status. A login item that was never
        // registered is not a failure; a daemon left behind is the one thing
        // the caller cannot see for itself.
        exit(detached ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
