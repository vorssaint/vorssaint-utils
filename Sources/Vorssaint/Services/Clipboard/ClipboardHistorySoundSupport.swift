// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Pure decisions and system-sound playback for clipboard history feedback
/// (issue #1340). Success events use the well-known `Pop` alert from
/// `/System/Library/Sounds`. Failures use `Basso` so they stay distinct from
/// Pop and from the generic `NSSound.beep()` the Command Bar used to fire on
/// history paste/copy failures — that path now calls the gated failure helper
/// instead, so preference-off stays quiet and preference-on never double-beeps.
/// All three preferences default off so existing installs stay quiet.
enum ClipboardHistorySoundSupport {
    static let successSoundName = "Pop"
    static let failureSoundName = "Basso"
    static let defaultEnabled = false

    static func shouldPlayOnCapture(preferenceEnabled: Bool) -> Bool {
        preferenceEnabled
    }

    static func shouldPlayOnPaste(preferenceEnabled: Bool, succeeded: Bool) -> Bool {
        preferenceEnabled && succeeded
    }

    /// `alreadySignaled` covers callers that still use `NSSound.beep()` for a
    /// non-clipboard reason (AX prompt, secure input, etc.); those keep their
    /// own beep and must not also play Basso.
    static func shouldPlayOnFailure(preferenceEnabled: Bool,
                                    alreadySignaled: Bool) -> Bool {
        preferenceEnabled && !alreadySignaled
    }

    static func successSound() -> NSSound? {
        NSSound(named: NSSound.Name(successSoundName))
    }

    static func failureSound() -> NSSound? {
        NSSound(named: NSSound.Name(failureSoundName))
    }

    /// Plays `Pop` when `shouldPlay` is true. Returns whether playback started.
    @discardableResult
    static func playSuccessIfNeeded(_ shouldPlay: Bool) -> Bool {
        guard shouldPlay, let sound = successSound() else { return false }
        return sound.play()
    }

    /// Plays `Basso` when `shouldPlay` is true. Returns whether playback started.
    @discardableResult
    static func playFailureIfNeeded(_ shouldPlay: Bool) -> Bool {
        guard shouldPlay, let sound = failureSound() else { return false }
        return sound.play()
    }

    static func preferenceEnabled(forKey key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultEnabled
    }

    static func playCaptureIfNeeded() {
        playSuccessIfNeeded(
            shouldPlayOnCapture(
                preferenceEnabled: preferenceEnabled(forKey: DefaultsKey.clipboardHistorySoundOnCapture)))
    }

    static func playPasteOutcomeIfNeeded(succeeded: Bool) {
        if succeeded {
            playSuccessIfNeeded(
                shouldPlayOnPaste(
                    preferenceEnabled: preferenceEnabled(forKey: DefaultsKey.clipboardHistorySoundOnPaste),
                    succeeded: true))
        } else {
            playFailureIfNeeded(
                shouldPlayOnFailure(
                    preferenceEnabled: preferenceEnabled(forKey: DefaultsKey.clipboardHistorySoundOnFailure),
                    alreadySignaled: false))
        }
    }

    static func playFailureIfNeeded(alreadySignaled: Bool = false) {
        playFailureIfNeeded(
            shouldPlayOnFailure(
                preferenceEnabled: preferenceEnabled(forKey: DefaultsKey.clipboardHistorySoundOnFailure),
                alreadySignaled: alreadySignaled))
    }
}
