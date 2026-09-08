// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum MusicLaunchTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Music launch blocker

        func musicKeyData(keyCode: Int, state: Int = 10, repeatFlag: Bool = false) -> Int {
            Int((UInt32(keyCode) << 16) | (UInt32(state) << 8) | (repeatFlag ? 1 : 0))
        }
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode))),
               "play/pause arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.nextTrackKeyCode))),
               "next track arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.previousTrackKeyCode))),
               "previous track arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.fastForwardKeyCode))),
               "fast-forward arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.rewindKeyCode))),
               "rewind arms the music-app blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode), state: 11)),
               "a media-key release does not arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode), repeatFlag: true)),
               "auto-repeat does not re-arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: 0)),
               "volume keys do not arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: 2)),
               "brightness keys do not arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(subtype: 1, data1: musicKeyData(keyCode: 16)),
               "other system-defined subtypes do not arm the blocker")
        expect(!MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: nil),
               "without a recent media key the music app may open")
        expect(MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: 9.5),
               "a launch in the arm window after a media key is blocked")
        expect(MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: 8.0),
               "a launch on the arm-window edge is still blocked")
        expect(!MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: 7.9),
               "a launch after the arm window is left alone")
    }
}
