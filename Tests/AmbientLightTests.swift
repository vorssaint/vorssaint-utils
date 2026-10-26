// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AmbientLightTests {
    static func run(_ suite: TestSuite) {
        suite.expect(AmbientLightSupport.thresholdSteps.count == 10,
                     "the slider offers ten lighting presets")
        suite.expect(AmbientLightSupport.nearestStep(69) == 2
                     && AmbientLightSupport.nearestStep(0) == 0
                     && AmbientLightSupport.nearestStep(100_000) == 9,
                     "custom thresholds map to the nearest preset without exceeding the slider")
        for (index, lux) in AmbientLightSupport.thresholdSteps.enumerated() {
            suite.expect(AmbientLightSupport.nearestStep(lux) == index,
                         "each preset remains selected when the settings reopen")
            suite.expect(abs(AmbientLightSupport.meterPosition(lux) - Double(index) / 9) < 0.000001,
                         "the live meter aligns with the corresponding slider step")
        }
        suite.expect(AmbientLightSupport.meterPosition(0) == 0
                     && AmbientLightSupport.meterPosition(100_000) == 1
                     && AmbientLightSupport.meterPosition(.nan) == 0,
                     "the live meter handles darkness, saturation and invalid input")
        suite.expect(AmbientLightSupport.meterPosition(150) > 3.0 / 9
                     && AmbientLightSupport.meterPosition(150) < 4.0 / 9,
                     "live readings interpolate between presets")
        var gate = AmbientLightGate()
        func sample(_ lux: Double?, _ time: Double,
                    defaultMode: AmbientLightAppearance = .dark) -> AmbientLightAppearance? {
            gate.observe(lux: lux, threshold: 10_000, defaultAppearance: defaultMode, now: time)
        }
        suite.expect(sample(12_000, 0) == nil && sample(9_999, 2) == nil
                     && sample(12_000, 4) == nil,
                     "brief flashes and interrupted readings do not change appearance")
        suite.expect(sample(10_000, 6) == nil && sample(10_000, 8) == .light,
                     "four seconds at or above the trigger requests Light")
        suite.expect(sample(30_000, 10) == .light,
                     "stable bright light keeps the automatic target authoritative")
        suite.expect(sample(9_999, 12) == nil && sample(9_999, 14) == nil
                     && sample(9_999, 16) == .dark,
                     "four seconds below the same trigger returns to default Dark")
        suite.expect(sample(10_000, 18) == nil && sample(9_000, 20) == nil
                     && sample(10_001, 22) == nil && sample(9_999, 24) == nil,
                     "readings fluctuating around the trigger never produce a rapid switch")

        gate = AmbientLightGate()
        suite.expect(sample(0, 0) == nil && sample(0, 2) == nil && sample(0, 4) == .dark,
                     "starting in dim light selects default Dark after settling")
        gate = AmbientLightGate()
        suite.expect(sample(0, 0, defaultMode: .light) == nil
                     && sample(0, 4, defaultMode: .light) == .light
                     && sample(10_000, 6, defaultMode: .light) == nil
                     && sample(10_000, 10, defaultMode: .light) == .dark
                     && sample(9_999, 12, defaultMode: .light) == nil
                     && sample(9_999, 16, defaultMode: .light) == .light,
                     "Light as default reverses both sides of the trigger")

        for invalid in [nil, Double.nan, .infinity, -.infinity, -1] as [Double?] {
            gate = AmbientLightGate()
            suite.expect(sample(15_000, 0) == nil && sample(invalid, 2) == nil
                         && sample(15_000, 4) == nil && sample(15_000, 8) == .light,
                         "invalid or absent readings break a pending transition")
            suite.expect(sample(invalid, 10) == nil && sample(15_000, 12) == nil
                         && sample(15_000, 16) == .light,
                         "a failed sensor never requests default mode and recovery settles again")
        }
        gate = AmbientLightGate()
        suite.expect(sample(20_000, 0) == nil && sample(20_000, 60) == nil
                     && sample(20_000, 64) == .light,
                     "a long sampling gap needs fresh sustained light")
        gate = AmbientLightGate()
        suite.expect(sample(20_000, 10) == nil && sample(20_000, 5) == nil
                     && sample(20_000, 9) == .light,
                     "a clock moving backwards starts a new observation period")
        suite.expect(AmbientLightSupport.validLux(0) == 0, "zero lux is a real sensor reading")
        suite.expect(AmbientLightSupport.sanitizedThreshold(.nan) == 10_000
                     && AmbientLightSupport.sanitizedThreshold(.infinity) == 10_000
                     && AmbientLightSupport.sanitizedThreshold(-10) == 1
                     && AmbientLightSupport.sanitizedThreshold(200_000) == 100_000,
                     "corrupt or out-of-range saved thresholds are safe")
        suite.expect(AmbientLightAppearance.sanitized(nil) == .dark
                     && AmbientLightAppearance.sanitized("invalid") == .dark
                     && AmbientLightAppearance.sanitized("light") == .light,
                     "the saved default appearance is validated")

        suite.expect(!AppFeature.ambientLight.installedByDefault
                     && AppFeature.ambientLight.enabledKeys == [DefaultsKey.ambientLightEnabled]
                     && AppFeature.ambientLight.permissions.isEmpty,
                     "ambient light is opt-in and has its own enable preference")
        suite.expect(AppFeature.ambientLight.settingsDestination ==
                     FeatureSettingsDestination(.energy, sectionAnchor: .ambientLight),
                     "ambient light opens its Energy settings card")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [
            DefaultsKey.ambientLightEnabled, DefaultsKey.ambientLightThreshold,
            DefaultsKey.ambientLightDefaultAppearance,
            AppFeature.ambientLight.availabilityKey,
        ]), "backup carries the ambient light preferences")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.ambientLight(language)
            suite.expect(!strings.title.isEmpty && !strings.description.isEmpty
                         && !strings.behavior.isEmpty && !strings.scaleHint.isEmpty && !strings.threshold.isEmpty
                         && !strings.currentLight.isEmpty && !strings.waiting.isEmpty
                         && !strings.unavailable.isEmpty && !strings.appearanceUnavailable.isEmpty
                         && !strings.paused.isEmpty && !strings.defaultMode.isEmpty
                         && !strings.aboveTriggerFormat.isEmpty && !strings.dark.isEmpty && !strings.light.isEmpty,
                         "ambient light strings cover \(language.rawValue)")
        }
    }
}
