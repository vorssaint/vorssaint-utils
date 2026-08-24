// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind Bluetooth on sleep, kept free of AppKit and IOKit so
/// they can be tested directly.
///
/// The rule the whole feature turns on: Vorssaint only ever puts back what it
/// took away. Bluetooth already off when the Mac went to sleep is never
/// switched on for the user, which is the part a plain sleep-and-wake toggle
/// gets wrong.
enum BluetoothSleepSupport {
    /// What to do as the Mac goes to sleep.
    struct SleepPlan: Equatable {
        /// Whether Bluetooth should be switched off now.
        let powersOff: Bool
        /// Whether a later wake owes the user a restore.
        let owesRestore: Bool
    }

    static func sleepPlan(isPoweredOn: Bool, restoresOnWake: Bool) -> SleepPlan {
        guard isPoweredOn else { return SleepPlan(powersOff: false, owesRestore: false) }
        return SleepPlan(powersOff: true, owesRestore: restoresOnWake)
    }

    /// Whether waking (or a launch that finds a restore still owed, because
    /// the Mac was shut down while asleep) should switch Bluetooth back on.
    /// Bluetooth the user turned on themselves in the meantime is left alone.
    static func restores(owesRestore: Bool, isPoweredOn: Bool) -> Bool {
        owesRestore && !isPoweredOn
    }
}
