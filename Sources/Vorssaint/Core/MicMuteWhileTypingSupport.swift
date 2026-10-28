// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind muting the microphone while the user types, kept
/// apart from the event monitor and the audio calls so they can be pinned
/// down by tests: when typing owns the mute, how long quiet must last before
/// it lets go, and which stored values are safe to wait on.
enum MicMuteWhileTypingSupport {
    /// How long after the last keypress the mic stays muted when nothing usable is stored.
    static let defaultUnmuteDelay: TimeInterval = 2
    /// The shortest wait worth calling a debounce, and the longest one that
    /// still reads as "after typing" rather than a forgotten mute.
    static let minimumUnmuteDelay: TimeInterval = 0.5
    static let maximumUnmuteDelay: TimeInterval = 30

    /// Whether the mic should be muted right now. Pure: no I/O, no clock reads.
    /// Callers pass `typing: true` only for the keypress itself, with
    /// `idleSeconds` at zero; the quiet spell after is `typing: false` with
    /// the measured gap.
    ///
    /// No microphone means nothing to mute, and the request is dropped rather
    /// than recorded as pending. A corrupt stored delay or a nonsense idle
    /// measurement fails open: the mic stays as the user left it instead of
    /// muting until something it cannot observe changes.
    static func shouldMute(typing: Bool,
                           idleSeconds: TimeInterval,
                           unmuteDelay: TimeInterval,
                           micInUse: Bool) -> Bool {
        guard micInUse else { return false }
        guard unmuteDelay.isFinite && unmuteDelay > 0 else { return false }
        guard idleSeconds.isFinite && idleSeconds >= 0 else { return false }
        // A keypress reads as an idle of zero: typing always mutes, and a
        // quiet spell holds the mute only while it is shorter than the wait.
        if typing { return true }
        return idleSeconds < unmuteDelay
    }

    /// Whether a new typing burst may claim the mute. A microphone the user
    /// muted themselves is never adopted: the burst leaves it exactly as it
    /// found it, and nothing later releases it.
    static func shouldClaimMutedMic(isMuted: Bool) -> Bool {
        !isMuted
    }

    /// Whether the debounce expiry may open the mic again. Only the burst
    /// that muted it may release it.
    static func shouldReleaseMic(mutedByTyping: Bool) -> Bool {
        mutedByTyping
    }

    /// A stored unmute delay turned into one safe to wait on. Anything that is
    /// not a positive, finite number of seconds falls back to the default, and
    /// anything outside the debounce range is pulled back into it.
    static func sanitizedUnmuteDelay(_ delay: TimeInterval) -> TimeInterval {
        guard delay.isFinite && delay > 0 else { return defaultUnmuteDelay }
        return min(max(delay, minimumUnmuteDelay), maximumUnmuteDelay)
    }

    /// A raw idle measurement turned into one safe to compare: the clock only
    /// moves forward, so anything else reads as "just typed".
    static func clampedIdleSeconds(_ idleSeconds: TimeInterval) -> TimeInterval {
        guard idleSeconds.isFinite && idleSeconds >= 0 else { return 0 }
        return idleSeconds
    }
}
