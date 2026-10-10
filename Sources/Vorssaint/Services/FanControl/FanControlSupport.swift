// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FanControlFanReading: Codable, Equatable, Identifiable, Sendable {
    let index: Int
    let actualRPM: Double
    let minimumRPM: Double
    let maximumRPM: Double
    let targetRPM: Double
    let isManuallyControlled: Bool

    var id: Int { index }
}

enum FanControlMode: String, Codable, Sendable {
    case system
    case manual
    case curve
    case adaptive
}

enum FanControlTemperatureSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case averageSoC
    case hottestSoC
    case averageCPU
    case hottestCPU
    case hottestGPU

    var id: String { rawValue }
}

struct FanControlTemperatureReading: Codable, Equatable, Sendable {
    let source: FanControlTemperatureSource
    let celsius: Double
}

struct FanControlCurvePoint: Codable, Equatable, Sendable {
    var temperature: Int
    var coolingLevel: Int
}

struct FanControlCurve: Codable, Equatable, Sendable {
    var sensor: FanControlTemperatureSource
    var points: [FanControlCurvePoint]
}

struct FanControlConfiguration: Codable, Equatable, Sendable {
    var mode: FanControlMode
    var manualLevel: Int
    var curves: [FanControlCurve]
    var adaptive: FanControlAdaptiveSettings = .balanced

    init(mode: FanControlMode,
         manualLevel: Int,
         curves: [FanControlCurve],
         adaptive: FanControlAdaptiveSettings = .balanced) {
        self.mode = mode
        self.manualLevel = manualLevel
        self.curves = curves
        self.adaptive = adaptive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(FanControlMode.self, forKey: .mode)
        manualLevel = try container.decode(Int.self, forKey: .manualLevel)
        curves = try container.decode([FanControlCurve].self, forKey: .curves)
        // Resume records and requests written before adaptive control carry
        // no tuning.
        adaptive = try container.decodeIfPresent(FanControlAdaptiveSettings.self,
                                                 forKey: .adaptive) ?? .balanced
    }

    static let defaultCurve = FanControlCurve(
        sensor: .hottestSoC,
        points: [
            FanControlCurvePoint(temperature: 50, coolingLevel: 0),
            FanControlCurvePoint(temperature: 70, coolingLevel: 100),
        ]
    )

    static func manual(level: Int) -> FanControlConfiguration {
        FanControlConfiguration(mode: .manual, manualLevel: level,
                                curves: [])
    }

    static func curve(_ curves: [FanControlCurve]) -> FanControlConfiguration {
        FanControlConfiguration(mode: .curve,
                                manualLevel: FanControlPolicy.defaultCoolingLevel,
                                curves: curves)
    }

    static func adaptive(
        _ settings: FanControlAdaptiveSettings = .balanced
    ) -> FanControlConfiguration {
        FanControlConfiguration(mode: .adaptive,
                                manualLevel: FanControlPolicy.defaultCoolingLevel,
                                curves: [],
                                adaptive: settings)
    }

    static func encodeCurves(_ curves: [FanControlCurve]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(curves) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decodeCurves(_ value: String) -> [FanControlCurve]? {
        guard let data = value.data(using: .utf8),
              let curves = try? JSONDecoder().decode([FanControlCurve].self, from: data),
              FanControlPolicy.validCurves(curves) else { return nil }
        return curves
    }

    static var defaultCurvesStorage: String {
        encodeCurves([defaultCurve]) ?? "[]"
    }
}

struct FanControlSnapshot: Codable, Equatable, Sendable {
    var fans: [FanControlFanReading]
    var isCooling: Bool
    var endsAt: Date?
    var stopReason: FanControlStopReason?
    var coolingLevel: Int?
    var configuration: FanControlConfiguration?
    var temperatures: [FanControlTemperatureReading]?

    static let empty = FanControlSnapshot(fans: [], isCooling: false,
                                          endsAt: nil, stopReason: nil,
                                          coolingLevel: nil,
                                          configuration: nil,
                                          temperatures: nil)
}

struct FanControlHistorySample: Codable, Equatable, Sendable {
    let timestamp: TimeInterval
    let temperature: Double
    let actualRPM: Double
    let targetRPM: Double
}

struct FanControlHistory {
    static let defaultCapacity = 10 * 60

    let capacity: Int
    private(set) var samples: [FanControlHistorySample] = []

