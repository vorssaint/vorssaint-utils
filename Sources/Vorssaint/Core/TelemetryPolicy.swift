// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Global privacy boundary triggered from the first onboarding screen or
/// Settings. Once telemetry is refused, every feature blocks automatic
/// background data collection, local usage learning, diagnostics, online
/// metadata lookups and subprocess analytics from that moment on.
enum TelemetryPolicy {
    static func isRefused(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.telemetryRefused)
    }

    /// Automatic update checks never run before first-run onboarding completes,
    /// so nothing contacts external servers before the person sees the first
    /// screen and can refuse all telemetry.
    static func shouldStartAutomaticUpdateChecksAtLaunch(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.hasOnboarded) && !isRefused(in: defaults)
    }

    static func allowsAutomaticUpdateChecks(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    static func allowsBackgroundDataCollection(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    static func allowsUsageLearning(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    static func allowsFeedbackDiagnostics(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    static func allowsHomebrewAnalytics(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    static func allowsOnlineMetadataLookups(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    static func allowsRemotePriceUpdates(in defaults: UserDefaults = .standard) -> Bool {
        !isRefused(in: defaults)
    }

    /// Persists telemetry refusal and switches off every automatic background
    /// collection, online lookup and local usage learning store immediately.
    static func applyRefusal(to defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: DefaultsKey.telemetryRefused)
        defaults.set(false, forKey: DefaultsKey.autoCheckUpdates)
        defaults.set(AppUpdatesSupport.CheckFrequency.off.rawValue,
                     forKey: DefaultsKey.appUpdatesCheckFrequency)
        defaults.set(false, forKey: DefaultsKey.notchLyricsOnline)
        defaults.set(false, forKey: DefaultsKey.notchBrowserCovers)
        defaults.set(false, forKey: DefaultsKey.notchAgentsPriceUpdates)
        defaults.set(false, forKey: DefaultsKey.audioTranscriptionSummaryProviderUpdateChecks)
        CommandBarLearning.forgetAll(in: defaults)
        defaults.removeObject(forKey: DefaultsKey.commandBarQueryHabitKey)
    }

    /// Updates the refusal preference. Turning refusal off never silently
    /// re-enables features that were turned off when telemetry was refused.
    static func setRefused(_ refused: Bool, in defaults: UserDefaults = .standard) {
        if refused {
            applyRefusal(to: defaults)
        } else {
            defaults.set(false, forKey: DefaultsKey.telemetryRefused)
        }
    }

    static func brewEnvironment(_ base: [String: String],
                                in defaults: UserDefaults = .standard) -> [String: String] {
        brewEnvironment(base, refused: isRefused(in: defaults))
    }

    static func brewEnvironment(_ base: [String: String], refused: Bool) -> [String: String] {
        guard refused else { return base }
        var environment = base
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["DO_NOT_TRACK"] = "1"
        return environment
    }

    static func codexEnvironment(_ base: [String: String],
                                 in defaults: UserDefaults = .standard) -> [String: String] {
        codexEnvironment(base, refused: isRefused(in: defaults))
    }

    static func codexEnvironment(_ base: [String: String], refused: Bool) -> [String: String] {
        guard refused else { return base }
        var environment = base
        environment["DO_NOT_TRACK"] = "1"
        environment["DISABLE_TELEMETRY"] = "1"
        return environment
    }

    static func claudeEnvironment(_ base: [String: String],
                                  in defaults: UserDefaults = .standard) -> [String: String] {
        claudeEnvironment(base, refused: isRefused(in: defaults))
    }

    static func claudeEnvironment(_ base: [String: String], refused: Bool) -> [String: String] {
        guard refused else { return base }
        var environment = base
        environment["DISABLE_TELEMETRY"] = "1"
        environment["DISABLE_ERROR_REPORTING"] = "1"
        environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        environment["DO_NOT_TRACK"] = "1"
        return environment
    }
}
