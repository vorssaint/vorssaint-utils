// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind capping the system output after the Mac wakes, kept
/// apart from the audio calls so they can be pinned down by tests: when a wake
/// may touch the level at all, and how a stored ceiling is made safe to use.
///
/// A ceiling is a maximum, never a target: it only ever moves the level down.
/// It never raises, never unmutes, and nothing here remembers the previous
/// level for a later restore — restoring a cap would raise the volume, which
/// is exactly what a cap must never do.
enum WakeVolumeCapSupport {
    /// The level to write, or nil to leave the output exactly as it is.
    ///
    /// A muted output is left entirely alone: lowering the scalar of a muted
    /// output is pointless work and risks a driver that unmutes on a volume
    /// write. A level already at or under the ceiling is left alone too — the
    /// ceiling caps, it does not aim. A ceiling below the audible floor or
    /// outside 1...100 is a corrupt or never-set preference, and the safe
    /// answer is to do nothing rather than clamp to silence: a stored zero
    /// once silenced the speakers on the headphone-disconnect path, and this
    /// ceiling inherits the same trap, so zero must never mean "write zero".
    /// The floor is the headphone-disconnect floor, reused rather than
    /// restated — one audible minimum for both protections, so they cannot
    /// drift into disagreeing about what "too quiet to write" means.
    static func cappedVolume(currentPercent: Int,
                             ceilingPercent: Int,
                             isMuted: Bool) -> Int? {
        if isMuted { return nil }
        guard ceilingPercent >= Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
              ceilingPercent <= 100 else { return nil }
        guard currentPercent > ceilingPercent else { return nil }
        return ceilingPercent
    }

    /// Makes a raw stored ceiling safe to decide with. Non-finite junk falls
    /// back to the registered default, anything under the floor rises to the
    /// floor, and anything past full scale stops there — no input, however
    /// corrupt, comes out as silence. A separate launch migration moves a
    /// stored zero to the default (mirroring the headphone-disconnect pair);
    /// this sanitizer is the second half of that guarantee, for values that
    /// arrive without going through the migration.
    static func sanitizedCeilingPercent(_ stored: Double) -> Int {
        guard stored.isFinite else { return Defaults.defaultMixerWakeVolumeCapPercent }
        if stored < Double(Defaults.minimumMixerHeadphonesDisconnectVolumePercent) {
            return Defaults.minimumMixerHeadphonesDisconnectVolumePercent
        }
        if stored > 100 { return 100 }
        return Int(stored)
    }
}
