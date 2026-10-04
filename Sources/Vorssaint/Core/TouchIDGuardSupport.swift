// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TouchIDGuardMode: String, CaseIterable, Identifiable {
    /// A press of the Touch ID / Power button never locks the Mac.
    case ignore
    /// Only a press kept down for the chosen time locks the Mac.
    case hold

    var id: String { rawValue }
}

/// What the guard concluded about one press of the button.
enum TouchIDGuardVerdict: Equatable {
    case waiting
    case released
    case reached
}

enum TouchIDGuardSupport {
    /// The press arrives as a system-defined event of this subtype.
    static let systemDefinedEventTypeRawValue: UInt32 = 14
    static let pressSubtype = 16

    /// The driver of the built-in Touch ID / Power button. A press carries
    /// the registry id of the service that sent it in this event field, which
    /// is how the built-in button is told from a key on another keyboard
    /// that sends the same event.
    static let builtInButtonServiceClass = "AppleM68Buttons"
    static let senderIDFieldRawValue: UInt32 = 87

    /// SMC key that reads non-zero while the button is down and zero once it
    /// is released. The press event has no release counterpart, so this is
    /// how a hold is told from a tap.
    static let pressedStateKey = "bHLD"

    /// The event reaches a tap this long after the button goes down; measured
    /// at 303 to 318 ms on a press of any length.
    static let pressToEventDelayMilliseconds = 300.0
    /// Below the event delay no hold can be told from a tap.
    static let holdDurationRange = 400.0...2_000.0
    static let defaultHoldDurationMilliseconds = 800.0
    static let pollIntervalMilliseconds = 20.0

    static func sanitizedHoldDuration(_ value: Double) -> Double {
        guard value.isFinite else { return defaultHoldDurationMilliseconds }
        return min(max(value, holdDurationRange.lowerBound), holdDurationRange.upperBound)
    }

    static func modeFor(_ rawValue: String?) -> TouchIDGuardMode {
        guard let rawValue, let value = TouchIDGuardMode(rawValue: rawValue) else { return .hold }
        return value
    }

    static func isPress(eventType: UInt32, subtype: Int) -> Bool {
        eventType == systemDefinedEventTypeRawValue && subtype == pressSubtype
    }

    /// Only a press the built-in button sent is the guard's. A press with no
    /// sender, or on a Mac where the button could not be found, is left to
    /// macOS.
    static func isBuiltInPress(senderID: Int64, builtInButtonID: UInt64?) -> Bool {
        guard let builtInButtonID, senderID != 0 else { return false }
        return UInt64(bitPattern: senderID) == builtInButtonID
    }

    /// The key is a little-endian integer: any non-zero byte means down.
    static func isDown(_ bytes: [UInt8]) -> Bool {
        bytes.contains { $0 != 0 }
    }

    /// `elapsedSinceEvent` is measured from the moment the press event was
    /// seen; the finger went down `pressToEventDelayMilliseconds` before that.
    static func verdict(elapsedSinceEventMilliseconds: Double,
                        down: Bool,
                        holdDurationMilliseconds: Double) -> TouchIDGuardVerdict {
        guard down else { return .released }
        let heldMilliseconds = elapsedSinceEventMilliseconds + pressToEventDelayMilliseconds
        return heldMilliseconds >= sanitizedHoldDuration(holdDurationMilliseconds) ? .reached : .waiting
    }

    /// Longest the poll can run: the wait left after the event plus a margin.
    static func pollBudgetMilliseconds(holdDurationMilliseconds: Double) -> Double {
        max(0, sanitizedHoldDuration(holdDurationMilliseconds) - pressToEventDelayMilliseconds)
            + 4 * pollIntervalMilliseconds
    }
}