    init(capacity: Int = FanControlHistory.defaultCapacity) {
        self.capacity = max(2, capacity)
    }

    mutating func append(_ sample: FanControlHistorySample) {
        samples.append(sample)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    mutating func append(snapshot: FanControlSnapshot,
                         timestamp: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard snapshot.isCooling,
              snapshot.configuration?.mode == .adaptive,
              let temperature = FanControlAdaptivePolicy.controlTemperature(
                  from: snapshot.temperatures ?? []
              ),
              !snapshot.fans.isEmpty else { return }

        let targetRPM = snapshot.fans.map(\.targetRPM).max() ?? 0
        let actualRPM = snapshot.fans.map(\.actualRPM).reduce(0, +)
            / Double(snapshot.fans.count)
        guard FanControlPolicy.validReading(temperature),
              FanControlPolicy.validReading(targetRPM),
              FanControlPolicy.validReading(actualRPM),
              targetRPM > 0 else { return }

        append(FanControlHistorySample(timestamp: timestamp,
                                       temperature: temperature,
                                       actualRPM: actualRPM,
                                       targetRPM: targetRPM))
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }
}

enum FanControlStopReason: String, Codable, Equatable, Sendable {
    case timeLimit
    case appDisconnected
    case heartbeatLost
    case hardwareChanged
    case thermalPressure
    case temperatureUnavailable
    case recovery
}

enum FanControlErrorCode: String, Codable, Equatable, Error, Sendable {
    case noFans
    case unsupportedHardware
    case alreadyControlled
    case authorizationRequired
    case helperUnavailable
    case controlFailed
}

struct FanControlResponse: Codable, Equatable, Sendable {
    let succeeded: Bool
    let snapshot: FanControlSnapshot
    let error: FanControlErrorCode?

    static func success(_ snapshot: FanControlSnapshot) -> FanControlResponse {
        FanControlResponse(succeeded: true, snapshot: snapshot, error: nil)
    }

    static func failure(_ error: FanControlErrorCode,
                        snapshot: FanControlSnapshot = .empty) -> FanControlResponse {
        FanControlResponse(succeeded: false, snapshot: snapshot, error: error)
    }
}

enum FanControlPolicy {
    /// Retained only for the legacy XPC entry point used by older app builds.
    static let coolingDuration: TimeInterval = 15 * 60
    static let heartbeatLimit: TimeInterval = 7
    static let verificationFailureLimit = 3
    static let temperatureFailureLimit = 3
    static let maximumFanCount = 8
    static let maximumSaneRPM = 20_000.0
    static let minimumCoolingLevel = 0
    static let maximumCoolingLevel = 100
    static let coolingLevelStep = 5
    static let defaultCoolingLevel = maximumCoolingLevel
    static let minimumCurveTemperature = 20
    static let maximumCurveTemperature = 110
    static let minimumCurvePointCount = 2
    static let maximumCurvePointCount = 8
    static let maximumCurveCount = FanControlTemperatureSource.allCases.count
    static let curveHysteresis = 2.0

    static func isAutomaticMode(_ mode: UInt8) -> Bool {
        mode == 0 || mode == 3
    }

    static func fanCount(from value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded = value.rounded()
        guard abs(value - rounded) < 0.001 else { return nil }
        let count = Int(rounded)
        return (1...maximumFanCount).contains(count) ? count : nil
    }

    static func validBounds(minimum: Double, maximum: Double) -> Bool {
        minimum.isFinite && maximum.isFinite
            && minimum >= 0 && maximum > minimum && maximum <= maximumSaneRPM
    }

    static func validReading(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumSaneRPM
    }

    static func validCoolingLevel(_ level: Int) -> Bool {
        (minimumCoolingLevel...maximumCoolingLevel).contains(level)
            && level.isMultiple(of: coolingLevelStep)
    }

    static func targetRPMMatches(target: Double, expected: Double) -> Bool {
        target.isFinite && expected.isFinite
            && abs(target - expected) <= max(2, expected * 0.001)
    }

    /// Not every Mac exposes `Ftst`. Where it is present the unlock write has to
    /// succeed; where it is absent there is nothing to force and nothing to fail.
    static func forceTestSatisfied(keyExists: Bool, writeSucceeded: Bool) -> Bool {
        !keyExists || writeSucceeded
    }

    static func coolingTargetRPM(minimum: Double, maximum: Double,
                                 level: Int) -> Double? {
        guard validBounds(minimum: minimum, maximum: maximum),
              validCoolingLevel(level) else { return nil }
        return minimum + (maximum - minimum) * Double(level) / 100
    }

