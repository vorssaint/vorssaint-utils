// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// When the lock screen shows the island's activities, the room it keeps for
/// the system's clock and login controls, and what gives way on a short
/// display. Nothing here locks the Mac or opens a window.
enum NotchLockScreenTests {
    static func run(_ suite: TestSuite) {
        sessionContracts(suite)
        preferenceContracts(suite)
        layoutContracts(suite)
        contentContracts(suite)
        soundContracts(suite)
    }

    static func sessionContracts(_ suite: TestSuite) {
        var locked = NotchSessionState()
        suite.expect(!locked.showsLockScreen, "an unlocked Mac shows nothing over its lock screen")
        locked.locked = true
        suite.expect(locked.showsLockScreen && !locked.canPresent,
                     "locked with the display awake, the lock screen takes over from the island")
        let hidden: [(WritableKeyPath<NotchSessionState, Bool>, String)] = [
            (\.sleeping, "the Mac asleep"), (\.displaysSleeping, "the display asleep"),
            (\.screenSaverRunning, "a screen saver running"),
        ]
        for (change, reason) in hidden {
            var session = locked
            session[keyPath: change] = true
            suite.expect(!session.showsLockScreen, "nothing shows with \(reason)")
        }
        var switched = locked
        switched.onConsole = false
        suite.expect(!switched.showsLockScreen, "nothing shows while another user has the display")
        var saver = NotchSessionState()
        saver.screenSaverRunning = true
        suite.expect(saver.canPresent && saver.canRunTimer, "a screen saver alone leaves the island as it was")
        suite.expect(NotchSessionState().hearsLockChange && locked.hearsLockChange,
                     "a lock or unlock at the keyboard is heard")
        var closing = NotchSessionState()
        closing.sleeping = true
        var dark = NotchSessionState()
        dark.displaysSleeping = true
        suite.expect(!closing.hearsLockChange && !dark.hearsLockChange && !switched.hearsLockChange,
                     "closing the lid, a dark display or a switched user plays no padlock")
        suite.expect(!saver.hearsLockChange, "a lock that follows an idle screen saver plays no padlock")
    }

