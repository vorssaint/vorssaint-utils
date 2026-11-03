// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// The per-app F-row translation (issue #1227): the pure half, every keycode
/// table and every routing decision, with no event tap of its own. The tap
/// lives in `FunctionKeyTap` and the lifecycle in `FnLockService`.
///
/// macOS decides F1-F12 by one global checkbox, "Use F1, F2, etc. keys as
/// standard function keys", and applies it below every app. The feature
/// flips the row per app instead, by translating whatever form the pressed
/// key arrives in:
///
/// - System setting off (the default; media actions win): a listed app gets
///   real function keys. Both delivery forms are translated: the media
///   keycodes some keyboards post as plain presses, and the NX system-
///   defined ids the built-in row posts instead.
/// - System setting on (function keys win): a listed app gets the media
///   actions instead, the reverse list.
enum FnLockSupport {
    /// The function row this feature covers, in row order.
    static let functionRowKeyCodes: [Int] = [
        Int(kVK_F1), Int(kVK_F2), Int(kVK_F3), Int(kVK_F4), Int(kVK_F5), Int(kVK_F6),
        Int(kVK_F7), Int(kVK_F8), Int(kVK_F9), Int(kVK_F10), Int(kVK_F11), Int(kVK_F12),
    ]

    /// Key-down form: the media keycodes the row carries as plain key
    /// presses, serving the REVERSE direction (a listed app's function key
    /// rewritten to the media keycode the system acts on). Measured on the
    /// Apple-silicon function row with the development probe (`--fn-probe`,
    /// 2026-10): Mission Control, Spotlight, Dictation and Focus arrive as
    /// key-downs carrying the Fn flag, while brightness and volume arrive as
    /// NX system-defined events instead. Brightness as 144/145 comes from
    /// external keyboards, confirmed by the brightness keys this app already
    /// routes; the forward table below also carries the Intel Launchpad form
    /// (161), which this reverse table leaves out because the Apple-silicon
    /// Spotlight id (177) is the one this Mac acts on.
    static let functionToMediaKeyDown: [Int: Int] = [
        kVK_F1: 145,   // brightness down, external keyboards
        kVK_F2: 144,   // brightness up, external keyboards
        kVK_F3: 160,   // Mission Control
        kVK_F4: 177,   // Spotlight, Apple silicon function row
        kVK_F5: 176,   // Dictation, Apple silicon function row
        kVK_F6: 178,   // Focus / Do Not Disturb, Apple silicon function row
    ]

    /// The forward direction: a media keycode rewritten to the function key.
    /// Spelled out rather than inverted, because F4 has two media forms
    /// (Launchpad 161 on the Intel function row, Spotlight 177 on Apple
    /// silicon) and only the forward table needs to answer both.
    static let mediaKeyDownToFunction: [Int: Int] = [
        145: kVK_F1,   // brightness down, external keyboards
        144: kVK_F2,   // brightness up, external keyboards
        160: kVK_F3,   // Mission Control
        161: kVK_F4,   // Launchpad, Intel function row
        177: kVK_F4,   // Spotlight, Apple silicon function row
        176: kVK_F5,   // Dictation, Apple silicon function row
        178: kVK_F6,   // Focus, Apple silicon function row
    ]

    /// NX system-defined form: the special-key ids (IOKit `NX_KEYTYPE_*`,
    /// carried in the event's data1) the row posts for the keys whose media
    /// actions travel that way. Serving the REVERSE direction: the synthetic
    /// post the Fn-Lock sends when a listed app's function key should act as
    /// a media key. F5 and F6 are absent because the Apple-silicon row posts
    /// them as plain key-downs (176/178, the table above) and an Intel
    /// backlight Mac's own keys arrive as NX 21/22 but go nowhere when posted
    /// back on a Mac without a backlight; the forward table below keeps them
    /// so those presses still translate into function keys.
    static let functionToNXKey: [Int: Int32] = [
        kVK_F1: 3,    // NX_KEYTYPE_BRIGHTNESS_DOWN
        kVK_F2: 2,    // NX_KEYTYPE_BRIGHTNESS_UP
        kVK_F7: 20,   // NX_KEYTYPE_REWIND
        kVK_F8: 16,   // NX_KEYTYPE_PLAY
        kVK_F9: 19,   // NX_KEYTYPE_FAST
        kVK_F10: 7,   // NX_KEYTYPE_MUTE
        kVK_F11: 1,   // NX_KEYTYPE_SOUND_DOWN
        kVK_F12: 0,   // NX_KEYTYPE_SOUND_UP
    ]

