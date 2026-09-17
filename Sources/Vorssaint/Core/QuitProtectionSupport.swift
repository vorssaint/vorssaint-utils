// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum QuitProtectionShortcut: String, CaseIterable, Identifiable {
    case quit
    case close

    var id: String { rawValue }
    var character: String { self == .quit ? "q" : "w" }
    /// The US position, used only while no layout and no character can be read.
    var fallbackKeyCode: Int64 { self == .quit ? 12 : 13 }
    var symbol: String { self == .quit ? "⌘Q" : "⌘W" }
}

enum QuitProtectionMode: String, CaseIterable, Identifiable {
    case hold
    case doublePress
    case extraModifier

    var id: String { rawValue }
}

enum QuitProtectionExtraModifier: String, CaseIterable, Identifiable {
    case shift
    case option
    case control

    var id: String { rawValue }
}

enum QuitProtectionScope: String, CaseIterable, Identifiable {
    case all
    case selectedOnly
    case allExceptSelected

    var id: String { rawValue }
}

struct QuitProtectionConfiguration: Equatable {
    var enabled: Bool
    var mode: QuitProtectionMode
    var holdDurationMilliseconds: Double
    var doublePressIntervalMilliseconds: Double
    var extraModifier: QuitProtectionExtraModifier
    var scope: QuitProtectionScope
    var exceptions: [String]
    var showFeedback: Bool
}

enum QuitProtectionSupport {
    static let holdDurationRange = 250.0...2_000.0
    static let doublePressIntervalRange = 200.0...1_500.0
    static let defaultHoldDurationMilliseconds = 800.0
    static let defaultDoublePressIntervalMilliseconds = 600.0

    static func sanitizedHoldDuration(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHoldDurationMilliseconds }
        return min(max(value, holdDurationRange.lowerBound), holdDurationRange.upperBound)
    }

    static func sanitizedDoublePressInterval(_ value: Double) -> Double {
        guard value.isFinite else { return defaultDoublePressIntervalMilliseconds }
        return min(max(value, doublePressIntervalRange.lowerBound), doublePressIntervalRange.upperBound)
    }

    /// CGEvent timestamps are monotonic nanoseconds. Confirmation uses them
    /// directly so a busy main run loop cannot make a valid second press miss
    /// its configured interval.
    static func isWithinDoublePressInterval(firstTimestamp: UInt64,
                                            secondTimestamp: UInt64,
                                            intervalMilliseconds: Double) -> Bool {
        guard secondTimestamp >= firstTimestamp else { return false }
        let allowedNanoseconds = UInt64(
            sanitizedDoublePressInterval(intervalMilliseconds) * 1_000_000
        )
        return secondTimestamp - firstTimestamp <= allowedNanoseconds
    }

    static func usesNativeQuitRequest(for shortcut: QuitProtectionShortcut) -> Bool {
        shortcut == .quit
    }

    static func scopeAllows(_ scope: QuitProtectionScope,
                            bundleIdentifier: String?,
                            exceptions: [String]) -> Bool {
        let contains = bundleIdentifier.map { exceptions.contains($0) } ?? false
        switch scope {
        case .all: return true
        case .selectedOnly: return contains
        case .allExceptSelected: return !contains
        }
    }

    /// Only the exact Command shortcut is protected by hold/double press.
    /// Extra-modifier mode deliberately claims the bare shortcut too, so a
    /// user cannot bypass protection by pressing plain Command-Q/Command-W.
    static func isBaseShortcut(keyCharacter: String?,
                               keyCode: Int64,
                               commandLabel: String?,
                               command: Bool,
                               control: Bool,
                               option: Bool,
                               shift: Bool,
                               shortcut: QuitProtectionShortcut) -> Bool {
        guard command, !control, !option, !shift else { return false }
        return matchesKey(keyCharacter: keyCharacter,
                          keyCode: keyCode,
                          commandLabel: commandLabel,
                          shortcut: shortcut)
    }

    static func isExtraShortcut(keyCharacter: String?,
                                keyCode: Int64,
                                commandLabel: String?,
                                command: Bool,
                                control: Bool,
                                option: Bool,
                                shift: Bool,
                                shortcut: QuitProtectionShortcut,
                                extraModifier: QuitProtectionExtraModifier) -> Bool {
        guard command else { return false }
        let hasExtra: Bool
        switch extraModifier {
        case .shift: hasExtra = shift && !option && !control
        case .option: hasExtra = option && !shift && !control
        case .control: hasExtra = control && !shift && !option
        }
        return hasExtra && matchesKey(keyCharacter: keyCharacter,
                                      keyCode: keyCode,
                                      commandLabel: commandLabel,
                                      shortcut: shortcut)
    }

    /// `commandLabel` is what the layout's Command table types on this key, the
    /// table macOS resolves Command-Q through; `keyCharacter` is the bare one,
    /// "й" on Russian and ";" on Greek for the very key that quits.
    static func matchesKey(keyCharacter: String?,
                           keyCode: Int64,
                           commandLabel: String?,
                           shortcut: QuitProtectionShortcut) -> Bool {
        if let commandLabel {
            return commandLabel.lowercased() == shortcut.character
        }
        if let keyCharacter {
            return keyCharacter.lowercased() == shortcut.character
        }
        return keyCode == shortcut.fallbackKeyCode
    }

    static func modeFor(_ rawValue: String?) -> QuitProtectionMode {
        guard let rawValue, let value = QuitProtectionMode(rawValue: rawValue) else { return .hold }
        return value
    }

    static func extraModifierFor(_ rawValue: String?) -> QuitProtectionExtraModifier {
        guard let rawValue, let value = QuitProtectionExtraModifier(rawValue: rawValue) else { return .shift }
        return value
    }

    static func scopeFor(_ rawValue: String?) -> QuitProtectionScope {
        guard let rawValue, let value = QuitProtectionScope(rawValue: rawValue) else { return .all }
        return value
    }
}