    static func preferenceContracts(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchLockScreen] as? Bool == false
                     && Defaults.registeredDefaults[DefaultsKey.notchLockSounds] as? Bool == false,
                     "the lock screen and its sounds are both opt-in")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [DefaultsKey.notchLockScreen, DefaultsKey.notchLockSounds]),
                     "settings backups carry the lock screen preferences")
        let domain = "com.vorssaint.tests.notch-lock-screen"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") { defaults.set(value, forKey: key) }
        for (key, value) in AppFeature.availabilityDefaults { defaults.set(value, forKey: key) }
        defaults.set(true, forKey: DefaultsKey.notchLockScreen)
        defaults.set(true, forKey: DefaultsKey.notchLockSounds)
        defaults.set(false, forKey: DefaultsKey.notchEnabled)
        suite.expect(!NotchLockScreenSupport.isEnabled(in: defaults) && !NotchLockScreenSupport.playsSounds(in: defaults),
                     "the island's own switch turns off the lock screen and the sounds")
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        suite.expect(NotchLockScreenSupport.isEnabled(in: defaults) && NotchLockScreenSupport.playsSounds(in: defaults),
                     "with the island on, each follows its own switch")
        defaults.set(false, forKey: DefaultsKey.notchLockScreen)
        suite.expect(!NotchLockScreenSupport.isEnabled(in: defaults) && NotchLockScreenSupport.playsSounds(in: defaults),
                     "the sounds do not need the lock screen")
        suite.expect(NotchLockScreenSupport.showsMusic(in: defaults), "music shows while the island has its Music section")
        defaults.set(NotchIdleContent.none.rawValue, forKey: DefaultsKey.notchIdleContent)
        suite.expect(NotchLockScreenSupport.showsMusic(in: defaults), "an island resting empty still shows music when locked")
        defaults.set(NotchModule.music.rawValue, forKey: DefaultsKey.notchHiddenModules)
        suite.expect(!NotchLockScreenSupport.showsMusic(in: defaults), "hiding the Music section hides the player")
    }

    static func layoutContracts(_ suite: TestSuite) {
        typealias Layout = NotchLockScreenLayout
        // Measured on the lock screen of a 1470 by 956 point display: the
        // clock ends 236 points from the top, the login controls take 218.
        let measured = CGRect(x: 0, y: 0, width: 1470, height: 956)
        if let row = Layout.rowFrame(in: measured), let player = Layout.playerFrame(in: measured) {
            suite.expect(measured.maxY - row.maxY >= 236 + 12 && measured.maxY - row.maxY <= 236 + 30,
                         "the activities read as a line just under the clock")
            suite.expect(player.minY - measured.minY >= 218 + 24, "the player clears the name, picture, password field and hint")
            suite.expect(player.maxY < row.minY && player.height >= 400,
                         "the player has the room between the line and the login controls")
            suite.expect(Layout.paneWidth < Layout.playerWidth, "the pane leaves room around it for the cover's glow")
            suite.expect(abs(row.midX - measured.midX) <= 0.5 && abs(player.midX - measured.midX) <= 0.5,
                         "the line and the player stand centered under the clock")
        } else {
            suite.expect(false, "the measured display has room for the lock screen scene")
        }
        let displays = [
            CGRect(x: 0, y: 0, width: 1280, height: 800), CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 0, y: 0, width: 1728, height: 1117), CGRect(x: 1470, y: -86, width: 1920, height: 1080),
            CGRect(x: -2560, y: 0, width: 2560, height: 1440), CGRect(x: 0, y: 0, width: 3008, height: 1692),
            CGRect(x: 0, y: 1117, width: 1080, height: 1920),
        ]
        for display in displays {
            guard let row = Layout.rowFrame(in: display), let player = Layout.playerFrame(in: display) else {
                suite.expect(false, "a \(Int(display.width))x\(Int(display.height)) display has room for the scene")
                continue
            }
            // A hair under the clock's edge is floating point, not overlap.
            let clock = Layout.clockBottom(screenHeight: display.height) - 0.001
            suite.expect(display.maxY - row.maxY >= clock && player.minY - display.minY == Layout.loginClearance,
                         "the scene keeps the clock's and the login controls' room on \(display)")
            suite.expect(display.contains(row) && display.contains(player) && player.maxY <= row.minY
                         && player.height >= Layout.minimumPlayerHeight,
                         "every part stays on \(display), the player under the line with room to show")
        }
        suite.expect(Layout.playerFrame(in: CGRect(x: 0, y: 0, width: 1024, height: 620)) == nil,
                     "a display too short for the player keeps the lock screen as it is")
        suite.expect(Layout.rowFrame(in: CGRect(x: 0, y: 0, width: 400, height: 956)) == nil
                     && Layout.playerFrame(in: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 956)) == nil,
                     "a narrow or unreadable display keeps the lock screen as it is")
        if let island = Layout.islandFrame(in: measured, cameraWidth: 179, cameraHeight: 32) {
            suite.expect(island.midX == measured.midX && island.maxY == measured.maxY && island.height == 32
                         && island.width == 179 + Layout.islandWing * 2,
                         "the padlock's island hangs from the top, centred on the camera, a wing each side")
        } else {
            suite.expect(false, "a notched display has room for the padlock")
        }
        suite.expect(Layout.islandFrame(in: measured, cameraWidth: 0, cameraHeight: 32) == nil
                     && Layout.islandFrame(in: measured, cameraWidth: 179, cameraHeight: .nan) == nil
                     && Layout.islandFrame(in: measured, cameraWidth: 1460, cameraHeight: 32) == nil,
                     "no padlock without a camera to hang it from, or room beside it")
    }

    static func contentContracts(_ suite: TestSuite) {
        suite.expect(NotchLockScreenSupport.activities(timer: true, calendar: true, agents: true, downloads: true)
                        == NotchLockScreenActivity.allCases,
                     "the line reads the timer, the next event, agents and downloads, in that order")
        suite.expect(NotchLockScreenSupport.activities(timer: false, calendar: false, agents: true, downloads: true)
                        == [.agents, .downloads],
                     "only live activities are read out")
        suite.expect(NotchLockScreenSupport.showsMusic(isPlaying: true, playedWhileLocked: false)
                     && NotchLockScreenSupport.showsMusic(isPlaying: false, playedWhileLocked: true)
                     && !NotchLockScreenSupport.showsMusic(isPlaying: false, playedWhileLocked: false),
                     "a song paused before locking stays off; one paused on the lock screen stays to be resumed")

        var countdown = NotchTimerSession()
        countdown.start(mode: .timer, minutes: 5, now: 100)
        suite.expect(!NotchLockScreenSupport.timerFinished(countdown, at: 399)
                     && NotchLockScreenSupport.timerFinished(countdown, at: 400),
                     "a countdown that runs out while locked reads as finished")
        countdown.pause(at: 200)
        suite.expect(!NotchLockScreenSupport.timerFinished(countdown, at: 10_000), "a paused countdown never finishes")
        var stopwatch = NotchTimerSession()
        stopwatch.start(mode: .stopwatch, minutes: 0, now: 100)
        suite.expect(!NotchLockScreenSupport.timerFinished(stopwatch, at: 100_000), "a stopwatch never finishes")

        let stamps: [(TimeInterval, String)] = [
            (0, "0:00"), (61.9, "1:01"), (3661, "1:01:01"), (-5, "0:00"), (.nan, "0:00"), (.infinity, "0:00"),
        ]
        for (interval, expected) in stamps {
            suite.expect(NotchLockScreenSupport.timestamp(interval) == expected,
                         "a song position of \(interval) s reads \(expected)")
        }
    }

    static func soundContracts(_ suite: TestSuite) {
        let lock = NotchLockScreenSupport.soundURL(locking: true)
        let unlock = NotchLockScreenSupport.soundURL(locking: false)
        suite.expect(lock != nil && unlock != nil && lock != unlock, "locking and unlocking each have their own sound")
        suite.expect([lock, unlock].allSatisfy { $0.map { FileManager.default.fileExists(atPath: $0.path) } == true },
                     "both sounds are files this Mac has")
    }
}