    /// The adaptive target: a continuous share of each fan's own range, so
    /// fans with different limits move together like they do for a level.
    static func coolingTargetRPM(minimum: Double, maximum: Double,
                                 fraction: Double) -> Double? {
        guard validBounds(minimum: minimum, maximum: maximum),
              fraction.isFinite, (0...1).contains(fraction) else { return nil }
        return (minimum + (maximum - minimum) * fraction).rounded()
    }

    static func validConfiguration(_ configuration: FanControlConfiguration) -> Bool {
        switch configuration.mode {
        case .system:
            return true
        case .manual:
            return validCoolingLevel(configuration.manualLevel)
        case .curve:
            return validCurves(configuration.curves)
        case .adaptive:
            return configuration.curves.isEmpty
                && validCoolingLevel(configuration.manualLevel)
                && FanControlAdaptivePolicy.validSettings(configuration.adaptive)
        }
    }

    static func validCurves(_ curves: [FanControlCurve]) -> Bool {
        guard (1...maximumCurveCount).contains(curves.count),
              Set(curves.map(\.sensor)).count == curves.count else { return false }
        return curves.allSatisfy(validCurve)
    }

    static func validCurve(_ curve: FanControlCurve) -> Bool {
        guard (minimumCurvePointCount...maximumCurvePointCount).contains(curve.points.count) else {
            return false
        }
        for (index, point) in curve.points.enumerated() {
            guard (minimumCurveTemperature...maximumCurveTemperature).contains(point.temperature),
                  validCoolingLevel(point.coolingLevel) else { return false }
            if index > 0 {
                let previous = curve.points[index - 1]
                guard point.temperature > previous.temperature,
                      point.coolingLevel >= previous.coolingLevel else { return false }
            }
        }
        return true
    }

    static func nextCurvePoint(for points: [FanControlCurvePoint]) -> FanControlCurvePoint? {
        guard points.count < maximumCurvePointCount,
              let first = points.first,
              let last = points.last else { return nil }
        var best: (index: Int, gap: Int)?
        for index in 1..<points.count {
            let gap = points[index].temperature - points[index - 1].temperature
            if gap > 1, gap > (best?.gap ?? 0) { best = (index, gap) }
        }
        if let best {
            let lower = points[best.index - 1]
            let upper = points[best.index]
            let temperature = lower.temperature + best.gap / 2
            let rawLevel = Double(lower.coolingLevel + upper.coolingLevel) / 2
            let level = Int((rawLevel / Double(coolingLevelStep)).rounded())
                * coolingLevelStep
            return FanControlCurvePoint(temperature: temperature, coolingLevel: level)
        }
        if last.temperature < maximumCurveTemperature {
            return FanControlCurvePoint(
                temperature: min(maximumCurveTemperature, last.temperature + 10),
                coolingLevel: last.coolingLevel
            )
        }
        if first.temperature > minimumCurveTemperature {
            return FanControlCurvePoint(
                temperature: max(minimumCurveTemperature, first.temperature - 10),
                coolingLevel: first.coolingLevel
            )
        }
        return nil
    }

    static func addingCurvePoint(to points: [FanControlCurvePoint]) -> [FanControlCurvePoint]? {
        guard let point = nextCurvePoint(for: points) else { return nil }
        var updated = points
        updated.append(point)
        updated.sort { $0.temperature < $1.temperature }
        guard validCurve(FanControlCurve(sensor: .hottestSoC, points: updated)) else { return nil }
        return updated
    }

    static func curveCoolingLevel(curves: [FanControlCurve],
                                  temperatures: [FanControlTemperatureReading],
                                  previousLevel: Int? = nil) -> Int? {
        guard let requested = evaluatedCurveCoolingLevel(curves: curves,
                                                         temperatures: temperatures) else { return nil }
        guard let previousLevel, requested < previousLevel else { return requested }
        let warmerReadings = temperatures.map {
            FanControlTemperatureReading(source: $0.source,
                                         celsius: $0.celsius + curveHysteresis)
        }
        guard let held = evaluatedCurveCoolingLevel(curves: curves,
                                                    temperatures: warmerReadings) else { return nil }
        return min(previousLevel, max(requested, held))
    }

