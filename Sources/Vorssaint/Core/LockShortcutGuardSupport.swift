// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum LockShortcutGuardMode: String, CaseIterable, Identifiable {
    case hold
    case doublePress

    var id: String { rawValue }
}

/// Pure rules for guarding Control-Command-Q, the shortcut that locks the
/// screen. Timing limits are the ones Quit Protection already uses for
/// Command-Q.
enum LockShortcutGuardSupport {
    static let symbol = "⌃⌘Q"

    static let holdDurationRange = QuitProtectionSupport.holdDurationRange
    static let doublePressIntervalRange = QuitProtectionSupport.doublePressIntervalRange
    static let defaultHoldDurationMilliseconds = QuitProtectionSupport.defaultHoldDurationMilliseconds
    static let defaultDoublePressIntervalMilliseconds = QuitProtectionSupport.defaultDoublePressIntervalMilliseconds

    static func modeFor(_ rawValue: String?) -> LockShortcutGuardMode {
        guard let rawValue, let value = LockShortcutGuardMode(rawValue: rawValue) else { return .hold }
        return value
    }

    /// The key the layout types Q with under Command, the table macOS answers
    /// Command shortcuts from: keycode 0 on AZERTY, 7 on Dvorak, 12 on QWERTY
    /// and on Russian, whose bare character there is "й". The US position is
    /// used only while no layout can be read.
    static func lockKeyCode(commandLabel: (Int64) -> String?) -> Int64 {
        (0...127).first { commandLabel($0)?.lowercased() == QuitProtectionShortcut.quit.character }
            ?? QuitProtectionShortcut.quit.fallbackKeyCode
    }

    /// Command-Q protection with Control as its extra key confirms a quit with
    /// Control-Command-Q, so that press belongs to it and this guard steps
    /// aside.
    static func quitProtectionOwnsShortcut(quitEnabled: Bool,
                                           quitMode: QuitProtectionMode,
                                           extraModifier: QuitProtectionExtraModifier) -> Bool {
        quitEnabled && quitMode == .extraModifier && extraModifier == .control
    }

    /// A second press inside the interval confirms; one landing later starts
    /// over.
    static func isSecondPress(after elapsedMilliseconds: Double, intervalMilliseconds: Double) -> Bool {
        elapsedMilliseconds >= 0
            && elapsedMilliseconds <= QuitProtectionSupport.sanitizedDoublePressInterval(intervalMilliseconds)
    }

    /// A hold lasts only while both modifiers stay down.
    static func holdSurvivesFlagsChange(control: Bool, command: Bool) -> Bool {
        control && command
    }
}
