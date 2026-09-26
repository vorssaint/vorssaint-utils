// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum WindowMaximizerSupport {
    /// An app on the exception list keeps the green button's own behavior, so
    /// a game, an emulator or a player can still enter macOS full screen.
    static func excludes(bundleIdentifier: String?, excludedBundleIdentifiers: [String]) -> Bool {
        guard let bundleIdentifier else { return false }
        return Defaults.sanitizedBundleIdentifierList(excludedBundleIdentifiers).contains(bundleIdentifier)
    }
}