    private static func evaluatedCurveCoolingLevel(curves: [FanControlCurve],
                                                   temperatures: [FanControlTemperatureReading]) -> Int? {
        guard validCurves(curves) else { return nil }
        let values = Dictionary(temperatures.map { ($0.source, $0.celsius) },
                                uniquingKeysWith: { _, newest in newest })
        var levels: [Int] = []
        for curve in curves {
            guard let temperature = values[curve.sensor], validTemperature(temperature) else {
                return nil
            }
            levels.append(interpolatedCoolingLevel(points: curve.points,
                                                   temperature: temperature))
        }
        return levels.max()
    }

    static func interpolatedCoolingLevel(points: [FanControlCurvePoint],
                                         temperature: Double) -> Int {
        guard let first = points.first, let last = points.last else {
            return minimumCoolingLevel
        }
        if temperature <= Double(first.temperature) { return first.coolingLevel }
        if temperature >= Double(last.temperature) { return last.coolingLevel }
        for index in 1..<points.count {
            let upper = points[index]
            guard temperature <= Double(upper.temperature) else { continue }
            let lower = points[index - 1]
            let progress = (temperature - Double(lower.temperature))
                / Double(upper.temperature - lower.temperature)
            let raw = Double(lower.coolingLevel)
                + Double(upper.coolingLevel - lower.coolingLevel) * progress
            let stepped = Int(ceil(raw / Double(coolingLevelStep) - 1e-9))
                * coolingLevelStep
            return min(maximumCoolingLevel, max(minimumCoolingLevel, stepped))
        }
        return last.coolingLevel
    }

    static func validTemperature(_ value: Double) -> Bool {
        value.isFinite && value >= 1 && value < 125
    }

    static func aggregatedTemperatures(
        cpuReadings: [(key: String, value: Double)],
        gpuReadings: [Double],
        platform: CPUTemperaturePlatform
    ) -> [FanControlTemperatureReading] {
        let validCPU = cpuReadings.filter {
            $0.value >= TemperatureSensorSelector.minimumChipTemperature
                && validTemperature($0.value)
        }
        let preferredCPU = validCPU.filter {
            TemperatureSensorSelector.isCPUCoreKey($0.key, platform: platform)
        }
        let cpu: [Double]
        if TemperatureSensorSelector.hasCPUCoreSet(platform: platform) {
            cpu = preferredCPU.map(\.value)
        } else if platform == .generic {
            cpu = validCPU.map(\.value)
        } else {
            cpu = []
        }
        let gpu = gpuReadings.filter {
            $0 >= TemperatureSensorSelector.minimumChipTemperature && validTemperature($0)
        }
        let soc = cpu + gpu

        var readings: [FanControlTemperatureReading] = []
        if !soc.isEmpty {
            readings.append(.init(source: .averageSoC,
                                  celsius: soc.reduce(0, +) / Double(soc.count)))
            if let hottest = soc.max() {
                readings.append(.init(source: .hottestSoC, celsius: hottest))
            }
        }
        if !cpu.isEmpty {
            readings.append(.init(source: .averageCPU,
                                  celsius: cpu.reduce(0, +) / Double(cpu.count)))
            if let hottest = cpu.max() {
                readings.append(.init(source: .hottestCPU, celsius: hottest))
            }
        }
        if let hottest = gpu.max() {
            readings.append(.init(source: .hottestGPU, celsius: hottest))
        }
        return readings
    }

    static func telemetryReadings(expectedCount: Int,
                                  readings: [Double?]) -> [Double]? {
        guard (1...maximumFanCount).contains(expectedCount),
              readings.count == expectedCount else { return nil }
        let values = readings.compactMap { $0 }
        guard values.count == expectedCount,
              values.allSatisfy(validReading) else { return nil }
        return values
    }

    static func menuBarValue(for speeds: [Double]) -> String? {
        guard !speeds.isEmpty, speeds.allSatisfy(validReading) else { return nil }
        return speeds.map { String(Int($0.rounded())) }.joined(separator: "/")
    }

    static func menuBarWidthUnits(fanCount: Int) -> Int {
        guard (1...maximumFanCount).contains(fanCount) else { return 0 }
        return 7 + fanCount * 5 + (fanCount - 1)
    }

