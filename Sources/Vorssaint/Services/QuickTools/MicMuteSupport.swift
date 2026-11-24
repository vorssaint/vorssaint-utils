// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind a global microphone mute, kept apart from the audio
/// calls so they can be pinned down by tests: which devices the mute has to
/// reach, which ones it must never touch, and how a device gets its level back.
enum MicMuteSupport {
    /// The app's own private aggregate devices: the mixer's, the island's
    /// level reader's and the recorder's. Each carries a tapped app's audio,
    /// not a microphone, and muting one would silence the very thing it is
    /// rendering or reading; a private aggregate is still listed to the
    /// process that created it, so every device list skips them by name.
    static let ownDeviceNames: Set<String> = ["Vorssaint Mixer", "Vorssaint AirPlay", "Vorssaint Island Levels",
                                              "Vorssaint Recorder"]

    /// The level a device falls back to when nothing was ever saved for it:
    /// loud enough to be usable, quiet enough not to startle.
    static let fallbackVolume: Float = 0.75
    /// Drivers may rebound to a small positive gain after a zero write. It
    /// still needs to be zeroed and cannot establish a call's unmute.
    static let residualGainLimit: Float = 0.01
    /// Devices without a readable stream layout still get the stereo pair
    /// tried, the way the mute used to.
    static let minimumChannelCount = 2
    /// CoreAudio's master element. Kept as a number so this file stays
    /// free of the HAL import the tests do not need.
    static let masterElement: UInt32 = 0

    static func isOwnDevice(name: String) -> Bool {
        ownDeviceNames.contains(name)
    }

    /// A level worth remembering. Saving a zero would make the unmute restore
    /// silence, which is how a re-applied mute could strand a microphone.
    static func shouldSaveVolume(_ volume: Float?) -> Bool {
        guard let volume else { return false }
        return volume > 0 && volume <= 1
    }

    /// The first real level is the one unmute should put back. A later
    /// re-apply, from an app raising gain while we are muted, must not
    /// replace it or the user would get that app's level instead of their own.
    static func shouldReplaceSavedVolume(existing: Double?, current: Float?) -> Bool {
        if let existing, shouldSaveVolume(Float(existing)) { return false }
        return shouldSaveVolume(current)
    }

    /// Capture is silent only when the input volume is down, because that is
    /// the control recording apps actually hear. A mute switch that reads
    /// engaged while the level is still live is not silence; a device with
    /// no volume control at all still counts the switch.
    static func isCaptureSilenced(muteSwitch: UInt32?, volume: Float?) -> Bool {
        if let volume { return volume == 0 }
        return muteSwitch == 1
    }

    /// A microphone the user silenced themselves is left alone, so unmuting
    /// later never opens something this app did not close. One this app
    /// already muted is still ours even when it is already quiet.
    static func shouldLeaveUntouched(owned: Bool, captureSilenced: Bool) -> Bool {
        !owned && captureSilenced
    }

    struct InputControls {
        enum Gain { case unavailable, unreadable, silent, audible }
        let gain: Gain
        let muteSwitch: UInt32?
        /// Gain addresses actually read at zero.
        var silentGains: Set<String> = []
        /// Engaged switches covering the input or channels without gain.
        var mutedElements: Set<UInt32> = []

        var isSilenced: Bool {
            gain == .silent || (gain == .unavailable && muteSwitch == 1)
        }

        /// A driver losing a readable gain control does not establish that it opened.
        func opened(since previous: InputControls) -> Bool {
            previous.isSilenced && ((previous.gain == .silent && gain == .audible)
                || ((previous.muteSwitch == 1 || !previous.mutedElements.isEmpty) && muteSwitch == 0))
        }
    }

    /// What an unmute has to do to a device this app muted. The mute switch
    /// and the volume are separate controls: clearing one must not skip the
    /// other, or a mute that zeroed the level would leave the microphone dead.
    enum RestoreNeed: Equatable {
        case alreadyAudible
        case unreadable
        case restore(clearMute: Bool, restoreVolume: Bool)
    }

