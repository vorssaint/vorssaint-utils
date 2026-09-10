// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Pure decisions and system-sound playback for Finder cut & paste feedback
/// (issue #962). Finder has no public dedicated cut/paste UI sound — only
/// trash effects under CoreAudio `SystemSounds/finder` — so feedback uses the
/// well-known `Pop` alert from `/System/Library/Sounds`, loadable via
/// `NSSound(named:)`. Preference defaults off so existing installs stay quiet.
enum FinderCutPasteSoundSupport {
    static let systemSoundName = "Pop"
    static let defaultEnabled = false

    static func shouldPlayOnCut(preferenceEnabled: Bool, markedCount: Int) -> Bool {
        preferenceEnabled && markedCount > 0
    }

    static func shouldPlayOnPaste(preferenceEnabled: Bool, movedCount: Int) -> Bool {
        preferenceEnabled && movedCount > 0
    }

    static func systemSound() -> NSSound? {
        NSSound(named: NSSound.Name(systemSoundName))
    }

    /// Plays `Pop` when `shouldPlay` is true. Returns whether playback started.
    @discardableResult
    static func playIfNeeded(_ shouldPlay: Bool) -> Bool {
        guard shouldPlay, let sound = systemSound() else { return false }
        return sound.play()
    }
}