    static func restoreReason(now: Date,
                              endsAt: Date?,
                              heartbeatAge: TimeInterval,
                              verificationFailures: Int,
                              temperatureFailures: Int = 0,
                              thermalState: ProcessInfo.ThermalState) -> FanControlStopReason? {
        if let endsAt, now >= endsAt { return .timeLimit }
        if heartbeatAge > heartbeatLimit { return .heartbeatLost }
        if verificationFailures >= verificationFailureLimit { return .hardwareChanged }
        if temperatureFailures >= temperatureFailureLimit { return .temperatureUnavailable }
        if thermalState == .serious || thermalState == .critical {
            return .thermalPressure
        }
        return nil
    }
}

/// Adaptive tuning. Speeds are percentages of each fan's own range, like the
/// manual level, so one setting fits every Mac and every fan in it.
struct FanControlAdaptiveSettings: Codable, Equatable, Sendable {
    var sweetSpotLevel: Int
    var maximumLevel: Int
    var rampStartTemperature: Int
    var maximumTemperature: Int
    var sensitivity: FanControlAdaptiveSensitivity = .standard

    enum CodingKeys: String, CodingKey {
        case sweetSpotLevel, maximumLevel, rampStartTemperature, maximumTemperature, sensitivity
    }

    // Measured on an M1 Max in system mode, the firmware keeps the fans off
    // until the chip is near 90 degrees and then holds about 40% of their
    // range even at 100 degrees. Quiet sits close to that; the other two cool
    // progressively earlier and harder.
    static let quiet = FanControlAdaptiveSettings(sweetSpotLevel: 5, maximumLevel: 60,
                                                  rampStartTemperature: 75,
                                                  maximumTemperature: 100,
                                                  sensitivity: .relaxed)
    static let balanced = FanControlAdaptiveSettings(sweetSpotLevel: 10, maximumLevel: 80,
                                                     rampStartTemperature: 70,
                                                     maximumTemperature: 95)
    static let performance = FanControlAdaptiveSettings(sweetSpotLevel: 20, maximumLevel: 100,
                                                        rampStartTemperature: 60,
                                                        maximumTemperature: 85,
                                                        sensitivity: .responsive)
}

extension FanControlAdaptiveSettings {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sweetSpotLevel = try container.decode(Int.self, forKey: .sweetSpotLevel)
        maximumLevel = try container.decode(Int.self, forKey: .maximumLevel)
        rampStartTemperature = try container.decode(Int.self, forKey: .rampStartTemperature)
        maximumTemperature = try container.decode(Int.self, forKey: .maximumTemperature)
        // Tuning stored before sensitivity existed keeps the original response.
        sensitivity = try container.decodeIfPresent(FanControlAdaptiveSensitivity.self,
                                                    forKey: .sensitivity) ?? .standard
    }
}

/// How quickly the fans follow the temperature. The filters are time
/// constants rather than per-tick weights, so a late tick cannot change them.
/// Heat is followed sooner than it is let go: the fans answer a sustained load
/// in a few seconds, while a short compiler burst or sensor jitter does not
/// become audible fan hunting. Readings that already call for the maximum
/// speed skip all of this whatever the sensitivity.
struct FanControlAdaptiveResponse: Equatable, Sendable {
    let riseTimeConstant: Double
    // One core spikes for a moment under almost any load, so the hottest
    // sensor is slower to rise than the average.
    let hotspotTimeConstant: Double
    let fallTimeConstant: Double
    // Shares of the fan range per second.
    let maximumRisePerSecond: Double
    let maximumFallPerSecond: Double
}

enum FanControlAdaptiveSensitivity: String, Codable, CaseIterable, Identifiable, Sendable {
    case relaxed
    case standard
    case responsive

    var id: String { rawValue }

    var response: FanControlAdaptiveResponse {
        switch self {
        case .relaxed:
            return FanControlAdaptiveResponse(riseTimeConstant: 12, hotspotTimeConstant: 30,
                                              fallTimeConstant: 30,
                                              maximumRisePerSecond: 0.015,
                                              maximumFallPerSecond: 0.008)
        case .standard:
            return FanControlAdaptiveResponse(riseTimeConstant: 5, hotspotTimeConstant: 15,
                                              fallTimeConstant: 15,
                                              maximumRisePerSecond: 0.03,
                                              maximumFallPerSecond: 0.015)
        case .responsive:
            return FanControlAdaptiveResponse(riseTimeConstant: 2, hotspotTimeConstant: 8,
                                              fallTimeConstant: 10,
                                              maximumRisePerSecond: 0.06,
                                              maximumFallPerSecond: 0.025)
        }
    }
}

enum FanControlAdaptiveProfile: String, CaseIterable, Identifiable, Sendable {
    case quiet
    case balanced
    case performance

