// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The decisions behind switching input sources with a tap of the Fn/🌐 key,
/// kept apart from the tap so every press order can be walked without a
/// keyboard.
///
/// The approach follows LangSwitch by Anton Nikeev (MIT): a short press of Fn
/// on its own selects the next enabled source when the key comes back up.
/// LangSwitch watches only the Fn key's own modifier events, so a quick Fn+F
/// or Fn+Delete could switch too; here every key, click and other modifier
/// pressed while Fn is down cancels the press.
enum FnInputSourceSupport {
    /// The Fn/🌐 key, `kVK_Function`. It only ever arrives as a modifier change.
    static let fnKeyCode: Int64 = 63

    /// A press at least this long is a hold and switches nothing on release.
    /// It only tells a tap from a press that never became a chord: chords are
    /// recognized by the other input itself. LangSwitch has used the same
    /// limit for years.
    static let tapLimitNanoseconds: UInt64 = 200_000_000

    /// `NX_SYSDEFINED`: media, brightness and other special keys.
    static let systemDefinedEventTypeRawValue: UInt32 = 14

    /// What one event at the tap means for a tap of Fn.
    enum Reading: Equatable {
        /// The physical Fn key went down or came up.
        case fnDown
        case fnUp
        /// A key or another modifier: whatever Fn press is under way became
        /// a chord.
        case otherInput
        /// Nothing that touches the keyboard: the tap's own notices.
        case unrelated
    }

    static func reading(type: CGEventType, keyCode: Int64, flags: CGEventFlags,
                        isOwnEvent: Bool) -> Reading {
        switch type {
        case .flagsChanged:
            // The app's own posted events never start or finish a tap, but
            // they still end one: a key this app types stands for a press.
            guard keyCode == fnKeyCode, !isOwnEvent else { return .otherInput }
            return flags.contains(.maskSecondaryFn) ? .fnDown : .fnUp
        case .keyDown, .keyUp:
            return .otherInput
        default:
            return type.rawValue == systemDefinedEventTypeRawValue ? .otherInput : .unrelated
        }
    }

    /// Modifiers that make a press of Fn part of a chord. Caps Lock is a
    /// state rather than a held key, so a tap with Caps Lock already on
    /// still counts.
    static let chordModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]

    /// The keys the tap saw go down and not come up yet, for telling whether
    /// another key is held when Fn goes down or up.
    ///
    /// The system's key state alone cannot say that: Caps Lock reads down for
    /// as long as its lock is on, and a keyboard can leave a code down at
    /// rest (127 on a built-in MacBook keyboard, found in review). A key
    /// counts only while both agree, so such a code never blocks a tap, and a
    /// release the tap missed clears itself the next time the system says
    /// the key is up. A key already down before the tap started is not seen.
    struct PressedKeys: Equatable {
        private(set) var codes: Set<Int64> = []

        mutating func note(type: CGEventType, keyCode: Int64) {
            switch type {
            case .keyDown: codes.insert(keyCode)
            case .keyUp: codes.remove(keyCode)
            default: break
            }
        }

        mutating func reset() {
            codes = []
        }

        /// Whether a key besides Fn is held now, dropping every one the
        /// system no longer reports down.
        mutating func anyHeld(isKeyDown: (CGKeyCode) -> Bool) -> Bool {
            codes = codes.filter { code in
                code != FnInputSourceSupport.fnKeyCode
                    && CGKeyCode(exactly: code).map(isKeyDown) == true
            }
            return !codes.isEmpty
        }
    }

    /// Whether the press of Fn is part of a chord at the moment of `flags`:
    /// a chord modifier is down, or `keyHeld` says another key is.
    static func otherInputHeld(flags: CGEventFlags, keyHeld: Bool) -> Bool {
        keyHeld || !flags.intersection(chordModifiers).isEmpty
    }

    /// Recognizes one solo tap of Fn at a time.
    ///
    /// Besides the events it is fed, each Fn transition carries `activity`, a
    /// running count of key presses and clicks the window server has seen.
    /// The count also moves for a press another tap in front of this one
    /// swallowed, and for a click, which the tap does not watch, so a chord
    /// the tap never saw still cancels the tap.
    struct Recognizer: Equatable {
        enum Event: Equatable {
            case fnDown(timestamp: UInt64, otherInputHeld: Bool, activity: UInt64)
            case fnUp(timestamp: UInt64, otherInputHeld: Bool, activity: UInt64)
            case otherInput
            /// The event stream broke off: the tap stopped, was disabled or
            /// missed events, or the Mac went to sleep. A tap is only
            /// recognized again from a fresh press.
            case interrupted
        }

        private struct Press: Equatable {
            let timestamp: UInt64
            let activity: UInt64
        }

        private var fnIsDown = false
        /// The press that can still become a tap; nil once it cannot.
        private var candidate: Press?

        /// Feeds one event and answers whether it completed a tap, in which
        /// case the next source is to be selected now.
        mutating func handle(_ event: Event) -> Bool {
            switch event {
            case let .fnDown(timestamp, otherInputHeld, activity):
                // A second down without an up in between means the up was
                // missed; this press starts over on its own.
                fnIsDown = true
                candidate = otherInputHeld ? nil : Press(timestamp: timestamp, activity: activity)
                return false
            case let .fnUp(timestamp, otherInputHeld, activity):
                defer {
                    fnIsDown = false
                    candidate = nil
                }
                guard fnIsDown, let press = candidate, !otherInputHeld,
                      activity == press.activity, timestamp >= press.timestamp
                else { return false }
                return timestamp - press.timestamp < FnInputSourceSupport.tapLimitNanoseconds
            case .otherInput:
                // A chord stays a chord even when its other key comes up
                // before Fn does.
                candidate = nil
                return false
            case .interrupted:
                fnIsDown = false
                candidate = nil
                return false
            }
        }
    }

    // MARK: - The system's own Fn action

    /// What macOS does on its own when the 🌐 key is pressed, as the
    /// `AppleFnUsageType` preference of `com.apple.HIToolbox` reads. Anything
    /// but nothing would act on the same press as this feature: a second
    /// switch, the emoji picker or dictation.
    enum SystemAction: Equatable {
        case nothing
        case something
        /// Never chosen on this Mac, so the system default applies, which
        /// is not "Do Nothing".
        case systemDefault
    }

    static let systemPreferencesDomain = "com.apple.HIToolbox"
    static let systemPreferenceKey = "AppleFnUsageType"

    static func systemAction(raw: Any?) -> SystemAction {
        guard let number = raw as? NSNumber else { return .systemDefault }
        return number.intValue == 0 ? .nothing : .something
    }
}
