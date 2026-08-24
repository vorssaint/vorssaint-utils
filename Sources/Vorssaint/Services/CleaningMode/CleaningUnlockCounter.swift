// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure state machine for the cleaning-mode unlock gesture: it counts deliberate
/// presses of one required key. Other keys reset the count, auto-repeat is ignored,
/// and a long pause restarts it. Extracted from the event tap so the logic can be
/// tested deterministically.
struct CleaningUnlockCounter {
    let requiredKeyCode: Int64
    let threshold: Int
    /// A required-key press only counts if it lands within this window of the previous
    /// one; a longer gap restarts the count.
    let pressWindow: TimeInterval

    private(set) var progress = 0
    private var lastKeyTime: TimeInterval = -.greatestFiniteMagnitude

    init(requiredKeyCode: Int64, threshold: Int, pressWindow: TimeInterval) {
        self.requiredKeyCode = requiredKeyCode
        self.threshold = threshold
        self.pressWindow = pressWindow
    }

    /// Registers a key-down at `time` (a monotonic clock). `isRepeat` is true for
    /// auto-repeat events, which never count. Returns true once `progress` reaches
    /// the threshold, signalling the caller to unlock.
    mutating func registerKeyDown(code: Int64, time: TimeInterval, isRepeat: Bool) -> Bool {
        guard !isRepeat else { return false }
        guard code == requiredKeyCode else {
            progress = 0
            lastKeyTime = -.greatestFiniteMagnitude
            return false
        }
        if time - lastKeyTime <= pressWindow {
            progress += 1
        } else {
            progress = 1
        }
        lastKeyTime = time
        return progress >= threshold
    }

    mutating func reset() {
        progress = 0
        lastKeyTime = -.greatestFiniteMagnitude
    }
}

struct CleaningSystemKeyEvent: Equatable {
    static let systemDefinedEventTypeRawValue: UInt32 = 14
    static let powerKeySubtype = 1
    static let auxiliaryControlButtonsSubtype = 8
    static let keyDownState = 10
    static let keyUpState = 11

    private static let syntheticKeyCodeBase: Int64 = 10_000

    let code: Int64
    let isKeyDown: Bool
    let isRepeat: Bool

    static func decode(subtype: Int, data1: Int) -> CleaningSystemKeyEvent? {
        switch subtype {
        case auxiliaryControlButtonsSubtype:
            return decodeAuxiliaryControl(data1: data1)
        case powerKeySubtype:
            return CleaningSystemKeyEvent(code: syntheticKeyCodeBase + Int64(powerKeySubtype),
                                          isKeyDown: true,
                                          isRepeat: false)
        default:
            return nil
        }
    }

    private static func decodeAuxiliaryControl(data1: Int) -> CleaningSystemKeyEvent? {
        let raw = UInt32(truncatingIfNeeded: data1)
        let keyCode = Int64((raw >> 16) & 0xffff)
        let state = Int((raw >> 8) & 0xff)
        guard state == keyDownState || state == keyUpState else { return nil }
        return CleaningSystemKeyEvent(code: syntheticKeyCodeBase + keyCode,
                                      isKeyDown: state == keyDownState,
                                      isRepeat: (raw & 0x1) != 0)
    }
}