    /// The forward direction for the NX form, measured by the probe on this
    /// Mac's row: brightness 3/2, transport 20/16/19, volume 7/1/0, and the
    /// Intel backlight pair 21/22 kept for the Macs that still have those
    /// keys.
    static let nxKeyToFunction: [Int32: Int] = [
        3: kVK_F1,    // NX_KEYTYPE_BRIGHTNESS_DOWN
        2: kVK_F2,    // NX_KEYTYPE_BRIGHTNESS_UP
        22: kVK_F5,   // NX_KEYTYPE_ILLUMINATION_DOWN, Intel backlight rows
        21: kVK_F6,   // NX_KEYTYPE_ILLUMINATION_UP, Intel backlight rows
        20: kVK_F7,   // NX_KEYTYPE_REWIND
        16: kVK_F8,   // NX_KEYTYPE_PLAY
        19: kVK_F9,   // NX_KEYTYPE_FAST
        7: kVK_F10,   // NX_KEYTYPE_MUTE
        1: kVK_F11,   // NX_KEYTYPE_SOUND_DOWN
        0: kVK_F12,   // NX_KEYTYPE_SOUND_UP
    ]

    /// Whether the system's own checkbox is on: F1-F12 are function keys
    /// everywhere unless the Fn key is held. Read from the preference the
    /// Keyboard pane writes to `NSGlobalDomain` as
    /// `com.apple.keyboard.fnState`; an unreadable or absent value means
    /// off, which is the factory default on every Mac.
    static func systemFunctionKeysDefault(read: (String) -> Bool? = {
        UserDefaults.standard.object(forKey: $0) as? Bool
            ?? (UserDefaults.standard.object(forKey: $0) as? Int).map { $0 != 0 }
            ?? false
    }) -> Bool {
        read("com.apple.keyboard.fnState") ?? false
    }

    /// The states an NX system-defined media event carries in data1: a press
    /// and its release, everything else is not a key state at all.
    static let nxKeyDownState = 0x0a
    static let nxKeyUpState = 0x0b

    // MARK: - Key names for the settings page's key test

    /// One side of a translation, in whichever form the key arrived.
    enum KeyRef: Equatable {
        /// A plain key-down keycode, media or function.
        case keyCode(Int)
        /// A system-defined media id.
        case nxKey(Int32)
    }

    /// Apple's own English labels for the row, the ones printed on the keys
    /// and shown in Keyboard system settings. Function-row names are the
    /// same in every locale, so they never localize.
    static func functionKeyName(keyCode: Int) -> String? {
        switch keyCode {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return nil
        }
    }

    static func mediaKeyDownName(keyCode: Int) -> String? {
        switch keyCode {
        case 145: return "Brightness down"
        case 144: return "Brightness up"
        case 160: return "Mission Control"
        case 161: return "Launchpad"
        case 177: return "Spotlight"
        case 176: return "Dictation"
        case 178: return "Focus"
        default: return nil
        }
    }

    static func nxKeyName(nxKey: Int32) -> String? {
        switch nxKey {
        case 3: return "Brightness down"
        case 2: return "Brightness up"
        case 22: return "Keyboard light down"
        case 21: return "Keyboard light up"
        case 20: return "Rewind"
        case 16: return "Play"
        case 19: return "Fast-forward"
        case 7: return "Mute"
        case 1: return "Volume down"
        case 0: return "Volume up"
        default: return nil
        }
    }

    /// "Spotlight (177)" for a named media key, "F4 (118)" for a function
    /// key, "Brightness down (NX 3)" for a system-defined id, so the key
    /// test reads as the pair the user can check against what the app did.
    static func displayName(for ref: KeyRef) -> String {
        switch ref {
        case .keyCode(let keyCode):
            let name = mediaKeyDownName(keyCode: keyCode) ?? functionKeyName(keyCode: keyCode)
            return name.map { "\($0) (\(keyCode))" } ?? "Key \(keyCode)"
        case .nxKey(let nxKey):
            let name = nxKeyName(nxKey: nxKey)
            return name.map { "\($0) (NX \(nxKey))" } ?? "Media \(nxKey)"
        }
    }

    /// What the tap should do with one key-down or key-up event.
    enum KeyAction: Equatable {
        /// Not this feature's key, or the feature did not engage: the event
        /// continues untouched.
        case passThrough
        /// Rewrite the keycode in place. The Fn flag goes on in both
        /// directions: the probe measured every form of this row, media and
        /// function alike, arriving with it set, so a rewritten press is
        /// indistinguishable from the genuine one it stands in for.
        case rewrite(keyCode: Int)
        /// Swallow the press and post the synthetic media event instead
        /// (reverse direction; the system acts on NX ids, not on the
        /// function keycodes).
        case postMediaDown(nxKey: Int32)
        /// Swallow the release of a press handled by `postMediaDown` and
        /// post its synthetic release.
        case postMediaUp(nxKey: Int32)
        /// Swallow with nothing to post: the release of a press this feature
        /// no longer owns, so the system never sees half of one.
        case consume
    }

