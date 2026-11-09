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
    /// Below this, a level is treated as silence. Matching the older volume
    /// save check keeps unmute from restoring a zero it never meant to keep.
    static let silenceThreshold: Float = 0.01
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
        return volume > silenceThreshold
    }

    /// The first real level is the one unmute should put back. A later
    /// re-apply, from an app raising gain while we are muted, must not
    /// replace it or the user would get that app's level instead of their own.
    static func shouldReplaceSavedVolume(existing: Double?, current: Float?) -> Bool {
        if let existing, existing > Double(silenceThreshold) { return false }
        return shouldSaveVolume(current)
    }

    /// Capture is silent only when the input volume is down, because that is
    /// the control recording apps actually hear. A mute switch that reads
    /// engaged while the level is still live is not silence; a device with
    /// no volume control at all still counts the switch.
    static func isCaptureSilenced(muteSwitch: UInt32?, volume: Float?) -> Bool {
        if let volume { return volume <= silenceThreshold }
        return muteSwitch == 1
    }

    /// A microphone the user silenced themselves is left alone, so unmuting
    /// later never opens something this app did not close. One this app
    /// already muted is still ours even when it is already quiet.
    static func shouldLeaveUntouched(owned: Bool, captureSilenced: Bool) -> Bool {
        !owned && captureSilenced
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
        let quiet = volume <= silenceThreshold
        if !muteOn && !quiet { return .alreadyAudible }
        return .restore(clearMute: muteOn, restoreVolume: quiet)
    }

    static func volumeToRestore(uid: String,
                                saved: [String: Double],
                                legacy: Double) -> Float {
        if let value = saved[uid], value > Double(silenceThreshold) { return Float(value) }
        if legacy > Double(silenceThreshold) { return Float(legacy) }
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
}
