// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Contracts for the optional fan RPM imbalance alert. The sampler, gate and
/// notification service are exercised through their pure decision pieces so no
/// test touches the machine's SMC or posts a notification.
enum FanRPMAlertTests {
    static func run(_ suite: TestSuite) {
        // MARK: Threshold choices

        for allowed in Defaults.allowedFanRPMImbalanceThresholds {
            suite.expect(Defaults.sanitizedFanRPMImbalanceThreshold(allowed) == allowed,
                         "\(allowed) RPM is an accepted imbalance threshold")
        }
        suite.expect(Defaults.allowedFanRPMImbalanceThresholds == [500, 1_000, 1_500],
                     "the picker offers exactly 500, 1000 and 1500 RPM")
        for invalid in [-1, 0, 499, 700, 1_499, 2_000, Int.max] {
            suite.expect(Defaults.sanitizedFanRPMImbalanceThreshold(invalid) == 500,
                         "an unsupported threshold falls back to 500 RPM")
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.monitorAlertFanRPMImbalance] as? Bool == false,
                     "the fan imbalance alert is off by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.monitorAlertFanRPMImbalanceThreshold] as? Int == 500,
                     "the fan imbalance threshold defaults to 500 RPM")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.monitorAlertFanRPMImbalance)
                         && SettingsBackupSupport.exportKeys().contains(DefaultsKey.monitorAlertFanRPMImbalanceThreshold),
                     "settings backup carries the fan alert toggle and threshold")

        // MARK: imbalance math

        suite.expectClose(FanControlPolicy.fanImbalance([1_820, 1_180]) ?? -1, 640,
                          "the alert compares the fastest and slowest fan")
        suite.expectClose(FanControlPolicy.fanImbalance([1_000, 1_500, 1_800]) ?? -1, 800,
                          "a third fan does not hide the widest pair")
        suite.expectClose(FanControlPolicy.fanImbalance([1_200, 1_200]) ?? -1, 0,
                          "matched fans have no imbalance")
        suite.expect(FanControlPolicy.fanImbalance([1_500]) == nil
                         && FanControlPolicy.fanImbalance([]) == nil,
                     "fewer than two readings cannot produce an imbalance")
        suite.expect(FanControlPolicy.fanImbalance([1_500, -1]) == nil
                         && FanControlPolicy.fanImbalance([1_500, Double.nan]) == nil
                         && FanControlPolicy.fanImbalance([1_500, Double.infinity]) == nil,
                     "invalid readings are not compared as fan speeds")
        suite.expectClose(FanControlPolicy.fanImbalance([1_500, Double.nan, 900]) ?? -1, 600,
                          "a bad reading is skipped while two good fans remain")

        let strings = FeatureStrings.monitorAlerts(.enUS)
        suite.expect(String(format: strings.fanRPMImbalanceBodyFormat, 640, 1_820, 1_180)
                         == "Fans differ by 640 RPM (1820 and 1180)",
                     "the notification names both fan speeds and their difference")
        suite.expect(String(format: strings.fanRPMFormat, 1_000) == "1000 RPM",
                     "the threshold picker prints an exact RPM value")

        // MARK: not-reporting detection

        suite.expect(!FanControlPolicy.fansNotReporting([1_000, 1_800], expectedCount: 2),
                     "a complete set of plausible readings is reporting")
        suite.expect(FanControlPolicy.fansNotReporting([1_000], expectedCount: 2),
                     "a missing fan has its own alert condition")
        suite.expect(FanControlPolicy.fansNotReporting([], expectedCount: 2),
                     "no readings at all means the fans are not reporting")
        suite.expect(FanControlPolicy.fansNotReporting([1_000, -5], expectedCount: 2)
                         && FanControlPolicy.fansNotReporting([1_000, Double.nan], expectedCount: 2),
                     "an invalid reading is a not-reporting condition")
        suite.expect(!FanControlPolicy.fansNotReporting([1_000], expectedCount: 1),
                     "a one-fan Mac with one reading is healthy")
        suite.expect(!FanControlPolicy.fansNotReporting([], expectedCount: 0),
                     "a Mac without fan telemetry does not claim a failed fan")

        // MARK: sustained window

        var gate = SustainedAlertGate()
        let start: TimeInterval = 100
        suite.expect(!gate.shouldAlert(reading: 640, threshold: 500, readAt: start),
                     "the first imbalance starts the window without firing")
        suite.expect(!gate.shouldAlert(reading: 640, threshold: 500, readAt: start),
                     "a repeated cached reading cannot age into an alert")
        suite.expect(!gate.shouldAlert(reading: 640, threshold: 500, readAt: start + 11),
                     "an imbalance shorter than the sustained window stays quiet")
        suite.expect(gate.shouldAlert(reading: 640, threshold: 500, readAt: start + 12),
                     "an imbalance held across twelve seconds fires")
        gate.reset()
        suite.expect(!gate.shouldAlert(reading: 640, threshold: 500, readAt: start),
                     "a reset gate waits again before firing")

        // MARK: feature catalog

        suite.expect(AppFeature.monitorAlertPairs.contains { $0.key == DefaultsKey.monitorAlertFanRPMImbalance
                                                              && $0.feature == .fanControl },
                     "the fan alert belongs to the fan control feature")
        suite.expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                       boolFor: { $0 == DefaultsKey.monitorAlertFanRPMImbalance }),
                     "the fan alert arms the monitor service on its own")
        suite.expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .fanControl },
                                                        boolFor: { $0 == DefaultsKey.monitorAlertFanRPMImbalance }),
                     "the fan alert stays disarmed when fan control is off in the hub")
    }
}
