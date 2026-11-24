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

    // MARK: - Quit all apps

    /// Vorssaint's own identifiers, including the local signing variant. Quitting
    /// ourselves mid-sweep would leave the remaining apps running with no way
    /// to finish the pass from here.
    static let vorssaintBundleIdentifiers = [
        "com.vorssaint.utils",
        "com.vorssaint.utils.dev",
    ]

    /// `NSApplication.ActivationPolicy.regular.rawValue`. Kept as an Int so this
    /// file stays free of AppKit for the unit harness.
    static let regularActivationPolicy = 0

    /// Kept apps always start with Auto Quit's locked pair, Finder and Phone.
    /// Vorssaint is never stored: the quit rules leave it alone by themselves.
    static func sanitizedQuitAllExceptions(_ bundleIDs: [String]) -> [String] {
        Defaults.sanitizedBundleIdentifierList(Defaults.mandatoryAutoQuitExceptionBundleIDs + bundleIDs)
            .filter { !vorssaintBundleIdentifiers.contains($0) }
    }

    /// Whether a running app should receive a soft quit. Only regular GUI apps
    /// with a bundle id, still alive, and outside the exception set qualify.
    static func shouldQuitApp(bundleIdentifier: String?,
                              activationPolicyRawValue: Int,
                              isTerminated: Bool,
                              exceptions: Set<String>) -> Bool {
        guard !isTerminated else { return false }
        guard activationPolicyRawValue == regularActivationPolicy else { return false }
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              !vorssaintBundleIdentifiers.contains(bundleIdentifier) else { return false }
        return !exceptions.contains(bundleIdentifier)
    }

    /// Whether the Quit apps window lists a running app. Finder relaunches
    /// itself and Vorssaint owns the window, so neither gets a row; other
    /// exceptions are listed (marked kept) so they can still be quit by hand.
    static func listsApp(bundleIdentifier: String?,
                         activationPolicyRawValue: Int,
                         isTerminated: Bool) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        guard bundleIdentifier != Defaults.finderBundleIdentifier,
              !vorssaintBundleIdentifiers.contains(bundleIdentifier) else { return false }
        return !isTerminated && activationPolicyRawValue == regularActivationPolicy
    }

    /// The process ids a batch quit sends `terminate()` to. Keeping the
    /// frontmost app only removes that one process; every exception still holds.
    static func batchQuitTargets(_ apps: [QuitAppsCandidate],
                                 exceptions: Set<String>,
                                 keepingPID: Int32?) -> [Int32] {
        apps.filter { app in
            app.pid != keepingPID
                && shouldQuitApp(bundleIdentifier: app.bundleIdentifier,
                                 activationPolicyRawValue: app.activationPolicyRawValue,
                                 isTerminated: app.isTerminated,
                                 exceptions: exceptions)
        }
        .map(\.pid)
    }

}

/// One running app as Quit apps sees it, reduced to the facts the targeting
/// rules read so they stay free of AppKit.
struct QuitAppsCandidate: Equatable {
    let pid: Int32
    let bundleIdentifier: String?
    let activationPolicyRawValue: Int
    let isTerminated: Bool
}

/// What Return does in the Quit apps window, chosen by how it was opened.
enum QuitAppsScope: Equatable {
    case all
    case allExceptFront
}

/// The Quit apps window's buttons, in on-screen order.
enum QuitAppsButton: Equatable {
    case cancel, allExceptFront, all
}

/// The one highlight the window has: an app row (by process id) or a button.
/// Return confirms whatever it is on.
enum QuitAppsFocus: Equatable {
    case row(Int32)
    case button(QuitAppsButton)
}

/// Arrow keys, plus `next` and `previous` for Tab and Shift-Tab.
enum QuitAppsMove: Equatable {
    case up, down, left, right, next, previous
}

extension QuickTogglesSupport {
    /// Cancel is always there; a batch button only when it would do something.
    static func quitAppsButtons(offersExceptFront: Bool, canQuitAll: Bool) -> [QuitAppsButton] {
        [.cancel] + (offersExceptFront ? [.allExceptFront] : []) + (canQuitAll ? [.all] : [])
    }

    /// Where the highlight rests when the window opens: the button for the way
    /// it was opened, or Cancel when that button is not offered.
    static func restingQuitAppsButton(scope: QuitAppsScope?,
                                      buttons: [QuitAppsButton]) -> QuitAppsButton {
        let wanted: QuitAppsButton?
        switch scope {
        case .all: wanted = .all
        case .allExceptFront: wanted = .allExceptFront
        case nil: wanted = nil
        }
        if let wanted, buttons.contains(wanted) { return wanted }
        return .cancel
    }

    /// Rows sit above the buttons: Down from the last row lands on the resting
    /// button and Up from any button lands on the last row. Arrows stop at the
    /// ends of the button bar; Tab wraps around it.
    static func movedQuitAppsFocus(_ focus: QuitAppsFocus,
                                   _ move: QuitAppsMove,
                                   rows: [Int32],
                                   buttons: [QuitAppsButton],
                                   resting: QuitAppsButton) -> QuitAppsFocus {
        switch focus {
        case .row(let pid):
            guard let index = rows.firstIndex(of: pid) else { return .button(resting) }
            switch move {
            case .up: return .row(rows[max(index - 1, 0)])
            case .down: return index + 1 < rows.count ? .row(rows[index + 1]) : .button(resting)
            case .left, .right: return focus
            case .next, .previous: return .button(resting)
            }
        case .button(let button):
            guard let index = buttons.firstIndex(of: button) else { return .button(resting) }
            switch move {
            case .up: return rows.last.map { .row($0) } ?? focus
            case .down: return focus
            case .left: return .button(buttons[max(index - 1, 0)])
            case .right: return .button(buttons[min(index + 1, buttons.count - 1)])
            case .next: return .button(buttons[(index + 1) % buttons.count])
            case .previous: return .button(buttons[(index - 1 + buttons.count) % buttons.count])
            }
        }
    }

    /// Keeps the highlight in place when an app quits or launches: a vanished
    /// row hands it to whichever row now sits where it was.
    static func quitAppsFocusAfterListChange(_ focus: QuitAppsFocus,
                                             previousRows: [Int32],
                                             rows: [Int32],
                                             buttons: [QuitAppsButton],
                                             resting: QuitAppsButton) -> QuitAppsFocus {
        switch focus {
        case .row(let pid):
            if rows.contains(pid) { return focus }
            guard !rows.isEmpty else { return .button(resting) }
            let index = previousRows.firstIndex(of: pid) ?? 0
            return .row(rows[min(index, rows.count - 1)])
        case .button(let button):
            return buttons.contains(button) ? focus : .button(resting)
        }
    }

    /// Type to jump, as in a Finder list: the first row whose name starts with
    /// what was typed, ignoring case and accents.
    static func quitAppsRow(matching prefix: String,
                            in rows: [(pid: Int32, name: String)]) -> Int32? {
        guard !prefix.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
        return rows.first { $0.name.range(of: prefix, options: options) != nil }?.pid
    }
}