    var id: String { rawValue }

    var settings: FanControlAdaptiveSettings {
        switch self {
        case .quiet: return .quiet
        case .balanced: return .balanced
        case .performance: return .performance
        }
    }

    init?(matching settings: FanControlAdaptiveSettings) {
        guard let profile = Self.allCases.first(where: { $0.settings == settings }) else {
            return nil
        }
        self = profile
    }
}

enum FanControlAdaptivePolicy {
    static let levelStep = FanControlPolicy.coolingLevelStep
    static let minimumLevelSpan = 10
    static let sweetSpotLevelRange = 0...(FanControlPolicy.maximumCoolingLevel - minimumLevelSpan)
    static let maximumLevelRange = minimumLevelSpan...FanControlPolicy.maximumCoolingLevel
    static let minimumConfiguredTemperature = 45
    // Apple Silicon throttles a little above this, so a later maximum would
    // never be reached with the fans still ramping.
    static let maximumConfiguredTemperature = 100
    static let configuredTemperatureRange = minimumConfiguredTemperature...maximumConfiguredTemperature
    static let minimumTemperatureSpan = 8
    // The fans idle at their minimum this far below the ramp start and climb
    // to the sweet spot across it, so a cool Mac is as quiet as the hardware
    // allows instead of holding the sweet spot for nothing.
    static let quietTemperatureSpan = 10.0
    // The average hides one hot core or a busy GPU. Their hottest reading asks
    // for the same speed as the average curve once it runs this far above that
    // curve's thresholds. The usual spread between the hottest sensor and the
    // average therefore never changes the fan speed, but a hotspot cannot sit
    // at the sweet spot either.
    static let hotspotGuardOffset = 15.0
    // The guard reaches the maximum speed here at the latest, whatever the
    // configured thresholds, because the chip throttles soon after.
    static let hotspotCeilingTemperature = 100.0
    // A smaller change is not worth an SMC write. It only gates the write; the
    // demand behind it keeps moving.
    static let minimumLevelChange = 0.012
    static let bootstrapCoolingLevel = 10

    static func validSettings(_ settings: FanControlAdaptiveSettings) -> Bool {
        sweetSpotLevelRange.contains(settings.sweetSpotLevel)
            && maximumLevelRange.contains(settings.maximumLevel)
            && settings.maximumLevel - settings.sweetSpotLevel >= minimumLevelSpan
            && configuredTemperatureRange.contains(settings.rampStartTemperature)
            && configuredTemperatureRange.contains(settings.maximumTemperature)
            && settings.maximumTemperature - settings.rampStartTemperature
                >= minimumTemperatureSpan
    }

    /// Stored tuning that no longer validates falls back as a whole: a half
    /// repaired set of thresholds is not what the user chose either.
    static func normalized(_ settings: FanControlAdaptiveSettings) -> FanControlAdaptiveSettings {
        validSettings(settings) ? settings : .balanced
    }

    private static func hotspotGuardRange(
        _ settings: FanControlAdaptiveSettings
    ) -> (start: Double, end: Double) {
        let end = min(Double(settings.maximumTemperature) + hotspotGuardOffset,
                      hotspotCeilingTemperature)
        let start = min(Double(settings.rampStartTemperature) + hotspotGuardOffset,
                        end - Double(minimumTemperatureSpan))
        return (start, end)
    }

    /// The share of the fan range, from 0 to 1, the temperatures ask for.
    static func baseLevel(temperature: Double,
                          hotspotTemperature: Double? = nil,
                          settings: FanControlAdaptiveSettings = .balanced) -> Double? {
        guard FanControlPolicy.validTemperature(temperature),
              validSettings(settings) else { return nil }
        let sweetSpot = Double(settings.sweetSpotLevel) / 100
        let maximum = Double(settings.maximumLevel) / 100
        let rampStart = Double(settings.rampStartTemperature)
        // Linear from the sweet spot at `start` to the maximum at `end`.
        let rampAbove = { (celsius: Double, start: Double, end: Double) -> Double in
            if celsius >= end { return maximum }
            return sweetSpot + (maximum - sweetSpot) * (celsius - start) / (end - start)
        }

        var level: Double
        let quietTemperature = rampStart - quietTemperatureSpan
        if temperature <= quietTemperature {
            level = 0
        } else if temperature < rampStart {
            level = sweetSpot * (temperature - quietTemperature) / quietTemperatureSpan
        } else {
            level = rampAbove(temperature, rampStart, Double(settings.maximumTemperature))
        }

        // The guard only ever raises the level. Below its start it asks for
        // nothing, so it cannot nudge the quiet part of the curve either.
        if let hotspotTemperature, FanControlPolicy.validTemperature(hotspotTemperature) {
            let range = hotspotGuardRange(settings)
            if hotspotTemperature >= range.start {
                level = max(level, rampAbove(hotspotTemperature, range.start, range.end))
            }
        }
        return level
    }

