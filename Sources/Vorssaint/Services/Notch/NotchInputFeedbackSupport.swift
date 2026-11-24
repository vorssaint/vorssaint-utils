// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

/// Live keyboard lock/modifier indicator shown inside the Dynamic Island.
enum NotchModifierIndicator: Equatable {
    case capsLock
    case shift
    case both

    static func from(capsLock: Bool, shift: Bool) -> NotchModifierIndicator? {
        switch (capsLock, shift) {
        case (true, true): return .both
        case (true, false): return .capsLock
        case (false, true): return .shift
        case (false, false): return nil
        }
    }

    var wings: NotchNoticeWings {
        switch self {
        case .capsLock: return NotchNoticeWings(leading: 54, trailing: 54)
        case .shift: return NotchNoticeWings(leading: 56, trailing: 56)
        case .both: return NotchNoticeWings(leading: 66, trailing: 66)
        }
    }

    func label(_ strings: NotchInputFeedbackStrings) -> String {
        switch self {
        case .capsLock: return strings.capsLock
        case .shift: return strings.shiftHeld
        case .both: return "\(strings.capsLock) · ⇧"
        }
    }

    var tint: Color {
        switch self {
        case .capsLock: return Color(red: 1.00, green: 0.78, blue: 0.28)
        case .shift: return Color(red: 0.56, green: 0.88, blue: 1.00)
        case .both: return Color(red: 1.00, green: 0.84, blue: 0.45)
        }
    }
}

/// Debounces held Shift keys (220ms) so fast capital typing never flickers the island,
/// while reflecting Caps Lock state immediately.
struct NotchModifierHoldTracker: Equatable {
    static let shiftHoldDelay: TimeInterval = 0.22

    private(set) var capsLockOn = false
    private(set) var shiftPhysicallyDown = false
    private(set) var shiftDownAt: TimeInterval?
    private(set) var shiftAnnounced = false

    var indicator: NotchModifierIndicator? {
        NotchModifierIndicator.from(capsLock: capsLockOn, shift: shiftAnnounced)
    }

    @discardableResult
    mutating func update(capsLock: Bool, shiftDown: Bool, otherModifiersDown: Bool, at now: TimeInterval) -> NotchModifierIndicator? {
        capsLockOn = capsLock
        if !shiftDown || otherModifiersDown {
            shiftPhysicallyDown = false
            shiftDownAt = nil
            shiftAnnounced = false
        } else if !shiftPhysicallyDown {
            shiftPhysicallyDown = true
            shiftDownAt = now
            shiftAnnounced = false
        } else if let downAt = shiftDownAt, now - downAt >= Self.shiftHoldDelay {
            shiftAnnounced = true
        }
        return indicator
    }

    @discardableResult
    mutating func tick(at now: TimeInterval) -> NotchModifierIndicator? {
        if shiftPhysicallyDown, !shiftAnnounced, let downAt = shiftDownAt, now - downAt >= Self.shiftHoldDelay {
            shiftAnnounced = true
        }
        return indicator
    }
}

/// Identifies Command-V / Shift-Option-Command-V paste keystrokes and debounces bursts.
struct NotchPasteDetector: Equatable {
    static let debounceInterval: TimeInterval = 0.25
    private(set) var lastReportedAt: TimeInterval = -.infinity

    static func isPasteKey(keyCode: UInt16, charactersIgnoringModifiers: String?, command: Bool, control: Bool) -> Bool {
        guard command, !control else { return false }
        return keyCode == 9 || charactersIgnoringModifiers?.lowercased() == "v"
    }

    mutating func recordPaste(at now: TimeInterval) -> Bool {
        guard now - lastReportedAt >= Self.debounceInterval else { return false }
        lastReportedAt = now
        return true
    }
}
