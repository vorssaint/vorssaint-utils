// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The production playback action uses the selected alert and the new output.
enum OutputDeviceSoundTests {
    struct UserDefaults {
        static let standard = UserDefaults()
        static var enabled = true
        func bool(forKey: String) -> Bool { Self.enabled }
    }
    final class NSSound {
        static var paths: [String] = []
        static var beeps = 0
        static var unloadable: Set<String> = []
        var playbackDeviceIdentifier: String?
        var played = false
        var stopped = false
        init?(contentsOfFile path: String, byReference: Bool) {
            Self.paths.append(path)
            if Self.unloadable.contains(path) { return nil }
        }
        func play() { played = true }
        func stop() { stopped = true }
        static func beep() { beeps += 1 }
    }
    class State {
        static var playingSound: NSSound?
        static var alertPath: String? = "/System/Library/Sounds/Blow.aiff"
        static func CFPreferencesCopyValue(_ key: CFString, _ app: CFString,
                                           _ user: CFString, _ host: CFString) -> CFPropertyList? {
            alertPath as CFPropertyList?
        }
    }
    static func run(expect: (Bool, String) -> Void) {
        UserDefaults.enabled = true
        NSSound.paths = []; NSSound.beeps = 0; NSSound.unloadable = []
        State.alertPath = "/System/Library/Sounds/Blow.aiff"
        Player.playSound(deviceUID: "headphones")
        let first = State.playingSound
        expect(NSSound.paths.last == State.alertPath && first?.played == true
               && first?.playbackDeviceIdentifier == "headphones",
               "output confirmation plays the user's macOS alert on the newly selected output")
        State.alertPath = "/System/Library/Sounds/Bottle.aiff"
        Player.playSound(deviceUID: "speakers")
        expect(first?.stopped == true && NSSound.paths.last == State.alertPath
               && State.playingSound?.playbackDeviceIdentifier == "speakers",
               "changing the macOS alert applies on the next switch and stops the prior sound")
        UserDefaults.enabled = false
        let count = NSSound.paths.count
        Player.playSound(deviceUID: "speakers")
        expect(State.playingSound == nil && NSSound.paths.count == count && NSSound.beeps == 0,
               "disabled confirmation does not load or play a sound")
        UserDefaults.enabled = true
        State.alertPath = nil
        NSSound.paths = []
        Player.playSound(deviceUID: "headphones")
        expect(NSSound.paths == [Player.fallbackAlertPath] && State.playingSound?.played == true
               && State.playingSound?.playbackDeviceIdentifier == "headphones",
               "an unset alert preference plays the fallback sound on the selected output")
        State.alertPath = "/missing/alert.aiff"; NSSound.unloadable = [State.alertPath!]
        NSSound.paths = []
        Player.playSound(deviceUID: "speakers")
        expect(NSSound.paths == ["/missing/alert.aiff", Player.fallbackAlertPath]
               && State.playingSound?.played == true
               && State.playingSound?.playbackDeviceIdentifier == "speakers",
               "a broken alert file falls back to the loadable fallback on the selected output")
        let previous = State.playingSound
        NSSound.unloadable.insert(Player.fallbackAlertPath)
        Player.playSound(deviceUID: "headphones")
        expect(previous?.stopped == true && State.playingSound == nil,
               "when neither file loads, nothing plays")
        expect(NSSound.beeps == 0,
               "the confirmation never beeps through the separate sound-effects output")
        Player.stopSound()
    }
}
