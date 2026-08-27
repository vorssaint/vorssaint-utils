// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Decision logic for keeping the launch at login registration alive.
///
/// The system's own record is not durable enough on its own. A registration
/// made from a temporary location (a mounted disk image, or the randomized
/// read-only mount the system uses for unmoved downloads) points at a path
/// that no longer exists on the next launch, and system updates have been
/// seen dropping third-party items outright. So the app remembers the user's
/// choice in preferences and redoes a lost registration at startup.
enum LaunchAtLoginSupport {
    /// What the system holds for this app. `needsApproval` is a registration
    /// that exists but is switched off in System Settings › Login Items: only
    /// the user can turn it back on there, so the app must neither treat it as
    /// working nor keep registering over it.
    enum Registration: Equatable {
        case enabled
        case needsApproval
        case off
    }

    enum StartupAction: Equatable {
        /// Leave everything as it is.
        case none
        /// The system has launch at login on but the stored choice says off:
        /// the user turned it on outside the app, so adopt that choice.
        case adoptEnabled
        /// The user wants launch at login and the system lost the
        /// registration: register again from the current location.
        case register
    }

    /// What startup reconciliation should do. Startup never disables
    /// anything: turning the item off is always an explicit user action.
    /// Registration is only redone from a stable location, because a record
    /// made from an unstable one would just die with the mount again, and
    /// never over an item awaiting approval: the record is already there and
    /// registering again cannot approve it (issue #260).
    static func startupAction(wanted: Bool, registration: Registration,
                              locationIsUnstable: Bool) -> StartupAction {
        switch registration {
        case .enabled:
            return wanted ? .none : .adoptEnabled
        case .needsApproval:
            return .none
        case .off:
            return wanted && !locationIsUnstable ? .register : .none
        }
    }
}
