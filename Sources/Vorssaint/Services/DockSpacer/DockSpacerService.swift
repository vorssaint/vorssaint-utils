// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// System touch points are explicit so previews and smoke runs never edit the real Dock.
struct DockSpacerService: Sendable {
    enum Action: Sendable {
        case addLarge, addSmall, restart
    }

    enum Result: Equatable, Sendable {
        case added, restarted, addFailed, restartFailed, addedButRestartFailed

        var succeeded: Bool {
            switch self {
            case .added, .restarted: return true
            case .addFailed, .restartFailed, .addedButRestartFailed: return false
            }
        }
    }

    let domain: String
    let restartDock: @Sendable () -> Bool

    static let live = DockSpacerService(
        domain: "com.apple.dock",
        restartDock: { Shell.run("/usr/bin/killall", ["Dock"]).status == 0 }
    )

    /// Run off the main thread. Append through defaults rather than rewriting a
    /// cached persistent-apps array, preserving the user's existing Dock items.
    func perform(_ action: Action, restartAfterAdding: Bool) -> Result {
        let tile: String
        switch action {
        case .addLarge:
            tile = "{\"tile-data\"={}; \"tile-type\"=\"spacer-tile\";}"
        case .addSmall:
            tile = "{\"tile-type\"=\"small-spacer-tile\";}"
        case .restart:
            return restartDock() ? .restarted : .restartFailed
        }
        guard Shell.run("/usr/bin/defaults", ["write", domain, "persistent-apps", "-array-add", tile]).status == 0
        else { return .addFailed }
        guard restartAfterAdding else { return .added }
        return restartDock() ? .restarted : .addedButRestartFailed
    }
}
