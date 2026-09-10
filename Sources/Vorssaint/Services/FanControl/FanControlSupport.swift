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
}

/// How long a manual-mode session runs before it reverts on its own.
/// `untilChanged` means no automatic expiry, matching the behavior manual
/// mode already had before this type existed. The helper is the only thing
/// that enforces this (see `FanControlPolicy.sessionDuration` and the
/// `endsAt`/watchdog mechanism it already had for the legacy fixed session),
/// so picking a case here never needs a second, app-side timer.
enum FanControlManualDuration: String, Codable, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case untilChanged

    var id: String { rawValue }

    /// `nil` means no automatic expiry.
    var seconds: TimeInterval? {
        switch self {
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .untilChanged: return nil
        }
    }
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
    /// Only meaningful in `.manual` mode; ignored otherwise.
    var manualDuration: FanControlManualDuration

    static let defaultCurve = FanControlCurve(
        sensor: .hottestSoC,
        points: [
            FanControlCurvePoint(temperature: 50, coolingLevel: 0),
            FanControlCurvePoint(temperature: 70, coolingLevel: 100),
        ]
    )

    static func manual(level: Int,
                       duration: FanControlManualDuration = .untilChanged) -> FanControlConfiguration {
        FanControlConfiguration(mode: .manual, manualLevel: level,
                                curves: [], manualDuration: duration)
    }

    static func curve(_ curves: [FanControlCurve]) -> FanControlConfiguration {
        FanControlConfiguration(mode: .curve,
                                manualLevel: FanControlPolicy.defaultCoolingLevel,
                                curves: curves, manualDuration: .untilChanged)
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

/// A named shortcut to a fan control configuration, selectable from the panel
/// with one click instead of walking through mode/level/duration/curve by
/// hand each time. `id` is stable storage identity (a built-in's is the fixed
/// `FanProfileBuiltIn.id`, a custom profile's is a UUID string minted once at
/// "Save as profile…" time); `name` is what the user sees for a custom
/// profile, but a built-in's displayed name always comes fresh from
/// `FanProfile.displayName(_:)` (in FanControlStrings.swift) so it
/// re-translates if the interface language changes after the profile was
/// seeded. This type stays free of `FanControlFeatureStrings` so it can keep
/// compiling into the privileged helper target, which links this file for
/// `FanControlConfiguration` but never needs UI strings.
struct FanProfile: Codable, Equatable, Identifiable, Sendable {
    /// Only one curve per profile: the panel and the built-in presets only
    /// ever need to snapshot the single curve that was actually running, so
    /// keeping a profile to one curve keeps switching and the settings list
    /// simple. (Fan control itself still supports several simultaneous
    /// curves; that combination just isn't something a one-click profile
    /// captures.)
    enum Kind: Codable, Equatable, Sendable {
        case system
        case manual(level: Int, duration: FanControlManualDuration)
        case curve(points: [FanControlCurvePoint], temperatureSource: FanControlTemperatureSource)
    }

    let id: String
    var name: String
    var kind: Kind
}

extension FanProfile {
    /// Which built-in this profile is, derived from `id` rather than a
    /// stored flag — so there is no separate bit that could ever disagree
    /// with the id about whether a profile is a built-in.
    var builtIn: FanProfileBuiltIn? {
        FanProfileBuiltIn.allCases.first { $0.id == id }
    }

    /// Built-ins are not renamable or deletable, only duplicable into an
    /// editable copy.
    var isBuiltIn: Bool { builtIn != nil }

    /// The configuration this profile applies — exactly as if the user had
    /// set mode/level/duration/curve to these values by hand.
    var configuration: FanControlConfiguration {
        switch kind {
        case .system:
            return FanControlConfiguration(mode: .system,
                                           manualLevel: FanControlPolicy.defaultCoolingLevel,
                                           curves: [], manualDuration: .untilChanged)
        case let .manual(level, duration):
            return .manual(level: level, duration: duration)
        case let .curve(points, temperatureSource):
            return .curve([FanControlCurve(sensor: temperatureSource, points: points)])
        }
    }

    /// Whether `configuration` is exactly what this profile would apply.
    /// Drives both the "apply" path (nothing to do if already active) and
    /// the panel's highlight (hand-edited controls that happen to match a
    /// profile again re-select it, without the app having to track that
    /// specially).
    func matches(_ configuration: FanControlConfiguration) -> Bool {
        self.configuration == configuration
    }

    /// A new custom profile that captures `configuration` under `name`, for
    /// the panel's "Save as profile…" action.
    static func makeCustom(id: String = UUID().uuidString,
                           name: String,
                           from configuration: FanControlConfiguration) -> FanProfile {
        let kind: Kind
        switch configuration.mode {
        case .system:
            kind = .system
        case .manual:
            kind = .manual(level: configuration.manualLevel, duration: configuration.manualDuration)
        case .curve:
            let curve = configuration.curves.first ?? FanControlConfiguration.defaultCurve
            kind = .curve(points: curve.points, temperatureSource: curve.sensor)
        }
        return FanProfile(id: id, name: name, kind: kind)
    }

    /// A duplicate of this profile as an editable custom copy, named with a
    /// caller-supplied label (typically the original's displayed name plus a
    /// "copy" suffix) — the only way to start editing a built-in.
    func duplicated(named name: String) -> FanProfile {
        FanProfile(id: UUID().uuidString, name: name, kind: kind)
    }

    /// The first stored profile whose configuration matches `configuration`,
    /// if any — what the panel highlights as active. Recomputed from the
    /// live controls rather than a separately tracked selection, so editing
    /// mode/level/duration/curve by hand deselects automatically unless the
    /// result happens to match a (possibly different) profile again.
    static func activeProfile(matching configuration: FanControlConfiguration,
                              in profiles: [FanProfile]) -> FanProfile? {
        profiles.first { $0.matches(configuration) }
    }

    static func encodeArray(_ profiles: [FanProfile]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes a stored profile array, silently dropping any entry whose
    /// `kind` this build does not recognize (e.g. one written by a future
    /// version and read by an older one) instead of losing every other
    /// profile because one entry failed to decode.
    static func decodeArray(_ value: String) -> [FanProfile] {
        guard let data = value.data(using: .utf8),
              let attempts = try? JSONDecoder().decode([FanProfileDecodeAttempt].self, from: data)
        else { return [] }
        return attempts.compactMap(\.profile)
    }
}

/// Decodes one profile in isolation so a single unrecognized `kind` cannot
/// fail the decode of the whole stored array the way a plain `[FanProfile]`
/// decode would.
private struct FanProfileDecodeAttempt: Decodable {
    let profile: FanProfile?
    init(from decoder: Decoder) throws {
        profile = try? FanProfile(from: decoder)
    }
}

/// The three presets every install ships with. Not editable or deletable —
/// `FanProfile.duplicated(named:)` is the only way to get an editable copy of
/// one — so they always exist as a safe, known-good baseline.
enum FanProfileBuiltIn: String, CaseIterable, Sendable {
    case silent
    case balanced
    case performance

    /// Stable storage identity; `FanProfile.builtIn` recognizes a profile as
    /// this built-in only by matching this exact id.
    var id: String { "builtin.\(rawValue)" }

    var kind: FanProfile.Kind {
        switch self {
        case .silent: return .manual(level: 25, duration: .untilChanged)
        case .balanced: return .system
        case .performance: return .manual(level: 75, duration: .untilChanged)
        }
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

    static func coolingTargetRPM(minimum: Double, maximum: Double,
                                 level: Int) -> Double? {
        guard validBounds(minimum: minimum, maximum: maximum),
              validCoolingLevel(level) else { return nil }
        return minimum + (maximum - minimum) * Double(level) / 100
    }

    /// The deadline the helper should enforce for a session started with this
    /// configuration. Only manual mode ever expires on its own; a curve keeps
    /// running until temperatures or the app say otherwise. Centralizing this
    /// keeps the app and the helper from independently answering the same
    /// question and disagreeing.
    static func sessionDuration(for configuration: FanControlConfiguration) -> TimeInterval? {
        guard configuration.mode == .manual else { return nil }
        return configuration.manualDuration.seconds
    }

    static func manualDurationElapsed(until: Date, now: Date) -> Bool {
        now >= until
    }

    /// Minutes left before a manual session's deadline, rounded up so the
    /// label never reads "0 min left" while control is still active, and
    /// `nil` once (or before) the deadline to signal there is nothing to show.
    static func remainingManualMinutes(until: Date?, now: Date) -> Int? {
        guard let until, until > now else { return nil }
        return max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// What a manual override should hand control back to once its timer
    /// expires: the curve it interrupted, or the system if nothing was
    /// actively running (or the interrupted mode was already system control).
    static func modeAfterManualExpiry(previousMode: FanControlMode?) -> FanControlMode {
        previousMode == .curve ? .curve : .system
    }

    /// What "previous mode" a timed manual override should remember, captured
    /// once when the override begins so later tweaks (level, duration) while
    /// still in manual do not overwrite what it should return to.
    static func manualOverridePreviousMode(isCooling: Bool,
                                           activeMode: FanControlMode?) -> FanControlMode {
        (isCooling && activeMode == .curve) ? .curve : .system
    }

    static func validConfiguration(_ configuration: FanControlConfiguration) -> Bool {
        switch configuration.mode {
        case .system:
            return true
        case .manual:
            return validCoolingLevel(configuration.manualLevel)
        case .curve:
            return validCurves(configuration.curves)
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
