// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Applies telemetry refusal to all live app services immediately so any
/// queued or in-flight collection stops right away.
enum TelemetryPolicyRuntime {
    @MainActor
    static func refuseAll() {
        TelemetryPolicy.applyRefusal(to: .standard)
        UpdateService.shared.stopAutomaticChecks()
        AppUpdatesService.shared.syncWithPreferences()
        NotchLyricsService.shared.stop()
        NotchBrowserArtwork.shared.cancel()
        HomebrewManager.shared.clearAnalyticsOnTelemetryRefusal()
        CommandBarService.shared.forgetLearnedRanking()
    }

    @MainActor
    static func setRefused(_ refused: Bool) {
        if refused {
            refuseAll()
        } else {
            TelemetryPolicy.setRefused(false, in: .standard)
        }
    }
}
