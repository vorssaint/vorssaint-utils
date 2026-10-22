// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Behaviour of the mute-while-typing policy: when the mic stays shut, when
/// it opens again, and that a microphone the user muted is never touched.
enum MicMuteWhileTypingTests {
    static func run(_ suite: TestSuite) {
        // No microphone, nothing to mute: the request is dropped, never kept as pending.
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: true, idleSeconds: 0,
                                                           unmuteDelay: 2, micInUse: false),
                     "typing with no microphone mutes nothing")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: 0,
                                                           unmuteDelay: 2, micInUse: false),
                     "idling with no microphone mutes nothing")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: true, idleSeconds: 0,
                                                           unmuteDelay: -1, micInUse: false),
                     "a bad delay with no microphone still mutes nothing")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: 30,
                                                           unmuteDelay: 2, micInUse: false),
                     "a long idleness with no microphone mutes nothing")
        // Typing mutes while a microphone is in use, whatever the idle reading says.
        suite.expect(MicMuteWhileTypingSupport.shouldMute(typing: true, idleSeconds: 0,
                                                          unmuteDelay: 2, micInUse: true),
                     "typing mutes while a microphone is in use")
        suite.expect(MicMuteWhileTypingSupport.shouldMute(typing: true, idleSeconds: 0.4,
                                                          unmuteDelay: 1, micInUse: true),
                     "typing still mutes when the idle reading lags behind the keypress")
        // Letting go keeps the mute through the gaps inside a phrase, then releases.
        suite.expect(MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: 0,
                                                          unmuteDelay: 2, micInUse: true),
                     "stopping typing stays muted inside the debounce window")
        suite.expect(MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: 1.9,
                                                          unmuteDelay: 2, micInUse: true),
                     "idling just inside the window stays muted")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: 2,
                                                           unmuteDelay: 2, micInUse: true),
                     "the window ends exactly at the delay, not after it")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: 5,
                                                           unmuteDelay: 2, micInUse: true),
                     "idling past the window releases the mic")
        // A corrupt stored delay fails open, even mid-burst: never mute forever.
        for delay in [0.0, -2.0, Double.nan, Double.infinity] {
            suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: true, idleSeconds: 0,
                                                               unmuteDelay: delay, micInUse: true),
                         "a stored delay of \(delay) does not mute forever")
        }
        // A nonsense idle measurement reads as not typing, never as a reason to hold the mute.
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: -1,
                                                           unmuteDelay: 2, micInUse: true),
                     "a negative idle reading releases instead of holding the mute")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: true, idleSeconds: -1,
                                                           unmuteDelay: 2, micInUse: true),
                     "a negative idle reading fails open even when flagged as typing")
        suite.expect(!MicMuteWhileTypingSupport.shouldMute(typing: false, idleSeconds: Double.nan,
                                                           unmuteDelay: 2, micInUse: true),
                     "an unreadable idle measurement releases instead of holding the mute")
        // Ownership: a microphone the user muted is neither adopted nor released.
        suite.expect(!MicMuteWhileTypingSupport.shouldClaimMutedMic(isMuted: true),
                     "a burst never adopts a mute the user already holds")
        suite.expect(MicMuteWhileTypingSupport.shouldClaimMutedMic(isMuted: false),
                     "a burst may claim the mute when the mic is open")
        suite.expect(MicMuteWhileTypingSupport.shouldReleaseMic(mutedByTyping: true),
                     "the burst that muted releases the mic when typing stops")
        suite.expect(!MicMuteWhileTypingSupport.shouldReleaseMic(mutedByTyping: false),
                     "anything the burst did not mute stays exactly as it was")
        // The sanitizer turns stored garbage into a waitable delay.
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(0)
                        == MicMuteWhileTypingSupport.defaultUnmuteDelay,
                     "a stored zero falls back to the default wait")
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(-3)
                        == MicMuteWhileTypingSupport.defaultUnmuteDelay,
                     "a stored negative falls back to the default wait")
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(Double.nan)
                        == MicMuteWhileTypingSupport.defaultUnmuteDelay,
                     "a stored NaN falls back to the default wait")
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(Double.infinity)
                        == MicMuteWhileTypingSupport.defaultUnmuteDelay,
                     "a stored infinity falls back to the default wait")
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(2) == 2,
                     "a sane stored delay is kept as it is")
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(0.1)
                        == MicMuteWhileTypingSupport.minimumUnmuteDelay,
                     "a vanishingly short wait is pulled up into the debounce range")
        suite.expect(MicMuteWhileTypingSupport.sanitizedUnmuteDelay(3600)
                        == MicMuteWhileTypingSupport.maximumUnmuteDelay,
                     "an hours-long wait is pulled down into the debounce range")
        // The idle clamp turns clock nonsense into "just typed".
        suite.expect(MicMuteWhileTypingSupport.clampedIdleSeconds(-5) == 0,
                     "a negative idle reading clamps to just typed")
        suite.expect(MicMuteWhileTypingSupport.clampedIdleSeconds(Double.nan) == 0,
                     "an unreadable idle measurement clamps to just typed")
        suite.expect(MicMuteWhileTypingSupport.clampedIdleSeconds(1.5) == 1.5,
                     "a sane idle measurement passes through untouched")
        // Whatever a preference domain hands back, the wait stays finite and positive.
        let domain = "com.vorssaint.tests.mic-mute-while-typing"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for raw in [-3.0, 0.0, Double.nan, Double.infinity, 0.4, 2.0, 3600.0] {
            defaults.set(raw, forKey: "unmuteDelay")
            let wait = MicMuteWhileTypingSupport.sanitizedUnmuteDelay(defaults.double(forKey: "unmuteDelay"))
            suite.expect(wait.isFinite && wait > 0,
                         "stored garbage of \(raw) still sanitizes to a waitable delay")
        }
    }
}