    static func restoreNeed(muteSwitch: UInt32?, volume: Float?, hasSavedVolume: Bool = false) -> RestoreNeed {
        let muteOn = muteSwitch == 1
        guard let volume else {
            if hasSavedVolume { return .unreadable }
            return muteOn ? .restore(clearMute: true, restoreVolume: false) : .unreadable
        }
        let restoreVolume = hasSavedVolume || volume == 0
        if !muteOn && !restoreVolume { return .alreadyAudible }
        return .restore(clearMute: muteOn, restoreVolume: restoreVolume)
    }

    static func volumeToRestore(uid: String,
                                saved: [String: Double],
                                legacy: Double) -> Float {
        if let value = saved[uid], shouldSaveVolume(Float(value)) { return Float(value) }
        if shouldSaveVolume(Float(legacy)) { return Float(legacy) }
        return fallbackVolume
    }

    /// Master first, then every channel the stream layout named, never fewer
    /// than a stereo pair so a device that hides its count still gets 1 and 2.
    static func inputChannelElements(channelCount: Int) -> [UInt32] {
        let channels = max(channelCount, minimumChannelCount)
        return [masterElement] + (1...channels).map { UInt32($0) }
    }

    /// Which devices an unmute has to touch. Normally only the ones this app
    /// muted, so a microphone the user silenced in System Settings stays
    /// silenced. With no record at all (settings restored onto another Mac, or
    /// a state from before this was tracked) every present device is restored:
    /// leaving someone muted with no way back is the worse failure. An empty
    /// record is different from a missing one: it means the sweep ran and
    /// every device was already silent by the user's own hand, so there is
    /// nothing this app is allowed to open.
    static func restoreTargets(recorded: [String]?, present: [String]) -> [String] {
        guard let recorded else { return present }
        let wanted = Set(recorded)
        return present.filter { wanted.contains($0) }
    }

    /// The claims a sweep carries forward untouched: the devices this app
    /// silenced that are not here right now. A headset unplugged while muted
    /// comes back still silenced, and it is still this app's to release;
    /// dropping the claim would leave it muted with nothing left to unmute it.
    static func absentClaims(recorded: [String]?, present: [String]) -> [String] {
        let here = Set(present)
        return (recorded ?? []).filter { !here.contains($0) }
    }

    /// A burst of attempts to silence an input backs off from a quarter
    /// second to half a minute. A new connection starts over.
    struct Retry {
        let deviceID: UInt32
        let onlyWhileIdle: Bool
        let attempts: Int
        let lastAttempt: TimeInterval
        let deadline: TimeInterval?
        /// Values returned by refused setters or tiny levels corrected to zero.
        /// Other controls and larger gain changes still get serviced immediately.
        var retryValues: [String: Double] = [:]

        func defers(_ value: Double, at key: String, isGain: Bool) -> Bool {
            guard let previous = retryValues[key] else { return false }
            return previous == value || (isGain && Self.isSmallGain(previous) && Self.isSmallGain(value))
        }

        static func isSmallGain(_ value: Double) -> Bool {
            value > 0 && value <= Double(residualGainLimit)
        }

        init(deviceID: UInt32, onlyWhileIdle: Bool, verified: Bool, previous: Retry?, now: TimeInterval) {
            self.deviceID = deviceID
            self.onlyWhileIdle = onlyWhileIdle
            lastAttempt = now
            if let previous, previous.deviceID == deviceID, previous.onlyWhileIdle == onlyWhileIdle,
               !verified || previous.deadline != nil || now - previous.lastAttempt < 0.25 {
                attempts = min(previous.attempts + 1, 10)
            } else {
                attempts = 1
            }
            deadline = attempts < 3 ? nil : now + min(30, 0.25 * Double(1 << (attempts - 3)))
        }
    }
}
