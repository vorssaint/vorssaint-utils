// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum GameControllerContract {
    static func run(_ suite: TestSuite) {
        chargeEstimates(suite)
        dualSenseFirmware(suite)
        formatting(suite)
        strings(suite)
    }

    private static func history(_ state: ControllerChargeState,
                                _ steps: [(time: TimeInterval, level: Double)]) -> ControllerChargeHistory {
        var history = ControllerChargeHistory()
        for step in steps { history.record(level: step.level, state: state, at: step.time) }
        return history
    }

    private static func chargeEstimates(_ suite: TestSuite) {
        let oneStep = history(.charging, [(0, 0.4), (600, 0.5)])
        suite.expect(oneStep.estimate == nil,
                     "one level step cannot give a charge rate: its start is unknown")

        let charging = history(.charging, [(0, 0.4), (600, 0.5), (1200, 0.6)])
        suite.expect(abs((charging.estimate ?? 0) - 2400) < 1,
                     "charging 10% every 10 minutes from 60% is 40 minutes from full")

        let draining = history(.discharging, [(0, 0.8), (3600, 0.7), (7200, 0.6)])
        suite.expect(abs((draining.estimate ?? 0) - 21600) < 1,
                     "losing 10% an hour from 60% leaves six hours")

        var flipped = charging
        flipped.record(level: 0.6, state: .discharging, at: 1300)
        suite.expect(flipped.estimate == nil && flipped.steps.count == 1,
                     "a change of direction starts the history over")

        var repeated = charging
        repeated.record(level: 0.6, state: .charging, at: 1500)
        suite.expect(repeated.steps == charging.steps,
                     "reading the same level again records nothing")

        let backwards = history(.charging, [(0, 0.6), (600, 0.5), (1200, 0.4)])
        suite.expect(backwards.estimate == nil, "a falling level while charging gives no estimate")

        let stalled = history(.charging, [(0, 0.1), (3600, 0.11), (7200, 0.12)])
        suite.expect(stalled.estimate == nil, "an estimate past two days is not shown")

        suite.expect(history(.full, [(0, 1), (60, 0.9), (120, 0.8)]).estimate == nil,
                     "a full battery has nothing to estimate")

        var invalid = ControllerChargeHistory()
        invalid.record(level: .nan, state: .charging, at: 0)
        suite.expect(invalid.steps.isEmpty, "a non-finite level is ignored")

        var reset = charging
        reset.reset()
        suite.expect(reset.estimate == nil && reset.steps.isEmpty && reset.state == .unknown,
                     "reset forgets the history")

        suite.expect(GameControllerSupport.percent(0.456) == 46
                        && GameControllerSupport.percent(1) == 100
                        && GameControllerSupport.percent(1.2) == nil
                        && GameControllerSupport.percent(-0.1) == nil
                        && GameControllerSupport.percent(nil) == nil,
                     "battery percent rounds a valid level and rejects the rest")
    }

    private static func firmwareReport(version: UInt32, hardware: UInt32,
                                       date: String = "Sep 12 2023", time: String = "12:22:08",
                                       id: UInt8 = 0x20) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 64)
        report[0] = id
        for (index, byte) in Array(date.utf8).prefix(11).enumerated() { report[1 + index] = byte }
        for (index, byte) in Array(time.utf8).prefix(8).enumerated() { report[12 + index] = byte }
        for shift in 0..<4 {
            report[24 + shift] = UInt8((hardware >> (8 * UInt32(shift))) & 0xFF)
            report[28 + shift] = UInt8((version >> (8 * UInt32(shift))) & 0xFF)
        }
        return report
    }

    private static func dualSenseFirmware(_ suite: TestSuite) {
        let report = firmwareReport(version: 0x0100_0224, hardware: 0x0000_0310)
        let parsed = GameControllerSupport.parseDualSenseFirmware(report)
        suite.expect(parsed?.version == 0x0100_0224 && parsed?.hardware == 0x0310,
                     "the firmware report is read as little-endian words")
        suite.expect(parsed?.built == "Sep 12 2023 12:22:08",
                     "the build date and time come from the report text")
        suite.expect(parsed.map(GameControllerSupport.firmwareText) == "0x01000224 · Sep 12 2023 12:22:08",
                     "the firmware shows its version and build")

        let noStamp = GameControllerSupport.parseDualSenseFirmware(
            firmwareReport(version: 0x0100_0224, hardware: 1, date: "", time: ""))
        suite.expect(noStamp?.built == nil && noStamp.map(GameControllerSupport.firmwareText) == "0x01000224",
                     "a report without a build stamp still shows its version")

        suite.expect(GameControllerSupport.parseDualSenseFirmware(
            firmwareReport(version: 0x0100_0224, hardware: 1, id: 0x05)) == nil,
                     "a report with another id is not firmware information")
        suite.expect(GameControllerSupport.parseDualSenseFirmware(
            firmwareReport(version: 0, hardware: 1)) == nil
                        && GameControllerSupport.parseDualSenseFirmware(
                            firmwareReport(version: .max, hardware: 1)) == nil,
                     "an empty or all-ones version is rejected")
        suite.expect(GameControllerSupport.parseDualSenseFirmware(Array(report.prefix(20))) == nil,
                     "a truncated report is rejected")
        var binary = report
        binary[3] = 0x07
        suite.expect(GameControllerSupport.parseDualSenseFirmware(binary)?.built == nil,
                     "a build stamp with control bytes is dropped, not shown")

        suite.expect(GameControllerSupport.isDualSense(vendorID: 0x054C, productID: 0x0CE6)
                        && GameControllerSupport.isDualSense(vendorID: 0x054C, productID: 0x0DF2)
                        && !GameControllerSupport.isDualSense(vendorID: 0x054C, productID: 0x09CC)
                        && !GameControllerSupport.isDualSense(vendorID: 0x045E, productID: 0x0CE6)
                        && !GameControllerSupport.isDualSense(vendorID: nil, productID: nil),
                     "only Sony's DualSense ids are read for firmware")
    }

    private static func formatting(_ suite: TestSuite) {
        let english = Locale(identifier: "en-US")
        suite.expect(GameControllerSupport.duration(7500, locale: english) == "2h 5m",
                     "a duration shows hours and minutes")
        suite.expect(GameControllerSupport.duration(10, locale: english) == "1m",
                     "a duration never reads below a minute")
        suite.expect(GameControllerSupport.duration(90_000, locale: english) == "1d 1h",
                     "a duration keeps two units at most")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let text = FeatureStrings.gameController(language)
            let values = [text.pageTitle, text.hubDescription, text.panelDescription, text.emptyTitle,
                          text.emptyHint, text.batteryLabel, text.batteryNotReported, text.stateCharging,
                          text.stateDischarging, text.stateFull, text.timeToFull, text.timeRemaining,
                          text.estimating, text.connectedFor, text.connectedForLowerBoundHelp,
                          text.connectionLabel, text.typeLabel, text.firmwareLabel, text.featuresLabel,
                          text.featureHaptics, text.featureLightBar, text.featureMotion,
                          text.featureAdaptiveTriggers, text.featureTouchpad]
            suite.expect(values.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                         "game controller strings are filled in for \(language.rawValue)")
        }
    }
}
