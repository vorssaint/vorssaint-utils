// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind a global microphone mute, kept apart from the audio
/// calls so they can be pinned down by tests: which devices the mute has to
/// reach, which ones it must never touch, and how a device gets its level back.
enum MicMuteSupport {
    /// The app's own private mixing device. It carries a tapped app's audio,
    /// not a microphone, and muting it would silence the very thing the mixer
    /// is rendering.
    static let ownDeviceName = "Vorssaint Mixer"

    /// The level a device falls back to when nothing was ever saved for it:
    /// loud enough to be usable, quiet enough not to startle.
    static let fallbackVolume: Float = 0.75

    static func isOwnDevice(name: String) -> Bool {
        name == ownDeviceName
    }

    /// A level worth remembering. Saving a zero would make the unmute restore
    /// silence, which is how a re-applied mute could strand a microphone.
    static func shouldSaveVolume(_ volume: Float?) -> Bool {
        guard let volume else { return false }
        return volume > 0.01
    }

    static func volumeToRestore(uid: String,
                                saved: [String: Double],
                                legacy: Double) -> Float {
        if let value = saved[uid], value > 0.01 { return Float(value) }
        if legacy > 0.01 { return Float(legacy) }
        return fallbackVolume
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

    /// Which still-silenced devices to release when the app believes nothing is
    /// muted. A device this app has silenced before, which is silent now, and
    /// which nothing currently claims, is a mute of this app's own making that
    /// lost its record: a voice processing session clears the mute switch for
    /// its own duration and restores the value it found when it ends, so a mute
    /// released while such a session was open comes back with the claim already
    /// dropped (issue #1568). The empty claim list cannot say which of the two
    /// it is, which is why the record of ever having muted a device is what
    /// decides.
    ///
    /// This can also open a microphone the user silenced in System Settings, if
    /// this app had muted that same device at some earlier point. That is the
    /// trade `restoreTargets` already makes for a missing record: leaving
    /// someone muted with no way back is the worse failure.
    static func orphanedMuteTargets(touched: [String],
                                    claimed: [String]?,
                                    silenced: [String]) -> [String] {
        let owned = Set(claimed ?? [])
        let seen = Set(touched)
        return silenced.filter { seen.contains($0) && !owned.contains($0) }
    }

    /// The running record of devices this app has silenced, newest last and
    /// bounded so a laptop that meets many interfaces does not grow it forever.
    static func updatedTouchedDevices(_ stored: [String], adding: [String], limit: Int = 16) -> [String] {
        var updated = stored.filter { !adding.contains($0) }
        updated.append(contentsOf: adding)
        if updated.count > limit { updated.removeFirst(updated.count - limit) }
        return updated
    }
}
