// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The wake volume ceiling, pinned by behaviour: it only ever moves the level
/// down, never up, never off mute, and no corrupt stored value may come out
/// as silence. The decision functions take plain values, so the scratch
/// domain below only proves the sanitizer works on values as actually stored.
enum WakeVolumeCapTests {
    static func run(_ suite: TestSuite) {
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 80,
                                                       ceilingPercent: 50,
                                                       isMuted: true) == nil,
                     "a muted output stays muted: the cap never unmutes")
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 50,
                                                       ceilingPercent: 50,
                                                       isMuted: true) == nil,
                     "mute wins even when the level sits exactly at the ceiling")
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 30,
                                                       ceilingPercent: 50,
                                                       isMuted: false) == nil,
                     "a level already below the ceiling is left untouched")
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 50,
                                                       ceilingPercent: 50,
                                                       isMuted: false) == nil,
                     "a level exactly at the ceiling is left untouched, never re-aimed")
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 80,
                                                       ceilingPercent: 50,
                                                       isMuted: false) == 50,
                     "a level above the ceiling comes down to exactly the ceiling")
        suite.expect(WakeVolumeCapSupport.cappedVolume(
                        currentPercent: 80,
                        ceilingPercent: Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
                        isMuted: false) == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
                     "a ceiling exactly at the audible floor still caps")
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 80,
                                                       ceilingPercent: 0,
                                                       isMuted: false) == nil,
                     "a stored ceiling of zero declines instead of silencing the speakers")
        suite.expect(WakeVolumeCapSupport.cappedVolume(
                        currentPercent: 80,
                        ceilingPercent: Defaults.minimumMixerHeadphonesDisconnectVolumePercent - 1,
                        isMuted: false) == nil,
                     "a below-floor ceiling declines instead of writing a near-silent level")
        suite.expect(WakeVolumeCapSupport.cappedVolume(currentPercent: 80,
                                                       ceilingPercent: 120,
                                                       isMuted: false) == nil,
                     "a ceiling past full scale declines instead of raising the volume")
        suite.expect(WakeVolumeCapSupport.sanitizedCeilingPercent(40) == 40,
                     "a valid stored ceiling passes through unchanged")
        suite.expect(WakeVolumeCapSupport.sanitizedCeilingPercent(0)
                        == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
                     "a stored zero sanitizes to the audible floor, never to silence")
        suite.expect(WakeVolumeCapSupport.sanitizedCeilingPercent(-20)
                        == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
                     "a negative stored ceiling sanitizes to the audible floor")
        for junk in [Double.nan, Double.infinity, -Double.infinity] {
            suite.expect(WakeVolumeCapSupport.sanitizedCeilingPercent(junk)
                            == Defaults.defaultMixerWakeVolumeCapPercent,
                         "a non-finite stored ceiling falls back to the default")
        }
        suite.expect(WakeVolumeCapSupport.sanitizedCeilingPercent(150) == 100,
                     "a stored ceiling past full scale stops at 100")
        let domain = "vorssaint.tests.wake-volume-cap"
        if let scratch = UserDefaults(suiteName: domain) {
            scratch.removePersistentDomain(forName: domain)
            scratch.set(80.0, forKey: "ceiling")
            let decided = WakeVolumeCapSupport.cappedVolume(
                currentPercent: 90,
                ceilingPercent: WakeVolumeCapSupport.sanitizedCeilingPercent(
                    scratch.double(forKey: "ceiling")),
                isMuted: false)
            suite.expect(decided == 80,
                         "a ceiling round-tripped through stored defaults still caps")
            scratch.removePersistentDomain(forName: domain)
        } else {
            suite.expect(false, "a throwaway defaults domain is available")
        }
    }
}