    /// Whether the raw readings already call for the maximum speed. Such heat
    /// is not smoothed or ramped: the filters exist for noise, not for this.
    static func demandsMaximum(temperature: Double, hotspotTemperature: Double?,
                               settings: FanControlAdaptiveSettings) -> Bool {
        if temperature >= Double(settings.maximumTemperature) { return true }
        guard let hotspotTemperature,
              FanControlPolicy.validTemperature(hotspotTemperature) else { return false }
        return hotspotTemperature >= hotspotGuardRange(settings).end
    }

    /// Whether the hottest sensor, not the average, is setting the speed.
    static func hotspotLeads(_ readings: [FanControlTemperatureReading],
                             settings: FanControlAdaptiveSettings) -> Bool {
        guard let temperature = controlTemperature(from: readings),
              let hotspot = hotspotTemperature(from: readings),
              let guarded = baseLevel(temperature: temperature, hotspotTemperature: hotspot,
                                      settings: settings),
              let average = baseLevel(temperature: temperature, settings: settings) else {
            return false
        }
        return guarded > average
    }

    static func controlTemperature(from readings: [FanControlTemperatureReading]) -> Double? {
        let values = Dictionary(readings.map { ($0.source, $0.celsius) },
                                uniquingKeysWith: { _, newest in newest })
        let preferred: [FanControlTemperatureSource] = [
            // Macs Fan Control's matching preset uses CPU Core Average. Prefer
            // the same stable signal before considering hotspot sensors.
            .averageCPU, .averageSoC, .hottestCPU, .hottestSoC, .hottestGPU,
        ]
        for source in preferred {
            if let value = values[source], FanControlPolicy.validTemperature(value) {
                return value
            }
        }
        return nil
    }

    /// The hottest chip sensor, whether it is a CPU core or the GPU. The
    /// control temperature averages the cores and hides it by design.
    static func hotspotTemperature(from readings: [FanControlTemperatureReading]) -> Double? {
        let hottest: Set<FanControlTemperatureSource> = [.hottestSoC, .hottestCPU, .hottestGPU]
        return readings
            .filter { hottest.contains($0.source) && FanControlPolicy.validTemperature($0.celsius) }
            .map(\.celsius)
            .max()
    }
}

/// Converts the temperature readings into a share of the fan range. The
/// filters and slew limits keep sensor noise from becoming audible fan
/// hunting. They act on a demand that moves on every tick; the deadband only
/// decides whether a change is worth an SMC write, so it can never hold the
/// demand back. The hottest sensor is filtered the same way and raises the
/// demand when it runs far above the average.
final class FanControlAdaptiveController {
    private(set) var filteredTemperature: Double?
    private(set) var filteredHotspot: Double?
    /// The level last handed to the fans.
    private(set) var currentLevel: Double?
    private var demand: Double?
    private var lastUptime: TimeInterval?

    func reset() {
        filteredTemperature = nil
        filteredHotspot = nil
        currentLevel = nil
        demand = nil
        lastUptime = nil
    }

    private static func filtered(_ previous: Double?, toward value: Double,
                                 elapsed: TimeInterval,
                                 riseTimeConstant: Double,
                                 fallTimeConstant: Double) -> Double {
        guard let previous else { return value }
        let timeConstant = value > previous ? riseTimeConstant : fallTimeConstant
        let weight = 1 - exp(-elapsed / timeConstant)
        return previous + weight * (value - previous)
    }

