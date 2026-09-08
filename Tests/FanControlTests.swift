// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FanControlTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            let actual = formatSpecifiers(in: format)
            expect(actual == expected, "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Fan Control safety policy

        expect(FanControlPolicy.coolingDuration == 15 * 60
                && FanControlPolicy.heartbeatLimit < 10,
               "the legacy session stays bounded while current control loses ownership quickly")
        expect(FanControlPolicy.isAutomaticMode(0)
                && FanControlPolicy.isAutomaticMode(3)
                && !FanControlPolicy.isAutomaticMode(1)
                && !FanControlPolicy.isAutomaticMode(2)
                && !FanControlPolicy.isAutomaticMode(.max),
               "fan ownership accepts firmware automatic modes and rejects manual or unknown modes")
        expect(FanControlPolicy.fanCount(from: 1) == 1
                && FanControlPolicy.fanCount(from: 8) == 8
                && FanControlPolicy.fanCount(from: 0) == nil
                && FanControlPolicy.fanCount(from: 9) == nil
                && FanControlPolicy.fanCount(from: 1.5) == nil
                && FanControlPolicy.fanCount(from: .nan) == nil,
               "fan discovery accepts only a small integral hardware count")
        expect(FanControlPolicy.validBounds(minimum: 1_200, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: -1, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: 5_800, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: 1_200, maximum: 25_000),
               "fan bounds must be finite, ordered and physically sane")
        expect(FanControlPolicy.validReading(0)
                && FanControlPolicy.validReading(8_000)
                && !FanControlPolicy.validReading(-1)
                && !FanControlPolicy.validReading(.infinity),
               "fan readings stay within a safe display and verification range")
        expect(FanControlPolicy.minimumCoolingLevel == 0
                && FanControlPolicy.maximumCoolingLevel == 100
                && FanControlPolicy.defaultCoolingLevel == 100
                && FanControlPolicy.validCoolingLevel(0)
                && FanControlPolicy.validCoolingLevel(55)
                && FanControlPolicy.validCoolingLevel(100)
                && !FanControlPolicy.validCoolingLevel(-5)
                && !FanControlPolicy.validCoolingLevel(26),
               "manual cooling accepts the full bounded five-percent scale")
        expect(FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                 level: 0) == 1_200
                && FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                     level: 25) == 2_350
                && FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                     level: 100) == 5_800
                && FanControlPolicy.coolingTargetRPM(minimum: 5_800, maximum: 5_800,
                                                     level: 100) == nil,
               "manual targets map the full percentage scale into reported hardware bounds")
        expect(FanControlPolicy.targetRPMMatches(target: 3_121, expected: 3_121)
                && FanControlPolicy.targetRPMMatches(target: 3_122, expected: 3_121)
                && FanControlPolicy.targetRPMMatches(target: 1_201.5, expected: 1_200)
                && !FanControlPolicy.targetRPMMatches(target: 3_500, expected: 3_121)
                && !FanControlPolicy.targetRPMMatches(target: 1_205, expected: 1_200)
                && !FanControlPolicy.targetRPMMatches(target: .nan, expected: 1_200),
               "fan target verification allows a narrow tolerance and rejects stale or malformed targets")

        let defaultCurve = FanControlConfiguration.defaultCurve
        expect(FanControlPolicy.validConfiguration(.manual(level: 0))
                && FanControlPolicy.validConfiguration(.manual(level: 100))
                && FanControlPolicy.validConfiguration(.curve([defaultCurve]))
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 40) == 0
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 60) == 50
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 61) == 55
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 80) == 100,
               "the default curve starts at 50 degrees, reaches maximum at 70 and rounds safely up")
        let coolingTemperature = [
            FanControlTemperatureReading(source: .hottestSoC, celsius: 59),
        ]
        expect(FanControlPolicy.curveCoolingLevel(curves: [defaultCurve],
                                                  temperatures: coolingTemperature,
                                                  previousLevel: 50) == 50
                && FanControlPolicy.curveCoolingLevel(
                    curves: [defaultCurve],
                    temperatures: [.init(source: .hottestSoC, celsius: 57)],
                    previousLevel: 50
                ) == 45,
               "a cooling curve uses two-degree hysteresis before lowering fan speed")
        let cpuCurve = FanControlCurve(
            sensor: .averageCPU,
            points: [FanControlCurvePoint(temperature: 40, coolingLevel: 0),
                     FanControlCurvePoint(temperature: 80, coolingLevel: 80)]
        )
        let curveTemperatures = [
            FanControlTemperatureReading(source: .hottestSoC, celsius: 54),
            FanControlTemperatureReading(source: .averageCPU, celsius: 70),
        ]
        expect(FanControlPolicy.curveCoolingLevel(curves: [defaultCurve, cpuCurve],
                                                  temperatures: curveTemperatures) == 60
                && FanControlPolicy.curveCoolingLevel(curves: [defaultCurve, cpuCurve],
                                                      temperatures: [curveTemperatures[0]]) == nil,
               "several temperature rules use their highest demand and require every selected sensor")
        let duplicateCurves = [defaultCurve,
                               FanControlCurve(sensor: .hottestSoC, points: cpuCurve.points)]
        let descendingCurve = FanControlCurve(
            sensor: .averageCPU,
            points: [FanControlCurvePoint(temperature: 50, coolingLevel: 80),
                     FanControlCurvePoint(temperature: 70, coolingLevel: 40)]
        )
        expect(!FanControlPolicy.validCurves(duplicateCurves)
                && !FanControlPolicy.validCurves([descendingCurve])
                && FanControlConfiguration.decodeCurves(
                    FanControlConfiguration.encodeCurves([defaultCurve]) ?? "") == [defaultCurve]
                && FanControlConfiguration.decodeCurves("not json") == nil,
               "stored curves reject duplicate sensors, unsafe slopes and malformed data")
        let addedPoints = FanControlPolicy.addingCurvePoint(to: defaultCurve.points)
        expect(FanControlPolicy.nextCurvePoint(for: defaultCurve.points) == FanControlCurvePoint(temperature: 60, coolingLevel: 50)
                && addedPoints == [
                    FanControlCurvePoint(temperature: 50, coolingLevel: 0),
                    FanControlCurvePoint(temperature: 60, coolingLevel: 50),
                    FanControlCurvePoint(temperature: 70, coolingLevel: 100),
                ]
                && FanControlPolicy.validCurve(FanControlCurve(sensor: .hottestSoC, points: addedPoints ?? [])),
               "adding a fan curve point calculates the intermediate point and produces a valid sorted curve")
        var iterativePoints = defaultCurve.points
        while let next = FanControlPolicy.addingCurvePoint(to: iterativePoints) {
            iterativePoints = next
        }
        expect(iterativePoints.count == FanControlPolicy.maximumCurvePointCount
                && FanControlPolicy.validCurve(FanControlCurve(sensor: .hottestSoC, points: iterativePoints))
                && FanControlPolicy.nextCurvePoint(for: iterativePoints) == nil
                && FanControlPolicy.addingCurvePoint(to: iterativePoints) == nil,
               "adding fan curve points fills up to the maximum point limit with strictly valid curves")
        let secondCurve = FanControlCurve(sensor: .averageCPU,
                                          points: defaultCurve.points)
        var updatedCurves = [defaultCurve, secondCurve]
        if let secondPoints = FanControlPolicy.addingCurvePoint(to: updatedCurves[1].points) {
            updatedCurves[1].points = secondPoints
        }
        let storedUpdatedCurves = FanControlConfiguration.decodeCurves(
            FanControlConfiguration.encodeCurves(updatedCurves) ?? ""
        )
        expect(updatedCurves.count == 2
                && updatedCurves.first == defaultCurve
                && updatedCurves[1].points == addedPoints
                && storedUpdatedCurves == updatedCurves,
               "adding a point to the second fan curve preserves every valid stored curve")
        let m3FanTemperatures = FanControlPolicy.aggregatedTemperatures(
            cpuReadings: [("Te05", 44), ("Tf4E", 53), ("Tf4F", 76)],
            gpuReadings: [48],
            platform: .appleM3Family
        )
        expectClose(m3FanTemperatures.first { $0.source == .hottestCPU }?.celsius ?? -1,
                    53,
                    "M3 fan curves include the hottest mapped Tf CPU core")
        expectClose(m3FanTemperatures.first { $0.source == .averageCPU }?.celsius ?? -1,
                    48.5,
                    "M3 fan curves exclude auxiliary Tf readings from the CPU average")
        let unmappedFanTemperatures = FanControlPolicy.aggregatedTemperatures(
            cpuReadings: [("Tp00", 48), ("Tp0W", 113)],
            gpuReadings: [],
            platform: .unmappedAppleSilicon
        )
        expect(unmappedFanTemperatures.isEmpty,
               "fan curves reject unknown Apple Silicon sensors instead of treating them as CPU")
        expect(FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [1_200]) == [1_200]
                && FanControlPolicy.telemetryReadings(expectedCount: 2,
                                                      readings: [1_200, 1_350]) == [1_200, 1_350],
               "fan telemetry preserves one or several ordered readings")
        expect(FanControlPolicy.telemetryReadings(expectedCount: 0, readings: []) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 2, readings: [1_200]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 2, readings: [1_200, nil]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [.infinity]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [-1]) == nil,
               "fan telemetry rejects no-fan, missing and malformed sensor sets")
        expect(FanControlPolicy.menuBarValue(for: [1_249.6]) == "1250"
                && FanControlPolicy.menuBarValue(for: [1_200, 1_350]) == "1200/1350"
                && FanControlPolicy.menuBarValue(for: []) == nil
                && FanControlPolicy.menuBarValue(for: [.infinity]) == nil,
               "fan RPM menu bar text supports one or several validated fans")
        expect(FanControlPolicy.menuBarWidthUnits(fanCount: 1) == 12
                && FanControlPolicy.menuBarWidthUnits(fanCount: 2) == 18
                && FanControlPolicy.menuBarWidthUnits(fanCount: 0) == 0,
               "fan RPM menu bar width reserves one or several five-digit readings")

        let floatRPM = SMCValueCodec.encode(4_850, type: "flt ", size: 4)
        expect(floatRPM.flatMap { SMCValueCodec.decode($0, type: "flt ") } == 4_850,
               "native fan RPM floats round-trip exactly")
        let fixedRPM = SMCValueCodec.encode(4_850.25, type: "fpe2", size: 2)
        expect(fixedRPM.flatMap { SMCValueCodec.decode($0, type: "fpe2") } == 4_850.25,
               "fixed-point fan RPM values round-trip at quarter-RPM precision")
        expect(SMCValueCodec.decode([0x12, 0x34], type: "ui16") == 0x1234
                && SMCValueCodec.decode([0, 0, 1, 2], type: "ui32") == 258
                && SMCValueCodec.encode(1, type: "ui8 ", size: 1) == [1],
               "SMC integer types preserve their documented byte order")
        expect(SMCValueCodec.encode(-1, type: "flt ", size: 4) == nil
                && SMCValueCodec.encode(30_000, type: "fpe2", size: 2) == nil
                && SMCValueCodec.encode(1, type: "myst", size: 1) == nil,
               "SMC writes reject negative, overflowing and unknown encodings")

        let watchdogEnd = Date(timeIntervalSince1970: 2_000)
        expect(FanControlPolicy.restoreReason(now: watchdogEnd,
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == .timeLimit,
               "the watchdog still honors a deadline from a legacy helper request")
        expect(FanControlPolicy.restoreReason(now: watchdogEnd,
                                              endsAt: nil,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == nil,
               "current manual and curve control have no arbitrary time limit")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: FanControlPolicy.heartbeatLimit + 0.1,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == .heartbeatLost,
               "the watchdog restores when the app heartbeat stops")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: FanControlPolicy.verificationFailureLimit,
                                              thermalState: .nominal) == .hardwareChanged,
               "the watchdog restores after repeated hardware verification failures")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              temperatureFailures: FanControlPolicy.temperatureFailureLimit,
                                              thermalState: .nominal) == .temperatureUnavailable,
               "a curve returns control after repeated missing temperature readings")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .serious) == .thermalPressure,
               "the watchdog returns control to the system under thermal pressure")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .fair) == nil,
               "a fair thermal state does not cancel the user's selected control")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == nil,
               "a healthy maximum-cooling session remains active")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.fanControl(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 42 && values.allSatisfy { !$0.isEmpty },
                   "fan control has every localized field for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "fan control text uses human punctuation for \(language.rawValue)")
            expectFormat(strings.fanNameFormat, ["d"],
                         "fan name format stays valid for \(language.rawValue)")
            expectFormat(strings.rpmFormat, ["d"],
                         "fan speed format stays valid for \(language.rawValue)")
            expectFormat(strings.currentRPMFormat, ["d"],
                         "current fan speed format stays valid for \(language.rawValue)")
            expectFormat(strings.targetRPMFormat, ["d"],
                         "target fan speed format stays valid for \(language.rawValue)")
        }
        expect(FanControlFeatureStrings.ru.rpmFormat == "%d об/мин"
                && FanControlFeatureStrings.de.rpmFormat == "%d U/min"
                && FanControlFeatureStrings.fr.rpmFormat == "%d tr/min",
               "existing localized RPM units stay intact")

        let legacyFanSnapshot = Data(#"{"fans":[],"isCooling":false}"#.utf8)
        let decodedLegacyFanSnapshot = try? JSONDecoder().decode(FanControlSnapshot.self,
                                                                  from: legacyFanSnapshot)
        expect(decodedLegacyFanSnapshot != nil
                && decodedLegacyFanSnapshot?.coolingLevel == nil
                && decodedLegacyFanSnapshot?.configuration == nil
                && decodedLegacyFanSnapshot?.temperatures == nil,
               "fan snapshots remain compatible with an older installed helper")

        let fanMigrationSuite = "com.vorssaint.tests.fan-migration.\(UUID().uuidString)"
        if let fanMigration = UserDefaults(suiteName: fanMigrationSuite) {
            fanMigration.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            expect(fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && fanMigration.bool(forKey: AppFeature.fanControl.availabilityKey)
                    && fanMigration.object(forKey: DefaultsKey.monitorShowFanControlBeta) == nil,
                   "an old fan opt-in keeps the feature installed and visible")

            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
            fanMigration.set(false, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            expect(!fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && fanMigration.object(forKey: AppFeature.fanControl.availabilityKey) == nil,
                   "an old fan opt-out does not install the feature")

            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
            fanMigration.set(false, forKey: DefaultsKey.panelShowFanControl)
            fanMigration.set(false, forKey: AppFeature.fanControl.availabilityKey)
            fanMigration.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            expect(!fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && !fanMigration.bool(forKey: AppFeature.fanControl.availabilityKey),
                   "newer fan choices win over the legacy opt-in")
            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
        } else {
            expect(false, "fan visibility migration suite can be created")
        }
    }
}
