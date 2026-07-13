// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules behind the quick toggles: the AppleScript sources, the Finder
/// preference parsing and the eject filter, kept free of AppKit so the unit
/// harness pins them down.
enum QuickTogglesSupport {
    static let finderDomain = "com.apple.finder"
    static let showAllFilesKey = "AppleShowAllFiles"
    static let createDesktopKey = "CreateDesktop"

    static let emptyTrashSource = "tell application \"Finder\" to empty trash"
    static let quitFinderSource = "tell application \"Finder\" to quit"

    /// Apple Event consent errors: not permitted, or the prompt was dismissed.
    static let permissionErrorNumbers: Set<Int> = [-1743, -1744]

    static func isPermissionError(_ errorNumber: Int?) -> Bool {
        guard let errorNumber else { return false }
        return permissionErrorNumbers.contains(errorNumber)
    }

    /// Finder preferences reach us as real booleans, numbers or the legacy
    /// "YES"/"TRUE"/"1" strings; anything unreadable means the given default.
    static func finderFlag(_ value: Any?, default defaultValue: Bool) -> Bool {
        switch value {
        case let flag as Bool:
            return flag
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return defaultValue
            }
        default:
            return defaultValue
        }
    }

    /// Which mounted volumes "Eject all disks" offers: local media that is
    /// external and removable or ejectable, the same shape the disk monitor
    /// ejects. Network shares and internal volumes never qualify.
    static func shouldOfferEject(isInternal: Bool,
                                 isRemovable: Bool,
                                 isEjectable: Bool,
                                 isLocal: Bool) -> Bool {
        isLocal && !isInternal && (isRemovable || isEjectable)
    }
}
