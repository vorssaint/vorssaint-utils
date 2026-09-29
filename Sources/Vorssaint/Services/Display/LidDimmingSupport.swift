// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What closed-lid screen dimming should do next, decided from plain values
/// so it can be tested without a display, a lid or the option ever having
/// run. `KeepAwakeManager` is the only caller and does the actual reading,
/// writing and persistence the decision implies.
enum LidDimmingSupport {
    enum Action: Equatable {
        /// Persist `save`, then dim the panel to zero.
        case dim(save: Double)
        /// Write this value back and clear whatever was persisted.
        case restore(Double)
        case none
    }

    /// The lid just closed while the option is armed. A reading of nil or
    /// zero means the panel already reads asleep — `BrightnessService` keeps
    /// such a reading out of its own remembered level for the same reason
    /// (issue #370): trusting it here would save "0" and later restore the
    /// panel to black instead of leaving it alone.
    static func lidClosed(currentBrightness: Double?) -> Action {
        guard let currentBrightness, currentBrightness > 0 else { return .none }
        return .dim(save: currentBrightness)
    }

    /// The lid opened, the option was switched off while dimmed, the
    /// closed-lid session ended, or a value survived from a launch that
    /// never got to restore it. `saved` is nil when nothing is owed.
    static func restoring(saved: Double?) -> Action {
        guard let saved else { return .none }
        return .restore(saved)
    }
}
