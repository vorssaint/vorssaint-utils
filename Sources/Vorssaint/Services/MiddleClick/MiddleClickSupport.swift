// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// What to do with an incoming physical trackpad press.
enum MiddleClickClickAction: Equatable {
    case transform
    case passThrough
    /// A second synthesized click right on the heels of a transformed one
    /// (tap-to-click fires an extra click as the fingers release): passing it
    /// through would open in the same tab, transforming it would open a
    /// second tab, so it is dropped.
    case swallow
}

/// A key that can be held through a click to make it a middle click. All of
/// them are read from the click's own flags, so nothing watches the keyboard.
/// The raw values are the tokens saved in preferences.
enum MiddleClickKey: String, CaseIterable {
    case fn, control, option, shift, command

    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .control: return .maskControl
        case .option: return .maskAlternate
        case .shift: return .maskShift
        case .command: return .maskCommand
        }
    }

    var symbol: String {
        switch self {
        case .fn: return "fn"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        case .command: return "⌘"
        }
    }

    var name: String {
        switch self {
        case .fn: return "Function"
        case .control: return "Control"
        case .option: return "Option"
        case .shift: return "Shift"
        case .command: return "Command"
        }
    }
}

/// What the preferences arm. `keys` is empty while key + click is off.
struct MiddleClickTriggers: Equatable {
    let threeFinger: Bool
    let keys: CGEventFlags

    var anyOn: Bool { threeFinger || !keys.isEmpty }
}

enum MiddleClickSupport {
    /// How recent the last contact frame must be for its finger count to
    /// describe "now". Frames stream continuously while fingers touch the
    /// trackpad, so anything older means the fingers already lifted.
    static let fingerFreshness: TimeInterval = 0.25

    /// The fingers must have been resting this long before the press: a
    /// click that arrives together with the last finger's touchdown is a
    /// synthesized tap-to-click, not a press (a real press needs the fingers
    /// on the pad before the force builds up).
    static let minimumSettle: TimeInterval = 0.04

    /// Window after a transformed click in which another qualifying click is
    /// treated as a synthesizer bounce and dropped.
    static let repeatGuard: TimeInterval = 0.30

    /// Decides what an incoming press becomes. Only real presses count
    /// (owner decision: taps, swipes and resting fingers must never click),
    /// and while the system's own three-finger drag gesture is enabled it
    /// owns three-finger touches: it synthesizes clicks from unpressed
    /// contact that are indistinguishable from real presses here, so the
    /// press moves to four fingers, as the tap does (issue #2061). A key +
    /// click is a deliberate chord, not a touch to interpret, so it skips all
    /// of that: finger counts say nothing about a mouse, and two quick ones
    /// are a real double click rather than a synthesizer bounce.
    static func actionForClick(fingerCount: Int,
                               frameAge: TimeInterval,
                               settledFor: TimeInterval,
                               sinceLastTransformEnd: TimeInterval?,
                               systemDragGestureEnabled: Bool,
                               keyClick: Bool = false,
                               fingerPressOn: Bool = true) -> MiddleClickClickAction {
        if keyClick { return .transform }
        guard fingerPressOn else { return .passThrough }
        let pressFingers = systemDragGestureEnabled ? 4 : 3
        guard fingerCount == pressFingers, frameAge >= 0, frameAge <= fingerFreshness else {
            return .passThrough
        }
        if let sinceLastTransformEnd, sinceLastTransformEnd >= 0,
           sinceLastTransformEnd < repeatGuard {
            return .swallow
        }
        guard settledFor >= minimumSettle else { return .passThrough }
        return .transform
    }

    // MARK: - Key + click (opt-in)

    static let defaultClickKeysStorageValue = MiddleClickKey.fn.rawValue

    /// The keys a chord is made of. Caps Lock and the like are not part of
    /// it, so they can be in any state during a key + click.
    static let clickKeyMask: CGEventFlags = [.maskSecondaryFn, .maskControl, .maskAlternate,
                                             .maskShift, .maskCommand]

    /// A chord needs a key besides Shift, which alone would take over every
    /// range selection; the window gesture modifiers follow the same rule.
    static func isValidClickChord(_ keys: CGEventFlags) -> Bool {
        !keys.intersection(clickKeyMask).subtracting(.maskShift).isEmpty
    }

    /// The chord saved as tokens like "control+option". Anything unreadable
    /// falls back to fn.
    static func clickKeys(from storedValue: String?) -> CGEventFlags {
        let fallback = MiddleClickKey.fn.flag
        guard let storedValue else { return fallback }
        var keys: CGEventFlags = []
        for token in storedValue.split(separator: "+", omittingEmptySubsequences: false) {
            guard let key = MiddleClickKey(rawValue: String(token)) else { return fallback }
            keys.insert(key.flag)
        }
        return isValidClickChord(keys) ? keys : fallback
    }

