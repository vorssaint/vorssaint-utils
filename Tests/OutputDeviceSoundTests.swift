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
        var volume: Float = 1
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
        static var alertVolume: CFPropertyList?
        static func CFPreferencesCopyValue(_ key: CFString, _ app: CFString,
                                           _ user: CFString, _ host: CFString) -> CFPropertyList? {
            switch key as String {
            case "com.apple.sound.beep.sound": return alertPath as CFPropertyList?
            case "com.apple.sound.beep.volume": return alertVolume
            default: return nil
            }
        }
    }
    static func run(expect: (Bool, String) -> Void) {
        UserDefaults.enabled = true
        NSSound.paths = []; NSSound.beeps = 0; NSSound.unloadable = []
        State.alertPath = "/System/Library/Sounds/Blow.aiff"
        State.alertVolume = nil
        Player.playSound(deviceUID: "headphones")
        let first = State.playingSound
        expect(NSSound.paths.last == State.alertPath && first?.played == true
               && first?.playbackDeviceIdentifier == "headphones",
               "output confirmation plays the user's macOS alert on the newly selected output")
        expect(first?.volume == 1, "an unset alert volume plays at the slider's full default")
        State.alertVolume = NSNumber(value: 0.25)
        Player.playSound(deviceUID: "headphones")
        expect(State.playingSound?.volume == 0.25 && State.playingSound?.played == true,
               "the confirmation plays at the alert volume from Sound settings")
        State.alertVolume = NSNumber(value: 3)
        Player.playSound(deviceUID: "headphones")
        let loud = State.playingSound?.volume
        State.alertVolume = NSNumber(value: -1)
        Player.playSound(deviceUID: "headphones")
        let quiet = State.playingSound?.volume
        State.alertVolume = NSNumber(value: Float.nan)
        Player.playSound(deviceUID: "headphones")
        let unreadable = State.playingSound?.volume
        State.alertVolume = "loud" as CFPropertyList
        Player.playSound(deviceUID: "headphones")
        expect(loud == 1 && quiet == 0 && unreadable == 1 && State.playingSound?.volume == 1,
               "an out-of-range alert volume clamps, and an unreadable one plays at full volume")
        State.alertVolume = NSNumber(value: 0.5)
        Player.playSound(deviceUID: "headphones")
        expect(State.playingSound?.volume == 0.5, "the alert volume applies again once readable")
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
               && State.playingSound?.playbackDeviceIdentifier == "headphones"
               && State.playingSound?.volume == 0.5,
               "an unset alert preference plays the fallback sound on the selected output at the alert volume")
        State.alertPath = "/missing/alert.aiff"; NSSound.unloadable = [State.alertPath!]
        NSSound.paths = []
        Player.playSound(deviceUID: "speakers")
        expect(NSSound.paths == ["/missing/alert.aiff", Player.fallbackAlertPath]
               && State.playingSound?.played == true
               && State.playingSound?.playbackDeviceIdentifier == "speakers"
               && State.playingSound?.volume == 0.5,
               "a broken alert file falls back to the loadable fallback on the selected output at the alert volume")
        let previous = State.playingSound
        NSSound.unloadable.insert(Player.fallbackAlertPath)
        Player.playSound(deviceUID: "headphones")
        expect(previous?.stopped == true && State.playingSound == nil,
               "when neither file loads, nothing plays")
        expect(NSSound.beeps == 0,
               "the confirmation never beeps through the separate sound-effects output")
        State.alertVolume = nil
        Player.stopSound()
    }
}
