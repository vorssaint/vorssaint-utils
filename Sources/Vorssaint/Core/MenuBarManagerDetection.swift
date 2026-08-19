// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum MenuBarManagerDetection {
    struct RunningManager: Equatable {
        let bundleIdentifier: String
        let name: String
    }

    static let bundleIdentifierPrefixes = [
        "com.stonerl.Thaw",
        "com.jordanbaird.Ice",
        "com.surteesstudios.Bartender",
        "com.dwarvesv.minimalbar",
        "com.mortenjust.Dozer",
    ]

    static func isKnownManager(bundleIdentifier: String) -> Bool {
        bundleIdentifierPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    static func runningManagers() -> [RunningManager] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  isKnownManager(bundleIdentifier: bundleID)
            else { return nil }
            return RunningManager(bundleIdentifier: bundleID,
                                  name: app.localizedName ?? bundleID)
        }
    }
}
