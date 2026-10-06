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

    /// Which mounted volumes "Eject all disks" offers. The system flags
    /// describe two different things: the bus tells whether the drive is
    /// external, while removable and ejectable describe media that leaves the
    /// drive, like a card or a disc. An external drive with fixed media, which
    /// is what most desk drives are, answers no to both, so asking for
    /// removable media hid them all. The bus decides, and media that comes out
    /// of an internal reader still counts. Network shares, the volume the Mac
    /// booted from, internal fixed drives and drives in the user's exclusion list
    /// never qualify.
    static func shouldOfferEject(isInternal: Bool,
                                 isRemovable: Bool,
                                 isEjectable: Bool,
                                 isLocal: Bool,
                                 isRootFileSystem: Bool,
                                 volumeName: String? = nil,
                                 volumeUUID: String? = nil,
                                 mountPath: String? = nil,
                                 excludedVolumes: Set<String> = []) -> Bool {
        guard isLocal && !isRootFileSystem && (!isInternal || isRemovable || isEjectable) else {
            return false
        }
        guard !excludedVolumes.isEmpty else { return true }
        return !isExcluded(volumeName: volumeName,
                           volumeUUID: volumeUUID,
                           mountPath: mountPath,
                           excludedVolumes: excludedVolumes)
    }

    /// Whether a volume matches any entry in the user's exclusion list by
    /// name (case-insensitive), volume UUID, full mount path or mount directory name.
    /// None of the four forms is optional to pass: an entry the user typed is
    /// honoured or ignored depending on which identifiers the caller happened
    /// to hand over, so a caller that has none says so with an explicit nil.
    static func isExcluded(volumeName: String?,
                           volumeUUID: String?,
                           mountPath: String?,
                           excludedVolumes: Set<String>) -> Bool {
        guard !excludedVolumes.isEmpty else { return false }
        if let name = volumeName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            if excludedVolumes.contains(name) || excludedVolumes.contains(name.lowercased()) {
                return true
            }
        }
        if let uuid = volumeUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !uuid.isEmpty {
            if excludedVolumes.contains(uuid) || excludedVolumes.contains(uuid.lowercased()) {
                return true
            }
        }
        if let mountPath = mountPath?.trimmingCharacters(in: .whitespacesAndNewlines), !mountPath.isEmpty {
            if excludedVolumes.contains(mountPath) || excludedVolumes.contains(mountPath.lowercased()) {
                return true
            }
            let lastComponent = (mountPath as NSString).lastPathComponent
            if !lastComponent.isEmpty && (excludedVolumes.contains(lastComponent) || excludedVolumes.contains(lastComponent.lowercased())) {
                return true
            }
        }
        return false
    }

    // MARK: - Dock preferences

    /// The Dock reads these once, at launch, so every write here is paired
    /// with a restart: the preference file on its own changes nothing the
    /// user can see.
    static let dockDomain = "com.apple.dock"
    static let dockRevealDelayKey = "autohide-delay"

    /// Zero wait. The value the toggle writes to remove the delay.
    static let instantRevealDelay: Double = 0
    /// The delay macOS ships with, restored when the toggle is switched off.
    /// An absent key already means this, so writing it back leaves the Dock
    /// exactly as it found it rather than only approximately right.
    static let systemRevealDelay: Double = 0.2

    /// A Dock preference arrives as an NSNumber, a Double or a decimal string
    /// depending on who wrote it last; anything unreadable is nil, and nil means
    /// "not set", which the toggle treats as Apple's default.
    static func dockNumber(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    /// Whether the reveal is already instant, so the row can name what the next
    /// click will do instead of reporting the state after the fact.
    static func revealDelayIsInstant(_ current: Double?) -> Bool {
        guard let current else { return false }
        return current == instantRevealDelay
    }

    /// The value the toggle writes: instant when the delay is not already gone,
    /// Apple's default when it is. Nil (unset) counts as Apple's default, so the
    /// first click on a Mac that never set the key removes the delay and the
    /// second puts back the value the system would have used anyway.
    static func toggledRevealDelay(_ current: Double?) -> Double {
        revealDelayIsInstant(current) ? systemRevealDelay : instantRevealDelay
    }

    // The two hot-corner codes below are undocumented system values. Apple
    // publishes no list of them; they are corroborated across independent
    // sources that agree, which is the strongest evidence available for an
    // interface that has no documentation at all. A future release could
    // renumber them, so re-verify rather than trust this comment -- and rather
    // than assume the codes the toggle does not write are safe to touch, which
    // is why only these two exist here.

    /// Undocumented hot-corner code for "do nothing".
    static let hotCornerActionNone = 0
    /// Undocumented hot-corner code for "Show Desktop".
    static let hotCornerActionShowDesktop = 4

    static let bottomLeftCornerKey = "wvous-bl-corner"
    static let bottomRightCornerKey = "wvous-br-corner"

    /// Which of the two bottom corners carry the Show Desktop hot corner.
    enum DockHotCorner: String, CaseIterable, Equatable {
        case none, bottomLeft, bottomRight, both
    }

    /// The cycle order. `none` first because switching the feature off is the
    /// state a user returns to when they want the corners back.
    static func nextHotCornerState(_ state: DockHotCorner) -> DockHotCorner {
        switch state {
        case .none: return .bottomLeft
        case .bottomLeft: return .bottomRight
        case .bottomRight: return .both
        case .both: return .none
        }
    }

    /// What the two corner codes currently say. A corner counts as on when its
    /// code is Show Desktop specifically — not merely non-zero — because a corner
    /// the user assigned Mission Control to is not one this toggle owns, and
    /// reporting it as "on" would promise a Desktop corner it will not give.
    static func hotCornerState(bottomLeft: Any?, bottomRight: Any?) -> DockHotCorner {
        hotCornerState(bottomLeftCode: cornerCode(bottomLeft),
                       bottomRightCode: cornerCode(bottomRight))
    }

    /// A raw corner value as the integer the code comparison wants, or "no
    /// action" when the key is unset or holds something unreadable — both of
    /// which read as off, which is what they are.
    private static func cornerCode(_ value: Any?) -> Int {
        guard let number = dockNumber(value) else { return hotCornerActionNone }
        return Int(number)
    }

    /// The code each corner needs for a given state.
    static func hotCornerCodes(for state: DockHotCorner) -> (bottomLeft: Int, bottomRight: Int) {
        switch state {
        case .none:
            return (hotCornerActionNone, hotCornerActionNone)
        case .bottomLeft:
            return (hotCornerActionShowDesktop, hotCornerActionNone)
        case .bottomRight:
            return (hotCornerActionNone, hotCornerActionShowDesktop)
        case .both:
            return (hotCornerActionShowDesktop, hotCornerActionShowDesktop)
        }
    }

    /// The state a set of codes reads back as. Exists so the cycle can be proven
    /// to survive a round trip through the preference layer instead of assumed to.
    static func hotCornerState(bottomLeftCode: Int, bottomRightCode: Int) -> DockHotCorner {
        let left = bottomLeftCode == hotCornerActionShowDesktop
        let right = bottomRightCode == hotCornerActionShowDesktop
        switch (left, right) {
        case (false, false): return .none
        case (true, false): return .bottomLeft
        case (false, true): return .bottomRight
        case (true, true): return .both
        }
    }

    // The toggle OWNS the two bottom corners while it has them on Show Desktop.
    // Switching a corner off and back on leaves it on Show Desktop, not on
    // whatever action the user had before: the original codes are deliberately
    // not stored, because a toggle that has to keep a shadow copy consistent
    // with a preference another app and System Settings both write is a worse
    // bug than a corner that comes back as Desktop. The user reassigns a corner
    // in System Settings, which is where every other hot corner is chosen too,
    // and the row's caption says which corner the next click will take.
    //
    // The top two corners (wvous-tl-corner, wvous-tr-corner) are never read and
    // never written. The cycle covers only the corners a pointer reaches without
    // travelling, and a key the toggle does not touch is a key it cannot undo.
}