    /// New settings take effect on the next call and keep the filters and the
    /// demand, so retuning a running control ramps instead of jumping.
    func nextLevel(temperatures: [FanControlTemperatureReading],
                   settings: FanControlAdaptiveSettings = .balanced,
                   now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double? {
        guard FanControlAdaptivePolicy.validSettings(settings),
              let temperature = FanControlAdaptivePolicy.controlTemperature(from: temperatures) else {
            return nil
        }
        let response = settings.sensitivity.response
        let hotspot = FanControlAdaptivePolicy.hotspotTemperature(from: temperatures)
        let urgent = FanControlAdaptivePolicy.demandsMaximum(temperature: temperature,
                                                             hotspotTemperature: hotspot,
                                                             settings: settings)

        let elapsed = lastUptime.map { min(max(now - $0, 0.25), 3.0) } ?? 1.0
        lastUptime = now
        let smoothedTemperature = urgent
            ? max(temperature, filteredTemperature ?? temperature)
            : Self.filtered(filteredTemperature, toward: temperature, elapsed: elapsed,
                            riseTimeConstant: response.riseTimeConstant,
                            fallTimeConstant: response.fallTimeConstant)
        filteredTemperature = smoothedTemperature
        // A tick without a hotspot reading simply goes without the guard.
        let smoothedHotspot = hotspot.map {
            urgent ? max($0, filteredHotspot ?? $0)
                   : Self.filtered(filteredHotspot, toward: $0, elapsed: elapsed,
                                   riseTimeConstant: response.hotspotTimeConstant,
                                   fallTimeConstant: response.fallTimeConstant)
        }
        if let smoothedHotspot { filteredHotspot = smoothedHotspot }

        guard let requested = FanControlAdaptivePolicy.baseLevel(
            temperature: smoothedTemperature,
            hotspotTemperature: smoothedHotspot,
            settings: settings
        ) else { return nil }

        let limited: Double
        if let demand, !urgent {
            let maximumRise = response.maximumRisePerSecond * elapsed
            let maximumFall = response.maximumFallPerSecond * elapsed
            limited = min(demand + maximumRise, max(demand - maximumFall, requested))
        } else {
            limited = requested
        }
        let maximum = Double(settings.maximumLevel) / 100
        // Not clamped to the configured maximum: a demand left above a lowered
        // maximum comes down at the fall rate like any other.
        let level = min(1, max(0, limited))
        demand = level

        // Hold back drift too small to write, but never strand the fans a
        // deadband short of either end of the range.
        if let currentLevel {
            let atEndPoint = level >= maximum || level <= 0
            let worthWriting = abs(level - currentLevel)
                >= FanControlAdaptivePolicy.minimumLevelChange
                || (atEndPoint && level != currentLevel)
            guard worthWriting else { return currentLevel }
        }
        currentLevel = level
        return level
    }
}

enum SMCValueCodec {
    static func decode(_ bytes: [UInt8], type: String) -> Double? {
        switch type {
        case "flt " where bytes.count == 4:
            let bits = UInt32(bytes[0])
                | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16
                | UInt32(bytes[3]) << 24
            let value = Double(Float32(bitPattern: bits))
            return value.isFinite ? value : nil
        case "fpe2" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4.0
        case "sp78" where bytes.count == 2:
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "ui8 " where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32" where bytes.count == 4:
            return Double(UInt32(bytes[0]) << 24
                          | UInt32(bytes[1]) << 16
                          | UInt32(bytes[2]) << 8
                          | UInt32(bytes[3]))
        case "ioft" where bytes.count == 8:
            var raw: UInt64 = 0
            for (offset, byte) in bytes.enumerated() {
                raw |= UInt64(byte) << UInt64(offset * 8)
            }
            return Double(raw) / 65_536.0
        default:
            return nil
        }
    }

    static func encode(_ value: Double, type: String, size: Int) -> [UInt8]? {
        guard value.isFinite, value >= 0 else { return nil }
        switch type {
        case "flt " where size == 4:
            let float = Float32(value)
            guard float.isFinite else { return nil }
            let bits = float.bitPattern
            return [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                    UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)]
        case "fpe2" where size == 2:
            let scaled = (value * 4).rounded()
            guard scaled <= Double(UInt16.max) else { return nil }
            let raw = UInt16(scaled)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui8 " where size == 1:
            guard value.rounded() == value, value <= Double(UInt8.max) else { return nil }
            return [UInt8(value)]
        case "ui16" where size == 2:
            guard value.rounded() == value, value <= Double(UInt16.max) else { return nil }
            let raw = UInt16(value)
            return [UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        case "ui32" where size == 4:
            guard value.rounded() == value, value <= Double(UInt32.max) else { return nil }
            let raw = UInt32(value)
            return [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff),
                    UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        default:
            return nil
        }
    }
}
