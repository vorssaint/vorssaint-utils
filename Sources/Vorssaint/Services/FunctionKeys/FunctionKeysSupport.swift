// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics

/// Decides what a press of the special keys on the top row of an Apple
/// keyboard does. Pure, so the choice can be tested without a tap or a
/// keyboard: the service only feeds it what the event says and acts on the
/// answer.
///
/// On a Mac keyboard the Spotlight key (F4), the dictation key (F5) and the Do
/// Not Disturb key (F6) arrive as ordinary key events with their own key codes,
/// not as media keys.
/// F8 (Play/Pause) is a media key, and the music-app block already covers what
/// it does when nothing is playing, so it is not handled here.
enum FunctionKeysSupport {
    /// The key code the Spotlight key sends (F4).
    static let spotlightKeyCode: Int64 = 177
    /// The key code the dictation key sends (F5).
    static let dictationKeyCode: Int64 = 176
    /// The key code the Do Not Disturb key sends (F6).
    static let doNotDisturbKeyCode: Int64 = 178

    enum Key: Equatable {
        case spotlight
        case dictation
        case doNotDisturb

        init?(keyCode: Int64) {
            switch keyCode {
            case FunctionKeysSupport.spotlightKeyCode: self = .spotlight
            case FunctionKeysSupport.dictationKeyCode: self = .dictation
            case FunctionKeysSupport.doNotDisturbKeyCode: self = .doNotDisturb
            default: return nil
            }
        }
    }

    enum Action: Equatable {
        case findInFrontApp
        case toggleMicrophone
        case sleepSystem
    }

    /// What the person has switched on, and whether the microphone control
    /// the first action drives is itself installed.
    struct Configuration: Equatable {
        var micMuteEnabled: Bool
        var sleepEnabled: Bool
        var microphoneMuteAvailable: Bool
        var findEnabled = false

        static let off = Configuration(micMuteEnabled: false, sleepEnabled: false,
                                       microphoneMuteAvailable: false)

        /// Whether any key is taken, which is what decides if a tap runs at all.
        var wantsTap: Bool {
            action(for: .spotlight) != nil || action(for: .dictation) != nil || action(for: .doNotDisturb) != nil
        }

        func action(for key: Key) -> Action? {
            switch key {
            case .spotlight: return findEnabled ? .findInFrontApp : nil
            case .dictation: return micMuteEnabled && microphoneMuteAvailable ? .toggleMicrophone : nil
            case .doNotDisturb: return sleepEnabled ? .sleepSystem : nil
            }
        }
    }

    enum Decision: Equatable {
        /// Not ours: the event goes on to the system untouched.
        case passThrough
        /// Ours, but nothing to do now (a key held down, or its release): the
        /// system must still not see it, or the dictation prompt would open
        /// on the repeat.
        case swallow
        /// Ours, and this is the press that does the work.
        case perform(Action)
    }

    /// `hasModifiers` is whether Command, Control, Option or Shift is held.
    /// Those combinations belong to the system (Command-F5 is VoiceOver) and
    /// to other shortcuts, so they are never taken.
    static func decision(keyCode: Int64, isKeyDown: Bool, isAutoRepeat: Bool, hasModifiers: Bool,
                         configuration: Configuration) -> Decision {
        guard let key = Key(keyCode: keyCode), !hasModifiers,
              let action = configuration.action(for: key) else { return .passThrough }
        return isKeyDown && !isAutoRepeat ? .perform(action) : .swallow
    }

    /// The modifiers that make a press somebody else's shortcut. Fn alone is
    /// how these keys are sent on a keyboard with the function row reversed,
    /// so it does not count.
    static let shortcutModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    /// The key code of F in an ANSI layout, and the shortcut the Spotlight key
    /// presses with it: Command-F, the Find of whatever app is in front.
    static let findKeyCode: CGKeyCode = 3
    static let findShortcutFlags: CGEventFlags = .maskCommand
}