    /// Routes one key-down/key-up. `systemFunctionKeysDefault` is the
    /// system checkbox as of the last sample; the tables themselves decide
    /// which direction a keycode belongs to, so a stale sample can only
    /// pick the wrong direction, never loop.
    static func keyDownAction(keyCode: Int, isKeyDown: Bool,
                              systemFunctionKeysDefault: Bool) -> KeyAction {
        if systemFunctionKeysDefault {
            // Function keys everywhere: in a listed app, hand the media
            // actions back. Keys whose native form is a plain key press are
            // rewritten in place; the rest are swallowed and posted as the
            // NX ids the system acts on.
            guard let nxKey = functionToNXKey[keyCode] else {
                // F3/F4 (Mission Control, Launchpad) have no NX id; their
                // media form is the plain keycode.
                guard let media = functionToMediaKeyDown[keyCode] else { return .passThrough }
                return .rewrite(keyCode: media)
            }
            return isKeyDown ? .postMediaDown(nxKey: nxKey) : .postMediaUp(nxKey: nxKey)
        }
        // Media actions everywhere: in a listed app, deliver real function
        // keys. The keycode was already rewritten below the tap, so this is
        // an in-place rewrite and the release matches the same table.
        guard let function = mediaKeyDownToFunction[keyCode] else { return .passThrough }
        return .rewrite(keyCode: function)
    }

    /// What the tap should do with one NX system-defined media event.
    enum SystemDefinedAction: Equatable {
        case passThrough
        /// Swallow the NX event and post a synthetic function-key press or
        /// release (forward direction; apps receive function keys, not NX
        /// ids).
        case postFunctionKey(keyCode: Int)
    }

    /// Routes one NX system-defined event. `state` is the raw key state
    /// from data1; only a press and a release are key states.
    static func systemDefinedAction(nxKey: Int32, state: Int,
                                    systemFunctionKeysDefault: Bool) -> SystemDefinedAction {
        // In the reverse direction an NX event already carries the media
        // action the listed app asked for, so it passes: the Fn key held
        // on a function-keys keyboard is how a user asks for one.
        guard !systemFunctionKeysDefault else { return .passThrough }
        guard state == nxKeyDownState || state == nxKeyUpState else { return .passThrough }
        guard let function = nxKeyToFunction[nxKey] else { return .passThrough }
        return .postFunctionKey(keyCode: function)
    }

    /// Guards the theoretical case of one physical press arriving in both
    /// delivery forms: whichever form the tap translated first wins, and a
    /// second translation of the same function key inside the window is
    /// dropped so the app never sees one press twice.
    struct TranslationDedup {
        /// How long after one translation the same function key is held
        /// against a second form of the same press.
        static let window: TimeInterval = 0.08

        private var translatedAt: [Int: TimeInterval] = [:]

        /// True when this function key was translated inside the window.
        func blocks(functionKey: Int, at now: TimeInterval) -> Bool {
            guard let earlier = translatedAt[functionKey] else { return false }
            return now >= earlier && now - earlier < Self.window
        }

        mutating func record(functionKey: Int, at now: TimeInterval) {
            translatedAt[functionKey] = now
        }

        mutating func reset() {
            translatedAt.removeAll()
        }
    }
}

/// The synthetic events the Fn-Lock posts, and the marker that keeps them
/// from being re-translated or re-handled on their way back through the
/// taps. Modeled on `PreciseVolumeKeyEvents`, whose posted media events the
/// volume features already rely on.
enum FnLockKeyEvents {
    /// "FNLK", in the same field the volume roller uses for its own posts.
    static let postedMarker: Int64 = 0x464E4C4B

    static func isPosted(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == postedMarker
    }

    /// A synthetic function-key press or release. Carries the modifiers of
    /// the press it stands for, plus the Fn flag a genuine function key
    /// arrives with, so shortcuts bound to F1-F12 match (issue #401).
    static func functionKeyEvent(keyCode: Int, isKeyDown: Bool, isRepeat: Bool,
                                 flags: CGEventFlags) -> CGEvent? {
        guard let virtualKey = CGKeyCode(exactly: keyCode),
              let event = CGEvent(keyboardEventSource: nil,
                                  virtualKey: virtualKey,
                                  keyDown: isKeyDown) else { return nil }
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        event.setIntegerValueField(.eventSourceUserData, value: postedMarker)
        var pressFlags = flags
        pressFlags.insert(.maskSecondaryFn)
        event.flags = pressFlags
        return event
    }

    /// A synthetic media action in the NX form the system acts on. The
    /// incoming press's modifiers and repeat bit are carried through so a
    /// plain key keeps its normal step, a modified press retains its
    /// behavior, and an autorepeat arrives as a repeat.
    static func mediaEvent(nxKey: Int32, isKeyDown: Bool,
                           flags: CGEventFlags = [], isRepeat: Bool = false) -> CGEvent? {
        let state = isKeyDown ? FnLockSupport.nxKeyDownState : FnLockSupport.nxKeyUpState
        // Carry only the standard modifiers the system-defined event packs
        // alongside the NX state, not the Fn flag or other CG-only bits.
        let carryMask = CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskCommand.rawValue
        let carryFlags = UInt(flags.rawValue & carryMask)
        guard let nsEvent = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8) | carryFlags),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int((nxKey << 16) | Int32(state << 8) | (isRepeat ? 1 : 0)),
            data2: -1),
              let event = nsEvent.cgEvent else { return nil }
        event.setIntegerValueField(.eventSourceUserData, value: postedMarker)
        return event
    }
}