    static func storageValue(forClickKeys keys: CGEventFlags) -> String {
        MiddleClickKey.allCases.filter { keys.contains($0.flag) }
            .map(\.rawValue).joined(separator: "+")
    }

    /// The chord with one key flipped, or nil when that would leave no valid
    /// chord: the picker keeps the last deliberate key selected.
    static func togglingClickKey(_ key: MiddleClickKey, in keys: CGEventFlags) -> CGEventFlags? {
        let next = keys.symmetricDifference(key.flag)
        return isValidClickChord(next) ? next : nil
    }

    /// Whether a press is a key + click: the primary button with exactly the
    /// chosen keys held. Exactly, as window gestures match, so a chord of ⌘
    /// does not take over ⌃⌘ click; fn + right click stays a right click.
    static func isKeyClick(type: CGEventType, flags: CGEventFlags, keys: CGEventFlags) -> Bool {
        !keys.isEmpty && type == .leftMouseDown && flags.intersection(clickKeyMask) == keys
    }

    /// Both triggers sit under the feature switch, and either works alone.
    static func triggers(featureOn: Bool, threeFingerOn: Bool, keyClickOn: Bool,
                         storedKeys: String?) -> MiddleClickTriggers {
        MiddleClickTriggers(threeFinger: featureOn && threeFingerOn,
                            keys: featureOn && keyClickOn ? clickKeys(from: storedKeys) : [])
    }

    /// Rewrites the event in place: same position, timestamp and modifiers,
    /// but a middle-button event instead of its native button. A chord is
    /// dropped: it asked for the middle click, so apps should not see it as
    /// modifiers on one.
    static func asMiddle(_ event: CGEvent, type: CGEventType, dropping keys: CGEventFlags) -> CGEvent {
        event.type = type
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.flags.subtract(keys)
        return event
    }

    // MARK: - Tap to middle click (issue #161, opt-in)

    /// A touch that lasts longer than this is a rest or a press, not a tap.
    static let tapMaxDuration: TimeInterval = 0.35

    /// How far the fingers' average position may travel (normalized trackpad
    /// units, 0...1 across the pad) before the touch counts as a swipe. Space
    /// switching and Mission Control travel far past this.
    static let tapMovementLimit: Float = 0.03

    /// How much the fingers' spread (mean distance from their centroid) may
    /// change before the touch counts as a pinch. A pinch or spread keeps the
    /// centroid still, so the movement limit alone would let Launchpad and
    /// show-desktop gestures fire a phantom middle click.
    static let tapSpreadChangeLimit: Float = 0.04

    /// Briefly ignore tap candidates after ordinary typing so incidental
    /// trackpad contact cannot move focus while the user is entering text.
    static let tapKeyboardIdle: TimeInterval = 0.5

    /// Decides whether a finished touch was a deliberate tap. `tapFingers` is
    /// the user's chosen count (3 or 4); with the system three-finger drag
    /// gesture enabled a three-finger tap belongs to macOS, so only the
    /// four-finger option stays available.
    static func tapShouldFire(duration: TimeInterval,
                              maxMovement: Float,
                              maxSpreadChange: Float,
                              exceededFingerCount: Bool,
                              buttonPressedDuring: Bool,
                              positionUnavailable: Bool,
                              systemDragGestureEnabled: Bool,
                              tapFingers: Int,
                              secondsSinceLastKeyDown: TimeInterval = .infinity) -> Bool {
        guard tapFingers == 3 || tapFingers == 4 else { return false }
        guard !exceededFingerCount, !buttonPressedDuring, !positionUnavailable else { return false }
        guard secondsSinceLastKeyDown >= tapKeyboardIdle else { return false }
        guard duration > 0, duration <= tapMaxDuration else { return false }
        guard maxMovement <= tapMovementLimit else { return false }
        guard maxSpreadChange <= tapSpreadChangeLimit else { return false }
        if tapFingers == 3, systemDragGestureEnabled { return false }
        return true
    }

    /// The finger count whose tap opens the radial menu, or 0 for none. Only
    /// four fingers: macOS keeps no gesture of its own there, while three
    /// belong to Look Up and three-finger drag. A middle click already set to
    /// four fingers keeps them, so turning this on never changes it.
    static func radialMenuTapFingers(radialMenuWantsTap: Bool, middleClickTapFingers: Int) -> Int {
        radialMenuWantsTap && middleClickTapFingers != 4 ? 4 : 0
    }
}
